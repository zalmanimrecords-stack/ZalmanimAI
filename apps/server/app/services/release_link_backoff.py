"""Per-platform backoff after failed release link discovery scans."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

from typing import TYPE_CHECKING

from app.models.models import Release

if TYPE_CHECKING:
    from app.services.release_link_discovery import PlatformDiscoveryResult

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

# Escalating backoff after consecutive platform failures within scan runs.
PLATFORM_FAILURE_BACKOFF_STEPS = (
    timedelta(hours=6),
    timedelta(hours=24),
    timedelta(days=3),
)


def _parse_backoff_map(release: Release) -> dict[str, dict]:
    raw = getattr(release, "link_scan_backoff_json", None) or "{}"
    try:
        data = json.loads(raw) or {}
    except (json.JSONDecodeError, TypeError):
        return {}
    return data if isinstance(data, dict) else {}


def _save_backoff_map(release: Release, data: dict[str, dict]) -> None:
    release.link_scan_backoff_json = json.dumps(data)


def platform_in_backoff(release: Release, platform: str, *, now: datetime | None = None) -> bool:
    now = now or datetime.now(timezone.utc)
    entry = _parse_backoff_map(release).get(platform)
    if not entry:
        return False
    retry_after = entry.get("retry_after")
    if not isinstance(retry_after, str) or not retry_after.strip():
        return False
    try:
        retry_dt = datetime.fromisoformat(retry_after.replace("Z", "+00:00"))
    except ValueError:
        return False
    return retry_dt > now


def filter_platforms_not_in_backoff(
    release: Release,
    platforms: list[str] | None,
    *,
    now: datetime | None = None,
) -> list[str]:
    """Return platforms eligible for scanning (may be empty when all are in backoff)."""
    base = list(platforms or SUPPORTED_RELEASE_LINK_PLATFORMS)
    return [p for p in base if not platform_in_backoff(release, p, now=now)]


def record_platform_scan_results(release: Release, results: list["PlatformDiscoveryResult"]) -> None:
    """Update per-platform backoff state from a completed scan."""
    backoff = _parse_backoff_map(release)
    now = datetime.now(timezone.utc)
    for result in results:
        platform = result.platform
        if result.status == "failed":
            entry = backoff.get(platform, {})
            fail_count = int(entry.get("fail_count", 0) or 0) + 1
            step_index = min(fail_count - 1, len(PLATFORM_FAILURE_BACKOFF_STEPS) - 1)
            retry_after = now + PLATFORM_FAILURE_BACKOFF_STEPS[step_index]
            backoff[platform] = {
                "fail_count": fail_count,
                "retry_after": retry_after.isoformat(),
                "last_error": (result.error_message or "")[:300],
            }
        else:
            backoff.pop(platform, None)
    _save_backoff_map(release, backoff)
