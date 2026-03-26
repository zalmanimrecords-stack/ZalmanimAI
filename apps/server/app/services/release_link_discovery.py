from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from html import unescape
from typing import Iterable
from urllib.parse import quote_plus, urlparse

import httpx
from sqlalchemy.orm import Session, joinedload

from app.models.models import Release, ReleaseLinkCandidate, ReleaseLinkScanRun


LINKTREE_PLATFORM_PRIORITY = (
    "spotify",
    "apple_music",
    "youtube",
    "beatport",
    "bandcamp",
    "deezer",
    "tidal",
    "amazon_music",
    "soundcloud",
)

SUPPORTED_RELEASE_LINK_PLATFORMS = (
    "spotify",
    "apple_music",
    "youtube",
    "soundcloud",
    "beatport",
    "bandcamp",
    "deezer",
    "tidal",
    "amazon_music",
)

AUTO_REJECT_CONFIDENCE = 0.34
REVIEW_MIN_CONFIDENCE = 0.45
SCAN_RETRY_INTERVAL = timedelta(days=1)
HTTP_TIMEOUT = 12.0


@dataclass
class DiscoveryCandidate:
    platform: str
    url: str
    match_title: str | None
    match_artist: str | None
    confidence: float
    source_type: str
    raw_payload: dict


@dataclass
class PlatformDiscoveryResult:
    platform: str
    status: str
    candidates: list[DiscoveryCandidate]
    error_message: str | None = None


class ReleaseLinkAdapter:
    platform: str = ""

    def discover(self, release_title: str, artist_names: list[str]) -> PlatformDiscoveryResult:
        raise NotImplementedError


def _normalize_text(value: str | None) -> str:
    value = unescape((value or "").strip().lower())
    value = re.sub(r"\([^)]*\)", " ", value)
    value = re.sub(r"\[[^\]]*\]", " ", value)
    value = re.sub(r"[^a-z0-9\u0590-\u05ff]+", " ", value)
    return " ".join(value.split())


def _contains_version_noise(value: str | None) -> bool:
    normalized = _normalize_text(value)
    return any(
        token in normalized
        for token in (
            "remix",
            "edit",
            "mix",
            "version",
            "live",
            "karaoke",
            "instrumental",
            "sped up",
            "slowed",
        )
    )


def _token_set(value: str | None) -> set[str]:
    return {token for token in _normalize_text(value).split() if len(token) >= 2}


def _title_similarity(expected: str, actual: str | None) -> float:
    expected_tokens = _token_set(expected)
    actual_tokens = _token_set(actual)
    if not expected_tokens or not actual_tokens:
        return 0.0
    overlap = len(expected_tokens & actual_tokens) / max(len(expected_tokens), 1)
    if _normalize_text(expected) == _normalize_text(actual):
        overlap = max(overlap, 1.0)
    return min(overlap, 1.0)


def _artist_similarity(expected_artists: Iterable[str], actual: str | None) -> float:
    actual_norm = _normalize_text(actual)
    if not actual_norm:
        return 0.0
    scores: list[float] = []
    for artist in expected_artists:
        artist_norm = _normalize_text(artist)
        if not artist_norm:
            continue
        if artist_norm == actual_norm or artist_norm in actual_norm or actual_norm in artist_norm:
            scores.append(1.0)
            continue
        expected_tokens = set(artist_norm.split())
        actual_tokens = set(actual_norm.split())
        if expected_tokens:
            scores.append(len(expected_tokens & actual_tokens) / len(expected_tokens))
    return max(scores) if scores else 0.0


def _official_domain_bonus(url: str, platform: str) -> float:
    host = (urlparse(url).netloc or "").lower()
    expected = {
        "spotify": ("spotify.com",),
        "apple_music": ("music.apple.com", "itunes.apple.com"),
        "youtube": ("youtube.com", "youtu.be", "music.youtube.com"),
        "soundcloud": ("soundcloud.com", "on.soundcloud.com"),
        "beatport": ("beatport.com",),
        "bandcamp": ("bandcamp.com",),
        "deezer": ("deezer.com",),
        "tidal": ("tidal.com",),
        "amazon_music": ("amazon.", "music.amazon."),
    }.get(platform, ())
    return 0.1 if any(part in host for part in expected) else 0.0


def compute_candidate_confidence(
    release_title: str,
    artist_names: list[str],
    candidate_title: str | None,
    candidate_artist: str | None,
    url: str,
    platform: str,
) -> float:
    title_score = _title_similarity(release_title, candidate_title)
    artist_score = _artist_similarity(artist_names, candidate_artist)
    confidence = (title_score * 0.65) + (artist_score * 0.25) + _official_domain_bonus(url, platform)
    if candidate_title and _contains_version_noise(candidate_title) and not _contains_version_noise(release_title):
        confidence -= 0.18
    if candidate_artist and artist_names and artist_score < 0.2:
        confidence -= 0.15
    if "/search" in url or "search?" in url:
        confidence -= 0.25
    return max(0.0, min(confidence, 1.0))


def parse_platform_links(raw: str | None) -> dict[str, str]:
    try:
        data = json.loads(raw or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {
        str(key): str(value).strip()
        for key, value in data.items()
        if str(key).strip() and str(value).strip()
    }


def best_release_link(platform_links: dict[str, str]) -> str | None:
    for platform in LINKTREE_PLATFORM_PRIORITY:
        if platform_links.get(platform):
            return platform_links[platform]
    for _, url in platform_links.items():
        if url:
            return url
    return None


def _candidate_from_payload(
    *,
    platform: str,
    url: str,
    release_title: str,
    artist_names: list[str],
    candidate_title: str | None,
    candidate_artist: str | None,
    source_type: str,
    raw_payload: dict,
) -> DiscoveryCandidate:
    confidence = compute_candidate_confidence(
        release_title,
        artist_names,
        candidate_title,
        candidate_artist,
        url,
        platform,
    )
    return DiscoveryCandidate(
        platform=platform,
        url=url,
        match_title=candidate_title,
        match_artist=candidate_artist,
        confidence=confidence,
        source_type=source_type,
        raw_payload=raw_payload,
    )


class ItunesSearchAdapter(ReleaseLinkAdapter):
    platform = "apple_music"

    def discover(self, release_title: str, artist_names: list[str]) -> PlatformDiscoveryResult:
        artist = artist_names[0] if artist_names else ""
        query = f'{release_title} {artist}'.strip()
        try:
            response = httpx.get(
                "https://itunes.apple.com/search",
                params={"term": query, "entity": "album", "limit": 5},
                timeout=HTTP_TIMEOUT,
                follow_redirects=True,
                headers={"User-Agent": "LabelOps/1.0"},
            )
            response.raise_for_status()
            payload = response.json()
        except Exception as exc:
            return PlatformDiscoveryResult(platform=self.platform, status="failed", candidates=[], error_message=str(exc))
        candidates: list[DiscoveryCandidate] = []
        for item in payload.get("results", []) or []:
            url = str(item.get("collectionViewUrl") or item.get("trackViewUrl") or "").strip()
            if not url:
                continue
            candidates.append(
                _candidate_from_payload(
                    platform=self.platform,
                    url=url,
                    release_title=release_title,
                    artist_names=artist_names,
                    candidate_title=item.get("collectionName") or item.get("trackName"),
                    candidate_artist=item.get("artistName"),
                    source_type="api",
                    raw_payload={"provider": "itunes_search", "item": item},
                )
            )
        return PlatformDiscoveryResult(platform=self.platform, status="ok", candidates=candidates)


class DeezerSearchAdapter(ReleaseLinkAdapter):
    platform = "deezer"

    def discover(self, release_title: str, artist_names: list[str]) -> PlatformDiscoveryResult:
        artist = artist_names[0] if artist_names else ""
        query = f'album:"{release_title}" artist:"{artist}"'.strip()
        try:
            response = httpx.get(
                "https://api.deezer.com/search",
                params={"q": query},
                timeout=HTTP_TIMEOUT,
                follow_redirects=True,
                headers={"User-Agent": "LabelOps/1.0"},
            )
            response.raise_for_status()
            payload = response.json()
        except Exception as exc:
            return PlatformDiscoveryResult(platform=self.platform, status="failed", candidates=[], error_message=str(exc))
        candidates: list[DiscoveryCandidate] = []
        for item in payload.get("data", []) or []:
            album = item.get("album") or {}
            album_title = album.get("title")
            url = str(album.get("link") or item.get("link") or "").strip()
            if not url:
                continue
            artist_name = ""
            if isinstance(item.get("artist"), dict):
                artist_name = str(item["artist"].get("name") or "")
            candidates.append(
                _candidate_from_payload(
                    platform=self.platform,
                    url=url,
                    release_title=release_title,
                    artist_names=artist_names,
                    candidate_title=album_title or item.get("title"),
                    candidate_artist=artist_name,
                    source_type="api",
                    raw_payload={"provider": "deezer_search", "item": item},
                )
            )
        return PlatformDiscoveryResult(platform=self.platform, status="ok", candidates=candidates)


class DuckDuckGoWebSearchAdapter(ReleaseLinkAdapter):
    def __init__(self, platform: str, allowed_domains: tuple[str, ...]) -> None:
        self.platform = platform
        self.allowed_domains = allowed_domains

    def discover(self, release_title: str, artist_names: list[str]) -> PlatformDiscoveryResult:
        artist = artist_names[0] if artist_names else ""
        domains_part = " OR ".join(f"site:{domain}" for domain in self.allowed_domains)
        query = f'{domains_part} "{release_title}" "{artist}"'.strip()
        try:
            response = httpx.get(
                "https://duckduckgo.com/html/",
                params={"q": query},
                timeout=HTTP_TIMEOUT,
                follow_redirects=True,
                headers={"User-Agent": "LabelOps/1.0"},
            )
            response.raise_for_status()
        except Exception as exc:
            return PlatformDiscoveryResult(platform=self.platform, status="failed", candidates=[], error_message=str(exc))

        candidates: list[DiscoveryCandidate] = []
        pattern = re.compile(
            r'<a[^>]+class="result__a"[^>]+href="(?P<url>[^"]+)"[^>]*>(?P<title>.*?)</a>',
            re.IGNORECASE | re.DOTALL,
        )
        snippet_pattern = re.compile(
            r'<a[^>]+class="result__a"[^>]+href="[^"]+"[^>]*>.*?</a>(?P<rest>.*?)</div>',
            re.IGNORECASE | re.DOTALL,
        )
        seen_urls: set[str] = set()
        for match in pattern.finditer(response.text):
            url = unescape(match.group("url")).strip()
            if not url or url in seen_urls:
                continue
            host = (urlparse(url).netloc or "").lower()
            if not any(domain in host for domain in self.allowed_domains):
                continue
            seen_urls.add(url)
            title_html = re.sub(r"<[^>]+>", " ", match.group("title"))
            title_text = " ".join(unescape(title_html).split())
            rest_match = snippet_pattern.search(response.text[match.start():match.start() + 1200])
            snippet_text = ""
            if rest_match:
                snippet_text = " ".join(
                    unescape(re.sub(r"<[^>]+>", " ", rest_match.group("rest"))).split()
                )
            candidates.append(
                _candidate_from_payload(
                    platform=self.platform,
                    url=url,
                    release_title=release_title,
                    artist_names=artist_names,
                    candidate_title=title_text,
                    candidate_artist=snippet_text,
                    source_type="web_search",
                    raw_payload={"provider": "duckduckgo_html", "title": title_text, "snippet": snippet_text},
                )
            )
            if len(candidates) >= 5:
                break
        return PlatformDiscoveryResult(platform=self.platform, status="ok", candidates=candidates)


def _build_adapter_registry() -> dict[str, ReleaseLinkAdapter]:
    return {
        "apple_music": ItunesSearchAdapter(),
        "deezer": DeezerSearchAdapter(),
        "spotify": DuckDuckGoWebSearchAdapter("spotify", ("open.spotify.com",)),
        "youtube": DuckDuckGoWebSearchAdapter("youtube", ("music.youtube.com", "youtube.com")),
        "soundcloud": DuckDuckGoWebSearchAdapter("soundcloud", ("soundcloud.com", "on.soundcloud.com")),
        "beatport": DuckDuckGoWebSearchAdapter("beatport", ("beatport.com",)),
        "bandcamp": DuckDuckGoWebSearchAdapter("bandcamp", ("bandcamp.com",)),
        "tidal": DuckDuckGoWebSearchAdapter("tidal", ("tidal.com",)),
        "amazon_music": DuckDuckGoWebSearchAdapter("amazon_music", ("music.amazon.", "amazon.")),
    }


ADAPTER_REGISTRY = _build_adapter_registry()


def discover_release_links(
    release_title: str,
    artist_names: list[str],
    *,
    platforms: list[str] | None = None,
) -> list[PlatformDiscoveryResult]:
    requested = platforms or list(SUPPORTED_RELEASE_LINK_PLATFORMS)
    results: list[PlatformDiscoveryResult] = []
    for platform in requested:
        adapter = ADAPTER_REGISTRY.get(platform)
        if adapter is None:
            results.append(
                PlatformDiscoveryResult(
                    platform=platform,
                    status="unsupported",
                    candidates=[],
                    error_message="No adapter configured for this platform.",
                )
            )
            continue
        results.append(adapter.discover(release_title, artist_names))
    return results


def _serialize_platform_list(platforms: list[str] | None) -> str:
    return json.dumps(list(platforms or []))


def queue_release_link_scan(
    db: Session,
    *,
    release_id: int,
    trigger_type: str,
    requested_by_user_id: int | None = None,
    platforms: list[str] | None = None,
) -> ReleaseLinkScanRun:
    open_run = (
        db.query(ReleaseLinkScanRun)
        .filter(
            ReleaseLinkScanRun.release_id == release_id,
            ReleaseLinkScanRun.status.in_(("queued", "running")),
        )
        .order_by(ReleaseLinkScanRun.created_at.desc(), ReleaseLinkScanRun.id.desc())
        .first()
    )
    if open_run:
        if platforms:
            open_run.platforms_json = _serialize_platform_list(platforms)
        return open_run
    run = ReleaseLinkScanRun(
        release_id=release_id,
        status="queued",
        trigger_type=trigger_type,
        requested_by_user_id=requested_by_user_id,
        platforms_json=_serialize_platform_list(platforms),
        summary_json="{}",
    )
    db.add(run)
    db.flush()
    return run


def _platforms_from_run(run: ReleaseLinkScanRun) -> list[str] | None:
    try:
        data = json.loads(run.platforms_json or "[]") or []
    except (json.JSONDecodeError, TypeError):
        return None
    if not isinstance(data, list):
        return None
    values = [str(item).strip() for item in data if str(item).strip()]
    return values or None


def _release_artist_names(release: Release) -> list[str]:
    names = [str(artist.name).strip() for artist in getattr(release, "artists", []) or [] if str(getattr(artist, "name", "")).strip()]
    if not names and getattr(release, "artist", None) is not None and getattr(release.artist, "name", None):
        names = [str(release.artist.name).strip()]
    return names


def _has_pending_review_candidates(release: Release) -> bool:
    return any(
        getattr(candidate, "status", "") == "pending_review"
        for candidate in (getattr(release, "link_candidates", None) or [])
    )


def _upsert_release_link_candidate(
    db: Session,
    *,
    release: Release,
    candidate: DiscoveryCandidate,
) -> ReleaseLinkCandidate:
    existing = (
        db.query(ReleaseLinkCandidate)
        .filter(
            ReleaseLinkCandidate.release_id == release.id,
            ReleaseLinkCandidate.platform == candidate.platform,
            ReleaseLinkCandidate.url == candidate.url,
        )
        .first()
    )
    serialized_payload = json.dumps(candidate.raw_payload or {})
    if existing:
        existing.match_title = candidate.match_title
        existing.match_artist = candidate.match_artist
        existing.confidence = max(float(existing.confidence or 0.0), candidate.confidence)
        existing.source_type = candidate.source_type
        existing.raw_payload_json = serialized_payload
        if existing.status == "pending_review" and existing.confidence < AUTO_REJECT_CONFIDENCE:
            existing.status = "auto_rejected"
        return existing
    status = "pending_review" if candidate.confidence >= REVIEW_MIN_CONFIDENCE else "auto_rejected"
    row = ReleaseLinkCandidate(
        release_id=release.id,
        platform=candidate.platform,
        url=candidate.url,
        match_title=candidate.match_title,
        match_artist=candidate.match_artist,
        confidence=candidate.confidence,
        status=status,
        source_type=candidate.source_type,
        raw_payload_json=serialized_payload,
    )
    db.add(row)
    db.flush()
    return row


def _scan_summary(results: list[PlatformDiscoveryResult]) -> dict:
    return {
        "platforms": [
            {
                "platform": result.platform,
                "status": result.status,
                "candidate_count": len(result.candidates),
                "error_message": result.error_message,
            }
            for result in results
        ]
    }


def process_release_link_scan_run(db: Session, run_id: int) -> bool:
    run = (
        db.query(ReleaseLinkScanRun)
        .options(
            joinedload(ReleaseLinkScanRun.release).joinedload(Release.artists),
            joinedload(ReleaseLinkScanRun.release).joinedload(Release.artist),
        )
        .filter(ReleaseLinkScanRun.id == run_id)
        .first()
    )
    if not run or run.status not in {"queued", "running"}:
        return False
    release = run.release
    if not release:
        run.status = "failed"
        run.error_message = "Release not found."
        run.completed_at = datetime.now(timezone.utc)
        db.commit()
        return False
    run.status = "running"
    run.started_at = datetime.now(timezone.utc)
    run.error_message = None
    db.commit()
    try:
        results = discover_release_links(
            release.title,
            _release_artist_names(release),
            platforms=_platforms_from_run(run),
        )
        for result in results:
            for candidate in result.candidates:
                _upsert_release_link_candidate(db, release=release, candidate=candidate)
        run.summary_json = json.dumps(_scan_summary(results))
        run.status = "completed"
        run.completed_at = datetime.now(timezone.utc)
        db.commit()
        return True
    except Exception as exc:
        run.status = "failed"
        run.error_message = str(exc)
        run.completed_at = datetime.now(timezone.utc)
        db.commit()
        return False


def get_release_link_runs_ready_to_scan(db: Session, limit: int = 10) -> list[ReleaseLinkScanRun]:
    return (
        db.query(ReleaseLinkScanRun)
        .filter(ReleaseLinkScanRun.status == "queued")
        .order_by(ReleaseLinkScanRun.created_at.asc(), ReleaseLinkScanRun.id.asc())
        .limit(limit)
        .all()
    )


def ensure_periodic_release_link_scan_runs(db: Session, limit: int = 10) -> int:
    now = datetime.now(timezone.utc)
    candidates = (
        db.query(Release)
        .options(joinedload(Release.link_candidates), joinedload(Release.link_scan_runs))
        .order_by(Release.created_at.desc(), Release.id.desc())
        .limit(max(limit * 4, limit))
        .all()
    )
    created = 0
    for release in candidates:
        open_run = any(run.status in {"queued", "running"} for run in (release.link_scan_runs or []))
        if open_run:
            continue
        if _has_pending_review_candidates(release):
            continue
        platform_links = parse_platform_links(release.platform_links_json)
        if platform_links:
            continue
        last_scan_at = None
        for run in release.link_scan_runs or []:
            stamp = run.completed_at or run.created_at
            if stamp is not None and (last_scan_at is None or stamp > last_scan_at):
                last_scan_at = stamp
        if last_scan_at and (now - last_scan_at) < SCAN_RETRY_INTERVAL:
            continue
        queue_release_link_scan(db, release_id=release.id, trigger_type="scheduled")
        created += 1
        if created >= limit:
            break
    if created:
        db.commit()
    return created


def approve_release_link_candidate(db: Session, candidate: ReleaseLinkCandidate) -> Release:
    release = candidate.release
    links = parse_platform_links(release.platform_links_json)
    links[candidate.platform] = candidate.url
    release.platform_links_json = json.dumps(links)
    for sibling in release.link_candidates or []:
        if sibling.id == candidate.id:
            continue
        if sibling.platform != candidate.platform:
            continue
        if sibling.status == "approved":
            sibling.status = "rejected"
            sibling.reviewed_at = datetime.now(timezone.utc)
    candidate.status = "approved"
    candidate.reviewed_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(release)
    return release


def reject_release_link_candidate(db: Session, candidate: ReleaseLinkCandidate) -> ReleaseLinkCandidate:
    candidate.status = "rejected"
    candidate.reviewed_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(candidate)
    return candidate


def serialize_scan_summary(run: ReleaseLinkScanRun) -> dict:
    try:
        data = json.loads(run.summary_json or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        data = {}
    return data if isinstance(data, dict) else {}


def candidate_to_payload(candidate: DiscoveryCandidate) -> dict:
    return asdict(candidate)
