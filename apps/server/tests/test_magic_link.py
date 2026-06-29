"""Passwordless email magic-link login: request + verify endpoints."""

import re
from datetime import datetime, timedelta, timezone

import pytest

from app.models.models import Artist, LoginToken, User


GENERIC_MESSAGE = "If an account exists with this email, a login link is on its way."


@pytest.fixture
def capture_emails(monkeypatch):
    """Capture outgoing emails instead of sending; return the list of sent messages."""
    sent: list[dict] = []

    def fake_send_email_service(*, to_email, subject, body_text, body_html=None):
        sent.append(
            {"to": to_email, "subject": subject, "text": body_text, "html": body_html or ""}
        )
        return True, "captured"

    monkeypatch.setattr("app.api.routes.send_email_service", fake_send_email_service)
    return sent


def _token_from_email(message: dict) -> str:
    match = re.search(r"login_token=([^\s\"&<]+)", message["text"] + message["html"])
    assert match, f"no login_token in email: {message}"
    return match.group(1)


def _make_artist(db_session, email="artist@example.com"):
    artist = Artist(name="Test Artist", email=email, is_active=True)
    db_session.add(artist)
    db_session.commit()
    db_session.refresh(artist)
    return artist


def _make_admin(db_session, email="admin@example.com"):
    user = User(email=email, full_name="Admin", role="admin", is_active=True)
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


def test_request_sends_link_for_artist(client, db_session, capture_emails):
    _make_artist(db_session)
    resp = client.post(
        "/api/auth/request-magic-link",
        json={"email": "artist@example.com", "audience": "artist"},
    )
    assert resp.status_code == 200
    assert resp.json()["message"] == GENERIC_MESSAGE

    assert len(capture_emails) == 1
    assert "login_token=" in capture_emails[0]["text"]
    assert "artists.zalmanim.com" in capture_emails[0]["text"]

    row = db_session.query(LoginToken).one()
    assert row.subject.startswith("artist:")
    # ~5 minutes expiry (allow slack for execution time). SQLite drops tzinfo on read, so
    # normalize to naive UTC before comparing.
    expires_at = row.expires_at
    if expires_at.tzinfo is not None:
        expires_at = expires_at.astimezone(timezone.utc).replace(tzinfo=None)
    remaining = expires_at - datetime.now(timezone.utc).replace(tzinfo=None)
    assert timedelta(minutes=4) < remaining <= timedelta(minutes=5)


def test_request_unknown_email_is_generic_and_sends_nothing(client, db_session, capture_emails):
    resp = client.post(
        "/api/auth/request-magic-link",
        json={"email": "nobody@example.com", "audience": "artist"},
    )
    assert resp.status_code == 200
    assert resp.json()["message"] == GENERIC_MESSAGE
    assert capture_emails == []
    assert db_session.query(LoginToken).count() == 0


def test_magic_login_artist_happy_path(client, db_session, capture_emails):
    _make_artist(db_session)
    client.post(
        "/api/auth/request-magic-link",
        json={"email": "artist@example.com", "audience": "artist"},
    )
    token = _token_from_email(capture_emails[0])

    resp = client.post("/api/auth/magic-login", json={"token": token})
    assert resp.status_code == 200
    body = resp.json()
    assert body["role"] == "artist"
    assert body["access_token"]
    # single-use: token row consumed
    assert db_session.query(LoginToken).count() == 0


def test_magic_login_admin_token_works_on_protected_route(client, db_session, capture_emails):
    _make_admin(db_session)
    client.post(
        "/api/auth/request-magic-link",
        json={"email": "admin@example.com", "audience": "admin"},
    )
    assert "lm.zalmanim.com" in capture_emails[0]["text"]
    token = _token_from_email(capture_emails[0])

    resp = client.post("/api/auth/magic-login", json={"token": token})
    assert resp.status_code == 200
    access_token = resp.json()["access_token"]

    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {access_token}"})
    assert me.status_code == 200
    assert me.json()["email"] == "admin@example.com"


def test_magic_login_is_single_use(client, db_session, capture_emails):
    _make_artist(db_session)
    client.post(
        "/api/auth/request-magic-link",
        json={"email": "artist@example.com", "audience": "artist"},
    )
    token = _token_from_email(capture_emails[0])

    assert client.post("/api/auth/magic-login", json={"token": token}).status_code == 200
    assert client.post("/api/auth/magic-login", json={"token": token}).status_code == 400


def test_magic_login_rejects_expired(client, db_session, capture_emails):
    _make_artist(db_session)
    client.post(
        "/api/auth/request-magic-link",
        json={"email": "artist@example.com", "audience": "artist"},
    )
    token = _token_from_email(capture_emails[0])

    row = db_session.query(LoginToken).one()
    row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db_session.commit()

    assert client.post("/api/auth/magic-login", json={"token": token}).status_code == 400


def test_magic_login_rejects_garbage_token(client, db_session):
    assert client.post("/api/auth/magic-login", json={"token": "not-a-real-token"}).status_code == 400


def test_request_rate_limited_returns_429(client, db_session, capture_emails, monkeypatch):
    _make_artist(db_session)
    monkeypatch.setattr(
        "app.services.auth_rate_limit.check_login_allowed",
        lambda *, email, client_ip: (False, 30),
    )
    resp = client.post(
        "/api/auth/request-magic-link",
        json={"email": "artist@example.com", "audience": "artist"},
    )
    assert resp.status_code == 429
    assert capture_emails == []
