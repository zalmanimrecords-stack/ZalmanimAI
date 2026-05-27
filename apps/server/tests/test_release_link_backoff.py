"""Tests for per-platform release link scan backoff."""

import json
from datetime import datetime, timedelta, timezone

from app.models.models import Artist, Release
from app.services.release_link_backoff import (
    filter_platforms_not_in_backoff,
    platform_in_backoff,
    record_platform_scan_results,
)
from app.services.release_link_discovery import (
    SUPPORTED_RELEASE_LINK_PLATFORMS,
    PlatformDiscoveryResult,
    process_release_link_scan_run,
    queue_release_link_scan,
)


def test_record_platform_scan_results_sets_and_clears_backoff(db_session):
    artist = Artist(name="Backoff Artist", email="backoff@example.com", notes="")
    release = Release(title="Backoff Album", status="from_catalog", artist=artist)
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.commit()

    record_platform_scan_results(
        release,
        [
            PlatformDiscoveryResult(
                platform="spotify",
                status="failed",
                candidates=[],
                error_message="rate limited",
            ),
        ],
    )
    db_session.commit()
    db_session.refresh(release)

    assert platform_in_backoff(release, "spotify")
    assert "spotify" not in filter_platforms_not_in_backoff(release, None)

    record_platform_scan_results(
        release,
        [
            PlatformDiscoveryResult(
                platform="spotify",
                status="ok",
                candidates=[],
            ),
        ],
    )
    db_session.commit()
    db_session.refresh(release)

    assert not platform_in_backoff(release, "spotify")
    assert "spotify" in filter_platforms_not_in_backoff(release, None)


def test_process_scan_skips_platforms_in_backoff(db_session, monkeypatch):
    artist = Artist(name="Skip Artist", email="skip@example.com", notes="")
    release = Release(
        title="Skip Album",
        status="from_catalog",
        artist=artist,
        link_scan_backoff_json=json.dumps(
            {
                "spotify": {
                    "fail_count": 1,
                    "retry_after": (datetime.now(timezone.utc) + timedelta(days=1)).isoformat(),
                }
            }
        ),
    )
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.commit()

    called_with: list[list[str] | None] = []

    def fake_discover(title, artist_names, *, platforms=None):
        called_with.append(platforms)
        return []

    monkeypatch.setattr(
        "app.services.release_link_discovery.discover_release_links",
        fake_discover,
    )

    run = queue_release_link_scan(db_session, release_id=release.id, trigger_type="manual")
    db_session.commit()
    assert process_release_link_scan_run(db_session, run.id) is True
    expected = [p for p in SUPPORTED_RELEASE_LINK_PLATFORMS if p != "spotify"]
    assert called_with == [expected]
