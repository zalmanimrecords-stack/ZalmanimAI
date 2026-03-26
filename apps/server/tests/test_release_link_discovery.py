import json

from app.models.models import Artist, Release, ReleaseLinkCandidate, ReleaseLinkScanRun
from app.services.release_link_discovery import (
    DiscoveryCandidate,
    PlatformDiscoveryResult,
    BandcampSearchAdapter,
    YouTubeSearchAdapter,
    ensure_periodic_release_link_scan_runs,
    process_release_link_scan_run,
)


def test_queue_release_link_scan_creates_run(client, db_session, admin_headers):
    artist = Artist(name="Maya Waves", email="maya@example.com", notes="")
    release = Release(title="Ocean Echo", status="from_catalog", artist=artist)
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.commit()

    response = client.post(
        "/api/admin/releases/link-scan",
        headers=admin_headers,
        json={"release_ids": [release.id]},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["release_ids"] == [release.id]
    assert db_session.query(ReleaseLinkScanRun).filter(ReleaseLinkScanRun.release_id == release.id).count() == 1


def test_approve_release_link_candidate_updates_release_and_linktree(client, db_session, admin_headers):
    artist = Artist(
        name="Maya Waves",
        email="maya2@example.com",
        notes="",
        extra_json=json.dumps({"spotify": "https://open.spotify.com/artist/maya"}),
    )
    release = Release(title="Ocean Echo", status="from_catalog", artist=artist)
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.flush()
    candidate = ReleaseLinkCandidate(
        release_id=release.id,
        platform="spotify",
        url="https://open.spotify.com/album/ocean-echo",
        match_title="Ocean Echo",
        match_artist="Maya Waves",
        confidence=0.92,
        status="pending_review",
        source_type="web_search",
        raw_payload_json="{}",
    )
    db_session.add(candidate)
    db_session.commit()

    approve_response = client.post(
        f"/api/admin/releases/{release.id}/link-candidates/{candidate.id}/approve",
        headers=admin_headers,
    )

    assert approve_response.status_code == 200
    approved_payload = approve_response.json()
    assert approved_payload["release"]["platform_links"]["spotify"] == "https://open.spotify.com/album/ocean-echo"
    assert approved_payload["candidate"]["status"] == "approved"

    linktree_response = client.get(f"/api/public/linktree/{artist.id}")
    assert linktree_response.status_code == 200
    releases = linktree_response.json()["releases"]
    assert releases[0]["url"] == "https://open.spotify.com/album/ocean-echo"


def test_approve_release_link_candidate_replaces_previous_approved_for_platform(client, db_session, admin_headers):
    artist = Artist(name="Maya Waves", email="maya-approve@example.com", notes="")
    release = Release(
        title="Ocean Echo",
        status="from_catalog",
        artist=artist,
        platform_links_json=json.dumps({"spotify": "https://open.spotify.com/album/old-link"}),
    )
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.flush()

    old_candidate = ReleaseLinkCandidate(
        release_id=release.id,
        platform="spotify",
        url="https://open.spotify.com/album/old-link",
        match_title="Ocean Echo",
        match_artist="Maya Waves",
        confidence=0.78,
        status="approved",
        source_type="manual",
        raw_payload_json="{}",
    )
    new_candidate = ReleaseLinkCandidate(
        release_id=release.id,
        platform="spotify",
        url="https://open.spotify.com/album/new-link",
        match_title="Ocean Echo",
        match_artist="Maya Waves",
        confidence=0.96,
        status="pending_review",
        source_type="web_search",
        raw_payload_json="{}",
    )
    db_session.add_all([old_candidate, new_candidate])
    db_session.commit()

    response = client.post(
        f"/api/admin/releases/{release.id}/link-candidates/{new_candidate.id}/approve",
        headers=admin_headers,
    )

    assert response.status_code == 200
    db_session.refresh(old_candidate)
    db_session.refresh(new_candidate)
    db_session.refresh(release)
    assert old_candidate.status == "rejected"
    assert new_candidate.status == "approved"
    assert json.loads(release.platform_links_json)["spotify"] == "https://open.spotify.com/album/new-link"


def test_reject_release_link_candidate_removes_matching_approved_link(client, db_session, admin_headers):
    artist = Artist(name="Maya Waves", email="maya-reject@example.com", notes="")
    release = Release(
        title="Ocean Echo",
        status="from_catalog",
        artist=artist,
        platform_links_json=json.dumps({"spotify": "https://open.spotify.com/album/ocean-echo"}),
    )
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.flush()
    candidate = ReleaseLinkCandidate(
        release_id=release.id,
        platform="spotify",
        url="https://open.spotify.com/album/ocean-echo",
        match_title="Ocean Echo",
        match_artist="Maya Waves",
        confidence=0.91,
        status="approved",
        source_type="web_search",
        raw_payload_json="{}",
    )
    db_session.add(candidate)
    db_session.commit()

    response = client.post(
        f"/api/admin/releases/{release.id}/link-candidates/{candidate.id}/reject",
        headers=admin_headers,
    )

    assert response.status_code == 200
    db_session.refresh(release)
    assert json.loads(release.platform_links_json) == {}


def test_update_release_minisite_returns_preview_and_public_urls(client, db_session, admin_headers):
    artist = Artist(name="Maya Waves", email="maya-minisite@example.com", notes="")
    release = Release(title="Ocean Echo", status="from_catalog", artist=artist)
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.commit()

    response = client.patch(
        f"/api/admin/releases/{release.id}/minisite",
        headers=admin_headers,
        json={
            "theme": "paperwave",
            "description": "A textured release page",
            "download_url": "https://downloads.example.com/ocean-echo.zip",
            "gallery_urls": ["https://img.example.com/ocean-echo.jpg"],
            "is_public": True,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["minisite_theme"] == "paperwave"
    assert payload["minisite_is_public"] is True
    assert payload["minisite_preview_url"]
    assert payload["minisite_public_url"]

    preview_response = client.get(payload["minisite_preview_url"])
    public_response = client.get(payload["minisite_public_url"])
    assert preview_response.status_code == 200
    assert public_response.status_code == 200
    assert "Ocean Echo" in public_response.text
    assert "Download Release" in public_response.text


def test_release_minisite_shows_best_scanned_links_when_no_approved_links(client, db_session):
    artist = Artist(name="Maya Waves", email="maya-minisite-links@example.com", notes="")
    release = Release(
        title="Ocean Echo",
        status="from_catalog",
        artist=artist,
        minisite_slug="ocean-echo-links",
        minisite_is_public=True,
        minisite_json=json.dumps({"preview_token": "preview-123", "theme": "nebula"}),
    )
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.flush()
    db_session.add_all(
        [
            ReleaseLinkCandidate(
                release_id=release.id,
                platform="youtube",
                url="https://www.youtube.com/watch?v=ocean-echo",
                match_title="Ocean Echo",
                match_artist="Maya Waves",
                confidence=0.95,
                status="pending_review",
                source_type="web_search",
                raw_payload_json="{}",
            ),
            ReleaseLinkCandidate(
                release_id=release.id,
                platform="spotify",
                url="https://open.spotify.com/album/ocean-echo",
                match_title="Ocean Echo",
                match_artist="Maya Waves",
                confidence=0.78,
                status="pending_review",
                source_type="web_search",
                raw_payload_json="{}",
            ),
            ReleaseLinkCandidate(
                release_id=release.id,
                platform="spotify",
                url="https://open.spotify.com/album/ocean-echo-low",
                match_title="Ocean Echo",
                match_artist="Maya Waves",
                confidence=0.52,
                status="pending_review",
                source_type="web_search",
                raw_payload_json="{}",
            ),
            ReleaseLinkCandidate(
                release_id=release.id,
                platform="deezer",
                url="https://www.deezer.com/album/ocean-echo",
                match_title="Ocean Echo",
                match_artist="Maya Waves",
                confidence=0.97,
                status="rejected",
                source_type="web_search",
                raw_payload_json="{}",
            ),
        ]
    )
    db_session.commit()

    response = client.get("/api/public/release-sites/ocean-echo-links")

    assert response.status_code == 200
    assert "https://www.youtube.com/watch?v=ocean-echo" in response.text
    assert "https://open.spotify.com/album/ocean-echo" in response.text
    assert "https://open.spotify.com/album/ocean-echo-low" not in response.text
    assert "https://www.deezer.com/album/ocean-echo" not in response.text


def test_release_minisite_prefers_approved_links_over_pending_candidates(client, db_session):
    artist = Artist(name="Maya Waves", email="maya-minisite-approved@example.com", notes="")
    release = Release(
        title="Ocean Echo",
        status="from_catalog",
        artist=artist,
        platform_links_json=json.dumps({"spotify": "https://open.spotify.com/album/ocean-echo-approved"}),
        minisite_slug="ocean-echo-approved",
        minisite_is_public=True,
        minisite_json=json.dumps({"preview_token": "preview-123", "theme": "nebula"}),
    )
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.flush()
    db_session.add(
        ReleaseLinkCandidate(
            release_id=release.id,
            platform="spotify",
            url="https://open.spotify.com/album/ocean-echo-pending",
            match_title="Ocean Echo",
            match_artist="Maya Waves",
            confidence=0.99,
            status="pending_review",
            source_type="web_search",
            raw_payload_json="{}",
        )
    )
    db_session.commit()

    response = client.get("/api/public/release-sites/ocean-echo-approved")

    assert response.status_code == 200
    assert "https://open.spotify.com/album/ocean-echo-approved" in response.text
    assert "https://open.spotify.com/album/ocean-echo-pending" not in response.text


def test_send_release_minisite_to_artist_uses_public_url_when_available(client, db_session, admin_headers, monkeypatch):
    artist = Artist(name="Maya Waves", email="maya-send@example.com", notes="")
    release = Release(
        title="Ocean Echo",
        status="from_catalog",
        artist=artist,
        minisite_slug="ocean-echo-1",
        minisite_is_public=True,
        minisite_json=json.dumps({"preview_token": "preview-123", "theme": "nebula"}),
    )
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.commit()

    sent_messages: list[tuple[str, str, str]] = []

    def fake_send_email_service(*, to_email, subject, body_text, body_html=None):
        sent_messages.append((to_email, subject, body_text))
        return True, None

    monkeypatch.setattr("app.api.routes.send_email_service", fake_send_email_service)

    response = client.post(
        f"/api/admin/releases/{release.id}/minisite/send",
        headers=admin_headers,
        json={"message": "Share this with your audience."},
    )

    assert response.status_code == 200
    assert len(sent_messages) == 1
    assert sent_messages[0][0] == "maya-send@example.com"
    assert "/public/release-sites/ocean-echo-1" in sent_messages[0][2]
    assert "preview_token" not in sent_messages[0][2]


def test_process_release_link_scan_run_dedupes_existing_rejected_candidate(db_session, monkeypatch):
    artist = Artist(name="Maya Waves", email="maya3@example.com", notes="")
    release = Release(title="Ocean Echo", status="from_catalog", artist=artist)
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.flush()

    rejected = ReleaseLinkCandidate(
        release_id=release.id,
        platform="spotify",
        url="https://open.spotify.com/album/ocean-echo",
        match_title="Ocean Echo",
        match_artist="Maya Waves",
        confidence=0.51,
        status="rejected",
        source_type="web_search",
        raw_payload_json="{}",
    )
    run = ReleaseLinkScanRun(release_id=release.id, status="queued", trigger_type="manual")
    db_session.add_all([rejected, run])
    db_session.commit()

    def fake_discover(release_title, artist_names, *, platforms=None):
        return [
            PlatformDiscoveryResult(
                platform="spotify",
                status="ok",
                candidates=[
                    DiscoveryCandidate(
                        platform="spotify",
                        url="https://open.spotify.com/album/ocean-echo",
                        match_title=release_title,
                        match_artist=artist_names[0],
                        confidence=0.95,
                        source_type="web_search",
                        raw_payload={"stub": True},
                    )
                ],
            )
        ]

    monkeypatch.setattr(
        "app.services.release_link_discovery.discover_release_links",
        fake_discover,
    )

    processed = process_release_link_scan_run(db_session, run.id)
    assert processed is True

    rows = (
        db_session.query(ReleaseLinkCandidate)
        .filter(ReleaseLinkCandidate.release_id == release.id)
        .all()
    )
    assert len(rows) == 1
    assert rows[0].status == "rejected"
    assert rows[0].confidence >= 0.95


def test_ensure_periodic_release_link_scan_runs_queues_missing_release(db_session):
    artist = Artist(name="Maya Waves", email="maya4@example.com", notes="")
    release = Release(title="Ocean Echo", status="from_catalog", artist=artist)
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.commit()

    created = ensure_periodic_release_link_scan_runs(db_session, limit=5)

    assert created == 1
    assert db_session.query(ReleaseLinkScanRun).filter(ReleaseLinkScanRun.release_id == release.id).count() == 1


def test_ensure_periodic_release_link_scan_runs_skips_release_with_approved_links(db_session):
    artist = Artist(name="Maya Waves", email="maya5@example.com", notes="")
    release = Release(
        title="Ocean Echo",
        status="from_catalog",
        artist=artist,
        platform_links_json=json.dumps({"spotify": "https://open.spotify.com/album/ocean-echo"}),
    )
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.commit()

    created = ensure_periodic_release_link_scan_runs(db_session, limit=5)

    assert created == 0
    assert db_session.query(ReleaseLinkScanRun).filter(ReleaseLinkScanRun.release_id == release.id).count() == 0


def test_ensure_periodic_release_link_scan_runs_skips_release_with_pending_review(db_session):
    artist = Artist(name="Maya Waves", email="maya6@example.com", notes="")
    release = Release(title="Ocean Echo", status="from_catalog", artist=artist)
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.flush()
    db_session.add(
        ReleaseLinkCandidate(
            release_id=release.id,
            platform="spotify",
            url="https://open.spotify.com/album/ocean-echo",
            match_title="Ocean Echo",
            match_artist="Maya Waves",
            confidence=0.9,
            status="pending_review",
            source_type="web_search",
            raw_payload_json="{}",
        )
    )
    db_session.commit()

    created = ensure_periodic_release_link_scan_runs(db_session, limit=5)

    assert created == 0
    assert db_session.query(ReleaseLinkScanRun).filter(ReleaseLinkScanRun.release_id == release.id).count() == 0


def test_youtube_search_adapter_parses_candidates(monkeypatch):
    class FakeResponse:
        text = (
            '"videoId":"abc123xyz00","title":{"runs":[{"text":"Maya Waves - Ocean Echo (Official Audio)"}]}'
            '"videoId":"def456uvw11","title":{"runs":[{"text":"Someone Else - Different Song"}]}'
        )

        def raise_for_status(self):
            return None

    monkeypatch.setattr(
        "app.services.release_link_discovery.httpx.get",
        lambda *args, **kwargs: FakeResponse(),
    )

    result = YouTubeSearchAdapter().discover("Ocean Echo", ["Maya Waves"])

    assert result.status == "ok"
    assert result.candidates
    assert result.candidates[0].url == "https://www.youtube.com/watch?v=abc123xyz00"
    assert result.candidates[0].match_title == "Ocean Echo"
    assert result.candidates[0].match_artist == "Maya Waves"
    assert result.candidates[0].raw_payload["artwork_url"] == "https://i.ytimg.com/vi/abc123xyz00/hqdefault.jpg"


def test_bandcamp_search_adapter_parses_candidates(monkeypatch):
    class FakeResponse:
        text = """
        <li class="searchresult band">
          <div class="heading"><a href="https://artist.bandcamp.com/album/ocean-echo">Ocean Echo</a></div>
          <div class="subhead">by Maya Waves</div>
        </li>
        """

        def raise_for_status(self):
            return None

    monkeypatch.setattr(
        "app.services.release_link_discovery.httpx.get",
        lambda *args, **kwargs: FakeResponse(),
    )

    result = BandcampSearchAdapter().discover("Ocean Echo", ["Maya Waves"])

    assert result.status == "ok"
    assert result.candidates
    assert result.candidates[0].url == "https://artist.bandcamp.com/album/ocean-echo"
    assert result.candidates[0].match_title == "Ocean Echo"
    assert result.candidates[0].match_artist == "Maya Waves"


def test_process_release_link_scan_run_updates_release_cover_from_candidate_artwork(db_session, monkeypatch):
    artist = Artist(name="Maya Waves", email="maya-cover@example.com", notes="")
    release = Release(title="Ocean Echo", status="from_catalog", artist=artist)
    release.artists.append(artist)
    db_session.add_all([artist, release])
    db_session.flush()
    run = ReleaseLinkScanRun(release_id=release.id, status="queued", trigger_type="manual")
    db_session.add(run)
    db_session.commit()

    def fake_discover(release_title, artist_names, *, platforms=None):
        return [
            PlatformDiscoveryResult(
                platform="youtube",
                status="ok",
                candidates=[
                    DiscoveryCandidate(
                        platform="youtube",
                        url="https://www.youtube.com/watch?v=abc123xyz00",
                        match_title=release_title,
                        match_artist=artist_names[0],
                        confidence=0.98,
                        source_type="web_search",
                        raw_payload={"artwork_url": "https://img.example.com/ocean-echo.jpg"},
                    )
                ],
            )
        ]

    def fake_download(release_row, artwork_url):
        release_row.cover_image_path = f"/tmp/release_{release_row.id}.jpg"
        release_row.cover_image_source_url = artwork_url
        return True

    monkeypatch.setattr("app.services.release_link_discovery.discover_release_links", fake_discover)
    monkeypatch.setattr("app.services.release_link_discovery._download_release_cover_image", fake_download)

    processed = process_release_link_scan_run(db_session, run.id)

    assert processed is True
    db_session.refresh(release)
    assert release.cover_image_path == f"/tmp/release_{release.id}.jpg"
    assert release.cover_image_source_url == "https://img.example.com/ocean-echo.jpg"
