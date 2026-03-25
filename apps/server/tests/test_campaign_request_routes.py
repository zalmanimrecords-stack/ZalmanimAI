from app.models.models import Artist, CampaignRequest, PendingReleaseToken, Release
from app.services.auth import create_access_token


def test_artist_can_create_and_list_campaign_requests(client, db_session):
    artist = Artist(name="Maya Waves", email="maya@example.com", is_active=True)
    db_session.add(artist)
    db_session.commit()
    db_session.refresh(artist)

    release = Release(artist_id=artist.id, title="Ocean Lights", status="submitted", file_path=None)
    db_session.add(release)
    db_session.commit()
    db_session.refresh(release)

    artist_headers = {"Authorization": f"Bearer {create_access_token(f'artist:{artist.id}')}"}
    create_response = client.post(
        "/api/artist/me/campaign-requests",
        headers=artist_headers,
        json={"release_id": release.id, "message": "Please promote this one"},
    )

    assert create_response.status_code == 200
    payload = create_response.json()
    assert payload["artist_id"] == artist.id
    assert payload["release_id"] == release.id
    assert payload["status"] == "pending"

    list_response = client.get("/api/artist/me/campaign-requests", headers=artist_headers)

    assert list_response.status_code == 200
    items = list_response.json()
    assert len(items) == 1
    assert items[0]["id"] == payload["id"]
    assert items[0]["release_title"] == "Ocean Lights"


def test_admin_can_approve_campaign_request_and_create_pending_release_token(client, db_session, admin_headers):
    artist = Artist(name="Maya Waves", email="maya@example.com", is_active=True)
    db_session.add(artist)
    db_session.commit()
    db_session.refresh(artist)

    request_row = CampaignRequest(
        artist_id=artist.id,
        release_id=None,
        message="Need label help",
        status="pending",
    )
    db_session.add(request_row)
    db_session.commit()
    db_session.refresh(request_row)

    response = client.patch(
        f"/api/admin/campaign-requests/{request_row.id}",
        headers=admin_headers,
        json={"status": "approved", "admin_notes": "Looks good"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "approved"
    assert payload["admin_notes"] == "Looks good"

    db_session.expire_all()
    tokens = db_session.query(PendingReleaseToken).filter(
        PendingReleaseToken.campaign_request_id == request_row.id
    ).all()
    assert len(tokens) == 1
    assert tokens[0].artist_id == artist.id
