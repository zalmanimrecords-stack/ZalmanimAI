"""Linktree and public artist page helpers."""

import json
from typing import Any

from fastapi import Request

from app.models.models import Artist
from app.schemas.schemas import LinktreeLink

# Label for each extra link key (for public linktree page)
_LINKTREE_LABELS = {
    "website": "Website",
    "soundcloud": "SoundCloud",
    "facebook": "Facebook",
    "instagram": "Instagram",
    "twitter_1": "Twitter / X",
    "twitter_2": "Twitter / X 2",
    "youtube": "YouTube",
    "tiktok": "TikTok",
    "spotify": "Spotify",
    "apple_music": "Apple Music",
    "linktree": "Linktree",
    "other_1": "Other",
    "other_2": "Other",
    "other_3": "Other",
}


def _linktree_image_url(request: Request, artist_id: int, kind: str) -> str:
    """Build public URL for artist profile image or logo (no auth)."""
    base = str(request.base_url).rstrip("/")
    return f"{base}/api/public/artist/{artist_id}/{kind}"


def _artist_public_media_url(request: Request, artist_id: int, media_id: int) -> str:
    base = str(request.base_url).rstrip("/")
    return f"{base}/api/public/artist/{artist_id}/media/{media_id}"


def _artist_minisite_theme(value: str | None) -> str:
    theme = (value or "").strip().lower()
    if theme in {"ocean", "sunset", "mono"}:
        return theme
    return "ocean"


def _artist_public_media_ids(extra: dict) -> set[int]:
    ids: set[int] = set()
    for key in ("profile_image_media_id", "logo_media_id"):
        value = extra.get(key)
        if isinstance(value, int) and value > 0:
            ids.add(value)
    gallery = extra.get("minisite_gallery_media_ids")
    if isinstance(gallery, list):
        ids.update(item for item in gallery if isinstance(item, int) and item > 0)
    return ids


def _artist_extra_json_dict(artist: Artist) -> dict[str, Any]:
    raw = getattr(artist, "extra_json", None)
    if not raw:
        return {}
    try:
        data = json.loads(raw) or {}
    except (json.JSONDecodeError, TypeError):
        return {}
    return data if isinstance(data, dict) else {}


def _normalize_external_url(value: str) -> str:
    trimmed = (value or "").strip()
    if not trimmed:
        return ""
    if trimmed.startswith("http://") or trimmed.startswith("https://"):
        return trimmed
    if "://" in trimmed:
        return trimmed
    return f"https://{trimmed}"


def _linktree_name_headline_bio_theme(artist: Artist, extra: dict[str, Any]) -> tuple[str, str | None, str | None, str]:
    name = (artist.name or "").strip() or (extra.get("full_name") or extra.get("artist_brand") or "").strip() or "Artist"
    headline = (extra.get("minisite_headline") or extra.get("artist_brand") or "").strip() or None
    bio = (extra.get("minisite_bio") or artist.notes or "").strip() or None
    theme = _artist_minisite_theme(extra.get("minisite_theme"))
    return name, headline, bio, theme


def _linktree_links_from_extra(extra: dict[str, Any]) -> list[LinktreeLink]:
    links: list[LinktreeLink] = []
    for key, label in _LINKTREE_LABELS.items():
        normalized_url = _normalize_external_url(str(extra.get(key) or ""))
        if normalized_url:
            links.append(LinktreeLink(label=label, url=normalized_url))
    return links


