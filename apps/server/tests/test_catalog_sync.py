import json

from app.models.models import Artist, CatalogTrack, Release


def test_sync_from_catalog_creates_release_for_matched_artist_and_queues_scan(
    client, db_session, admin_headers, monkeypatch
):
    artist = Artist(
        name="Aurora Echo",
        email="aurora-sync@example.com",
        is_active=True,
        extra_json=json.dumps({"artist_brand": "Aurora Echo"}),
    )
    db_session.add(artist)
    db_session.flush()

    db_session.add(
        CatalogTrack(
            catalog_number="CAT-001",
            release_title="Skyline EP",
            original_artists="Aurora Echo",
            track_title="Skyline",
            mix_title="Original Mix",
        )
    )
    db_session.commit()

    queued_release_ids: list[int] = []

    def _fake_queue_release_link_scan(db, release_id, trigger_type, requested_by_user_id=None, platforms=None):
        queued_release_ids.append(release_id)
        return None

    monkeypatch.setattr("app.api.routes.queue_release_link_scan", _fake_queue_release_link_scan)

    response = client.post("/api/admin/releases/sync-from-catalog", headers=admin_headers)
    assert response.status_code == 200
    payload = response.json()
    assert payload["created"] == 1
    assert payload["skipped_duplicate"] == 0
    assert payload["unmatched"] == 0

    created_release = db_session.query(Release).filter(Release.title == "Skyline EP").first()
    assert created_release is not None
    assert created_release.artist_id == artist.id
    assert any(a.id == artist.id for a in created_release.artists)
    assert queued_release_ids == [created_release.id]


def test_sync_from_catalog_unmatched_creates_placeholder_and_second_run_skips_duplicate(
    client, db_session, admin_headers, monkeypatch
):
    db_session.add(
        CatalogTrack(
            catalog_number="CAT-404",
            release_title="Unknown Origins",
            original_artists="No Such Artist",
            track_title="Unknown Origins",
            mix_title="Original Mix",
        )
    )
    db_session.commit()

    monkeypatch.setattr("app.api.routes.queue_release_link_scan", lambda *args, **kwargs: None)

    first = client.post("/api/admin/releases/sync-from-catalog", headers=admin_headers)
    assert first.status_code == 200
    first_payload = first.json()
    assert first_payload["created"] == 1
    assert first_payload["unmatched"] == 1
    assert first_payload["skipped_duplicate"] == 0

    placeholder = db_session.query(Release).filter(Release.title == "Unknown Origins").first()
    assert placeholder is not None
    assert placeholder.artist_id is None
    assert placeholder.artists == []

    second = client.post("/api/admin/releases/sync-from-catalog", headers=admin_headers)
    assert second.status_code == 200
    second_payload = second.json()
    assert second_payload["created"] == 0
    assert second_payload["unmatched"] == 1
    assert second_payload["skipped_duplicate"] == 1

