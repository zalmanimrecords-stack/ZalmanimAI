import hashlib
from datetime import datetime, timedelta, timezone

from app.api import routes
from app.models.models import (
    Artist,
    ArtistActivityLog,
    LabelInboxMessage,
    LabelInboxThread,
    PendingRelease,
    PendingReleaseToken,
)


def test_send_pending_release_reminder_creates_token_and_logs_activity(
    client,
    db_session,
    admin_headers,
    monkeypatch,
):
    sent_payload = {}

    def fake_send_email_service(*, to_email, subject, body_text, body_html=None):
        sent_payload["to_email"] = to_email
        sent_payload["subject"] = subject
        sent_payload["body_text"] = body_text
        sent_payload["body_html"] = body_html
        return True, "Sent"

    monkeypatch.setattr(routes, "send_email_service", fake_send_email_service)

    artist = Artist(name="Maya Waves", email="maya@example.com", is_active=True)
    db_session.add(artist)
    db_session.commit()
    db_session.refresh(artist)

    pending_release = PendingRelease(
        artist_id=artist.id,
        artist_name=artist.name,
        artist_email=artist.email,
        artist_data_json="{}",
        release_title="Ocean Lights",
        release_data_json="{}",
        status="pending",
    )
    db_session.add(pending_release)
    db_session.commit()
    db_session.refresh(pending_release)

    response = client.post(
        f"/api/admin/pending-releases/{pending_release.id}/send-reminder",
        headers=admin_headers,
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["success"] is True
    assert payload["message"] == "Completion email sent"
    assert sent_payload["to_email"] == "maya@example.com"
    assert "Ocean Lights" in sent_payload["subject"]
    assert "Ocean Lights" in sent_payload["body_text"]

    tokens = db_session.query(PendingReleaseToken).filter(
        PendingReleaseToken.pending_release_id == pending_release.id
    ).all()
    assert len(tokens) == 1

    logs = db_session.query(ArtistActivityLog).filter(
        ArtistActivityLog.artist_id == artist.id,
        ArtistActivityLog.activity_type == "pending_release_reminder_email",
    ).all()
    assert len(logs) == 1


def test_pending_release_submit_creates_unread_admin_inbox_message(
    client,
    db_session,
    admin_headers,
):
    artist = Artist(name="Maya Waves", email="maya@example.com", is_active=True)
    db_session.add(artist)
    db_session.commit()
    db_session.refresh(artist)

    pending_release = PendingRelease(
        artist_id=artist.id,
        artist_name=artist.name,
        artist_email=artist.email,
        artist_data_json="{}",
        release_title="Ocean Lights",
        release_data_json="{}",
        status="pending",
    )
    db_session.add(pending_release)
    db_session.commit()
    db_session.refresh(pending_release)

    raw_token = "pending-release-token"
    db_session.add(
        PendingReleaseToken(
            token_hash=hashlib.sha256(raw_token.encode()).hexdigest(),
            pending_release_id=pending_release.id,
            artist_id=artist.id,
            expires_at=datetime.now(timezone.utc) + timedelta(days=7),
        )
    )
    db_session.commit()

    response = client.post(
        "/api/public/pending-release-submit",
        json={
            "token": raw_token,
            "artist_name": "Maya Waves",
            "artist_email": "maya@example.com",
            "artist_data": {"instagram": "https://instagram.com/mayawaves"},
            "release_title": "Ocean Lights",
            "release_data": {"track_title": "Ocean Lights"},
        },
    )

    assert response.status_code == 200

    db_session.expire_all()
    thread = (
        db_session.query(LabelInboxThread)
        .filter(LabelInboxThread.artist_id == artist.id)
        .first()
    )
    assert thread is not None

    messages = (
        db_session.query(LabelInboxMessage)
        .filter(LabelInboxMessage.thread_id == thread.id)
        .all()
    )
    assert len(messages) == 1
    assert messages[0].sender == "artist"
    assert messages[0].admin_read_at is None
    assert "Pending Release form submitted by the artist." in messages[0].body
    assert "Ocean Lights" in messages[0].body

    inbox_response = client.get("/api/admin/inbox", headers=admin_headers)

    assert inbox_response.status_code == 200
    inbox_payload = inbox_response.json()
    assert len(inbox_payload) == 1
    assert inbox_payload[0]["unread_count"] == 1


def test_archive_pending_release_hides_it_from_default_list(
    client,
    db_session,
    admin_headers,
):
    pending_release = PendingRelease(
        artist_name="Archive Artist",
        artist_email="archive@example.com",
        artist_data_json="{}",
        release_title="Archive Target",
        release_data_json="{}",
        status="pending",
    )
    db_session.add(pending_release)
    db_session.commit()
    db_session.refresh(pending_release)

    response = client.post(
        f"/api/admin/pending-releases/{pending_release.id}/archive",
        headers=admin_headers,
    )

    assert response.status_code == 200
    assert response.json()["success"] is True

    db_session.expire_all()
    archived = (
        db_session.query(PendingRelease)
        .filter(PendingRelease.id == pending_release.id)
        .first()
    )
    assert archived is not None
    assert archived.status == "archived"

    default_list_response = client.get(
        "/api/admin/pending-releases",
        headers=admin_headers,
    )
    assert default_list_response.status_code == 200
    assert all(item["id"] != pending_release.id for item in default_list_response.json())

    archived_list_response = client.get(
        "/api/admin/pending-releases?status_filter=archived",
        headers=admin_headers,
    )
    assert archived_list_response.status_code == 200
    assert any(item["id"] == pending_release.id for item in archived_list_response.json())


def test_delete_pending_release_removes_it(
    client,
    db_session,
    admin_headers,
):
    pending_release = PendingRelease(
        artist_name="Delete Artist",
        artist_email="delete@example.com",
        artist_data_json="{}",
        release_title="Delete Target",
        release_data_json="{}",
        status="pending",
    )
    db_session.add(pending_release)
    db_session.commit()
    db_session.refresh(pending_release)

    response = client.delete(
        f"/api/admin/pending-releases/{pending_release.id}",
        headers=admin_headers,
    )

    assert response.status_code == 200
    assert response.json()["success"] is True

    db_session.expire_all()
    deleted = (
        db_session.query(PendingRelease)
        .filter(PendingRelease.id == pending_release.id)
        .first()
    )
    assert deleted is None
