import hashlib
import json
import os
from datetime import datetime, timedelta, timezone
from io import BytesIO
from urllib.parse import unquote, urlparse

from PIL import Image

from app.api import routes
from app.core.config import settings
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
    pending_id = pending_release.id

    response = client.delete(
        f"/api/admin/pending-releases/{pending_id}",
        headers=admin_headers,
    )

    assert response.status_code == 200
    assert response.json()["success"] is True

    db_session.expire_all()
    deleted = (
        db_session.query(PendingRelease)
        .filter(PendingRelease.id == pending_id)
        .first()
    )
    assert deleted is None


def test_admin_delete_pending_release_image_option_removes_file_and_updates_json(
    client,
    db_session,
    admin_headers,
    tmp_path,
    monkeypatch,
):
    monkeypatch.setattr(settings, "upload_dir", str(tmp_path))
    label_dir = tmp_path / "pending_release_label_images"
    label_dir.mkdir(parents=True)
    stored = "abc123face.png"
    (label_dir / stored).write_bytes(b"x")

    image_id = "img-option-1"
    url = f"http://testserver/api/public/pending-release-label-image/{stored}"
    pending_release = PendingRelease(
        artist_name="Img Artist",
        artist_email="img@example.com",
        artist_data_json="{}",
        release_title="Has Images",
        release_data_json=json.dumps(
            {
                "image_options": [
                    {"id": image_id, "url": url, "filename": "cover.png"},
                ],
                "selected_image_id": image_id,
            }
        ),
        status="pending",
    )
    db_session.add(pending_release)
    db_session.commit()
    db_session.refresh(pending_release)

    response = client.delete(
        f"/api/admin/pending-releases/{pending_release.id}/images/{image_id}",
        headers=admin_headers,
    )
    assert response.status_code == 200
    assert not os.path.isfile(str(label_dir / stored))

    db_session.expire_all()
    row = db_session.query(PendingRelease).filter(PendingRelease.id == pending_release.id).first()
    data = json.loads(row.release_data_json or "{}")
    assert data.get("image_options") == []
    assert data.get("selected_image_id") in (None, "")


def test_admin_upload_pending_release_image_uses_artist_and_release_name(
    client,
    db_session,
    admin_headers,
    tmp_path,
    monkeypatch,
):
    monkeypatch.setattr(settings, "upload_dir", str(tmp_path))
    monkeypatch.setattr(routes, "send_email_service", lambda **kwargs: (True, "Sent"))

    pending_release = PendingRelease(
        artist_name="Maya Waves",
        artist_email="maya@example.com",
        artist_data_json="{}",
        release_title="Ocean Lights",
        release_data_json="{}",
        status="pending",
    )
    db_session.add(pending_release)
    db_session.commit()
    db_session.refresh(pending_release)

    response = client.post(
        f"/api/admin/pending-releases/{pending_release.id}/images",
        headers=admin_headers,
        files={"file": ("cover draft.PNG", b"fake-image-bytes", "image/png")},
    )

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["image_options"]) == 1
    option = payload["image_options"][0]
    assert option["filename"] == "Maya Waves - Ocean Lights.png"

    stored_name = unquote(urlparse(option["url"]).path.split("/")[-1])
    assert stored_name == "Maya Waves - Ocean Lights.png"
    assert (tmp_path / "pending_release_label_images" / stored_name).is_file()


def test_admin_normalize_pending_release_image_writes_jpg_3000(
    client,
    db_session,
    admin_headers,
    tmp_path,
    monkeypatch,
):
    monkeypatch.setattr(settings, "upload_dir", str(tmp_path))
    label_dir = tmp_path / "pending_release_label_images"
    label_dir.mkdir(parents=True)
    stored = "before.png"
    buf = BytesIO()
    Image.new("RGB", (400, 200), color=(10, 20, 30)).save(buf, format="PNG")
    png_bytes = buf.getvalue()
    (label_dir / stored).write_bytes(png_bytes)

    image_id = "img-to-convert"
    url = f"http://testserver/api/public/pending-release-label-image/{stored}"
    pending_release = PendingRelease(
        artist_name="Convert Artist",
        artist_email="conv@example.com",
        artist_data_json="{}",
        release_title="Convert",
        release_data_json=json.dumps(
            {
                "image_options": [
                    {"id": image_id, "url": url, "filename": "before.png"},
                ],
                "selected_image_id": image_id,
            }
        ),
        status="pending",
    )
    db_session.add(pending_release)
    db_session.commit()
    db_session.refresh(pending_release)

    response = client.post(
        f"/api/admin/pending-releases/{pending_release.id}/images/{image_id}/normalize-jpg",
        headers=admin_headers,
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["image_options"]
    new_url = payload["image_options"][0]["url"]
    assert new_url.endswith(".jpg")
    assert not os.path.isfile(str(label_dir / stored))

    tail = urlparse(new_url).path.split("/")[-1]
    jpg_path = label_dir / tail
    assert jpg_path.is_file()
    out = Image.open(jpg_path)
    assert out.size == (3000, 3000)
    assert out.format == "JPEG"
