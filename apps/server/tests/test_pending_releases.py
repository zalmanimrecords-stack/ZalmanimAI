from app.api import routes
from app.models.models import Artist, ArtistActivityLog, PendingRelease, PendingReleaseToken


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
