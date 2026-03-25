from types import SimpleNamespace

from sqlalchemy import text
from sqlalchemy.orm import sessionmaker

from app.models.models import SocialConnection
from app.services import email_service, social_publisher


def _raw_social_connection_row(db_session, connection_id: int):
    return db_session.execute(
        text("SELECT access_token, refresh_token FROM social_connections WHERE id = :id"),
        {"id": connection_id},
    ).one()


def test_social_connection_tokens_are_encrypted_at_rest(db_session):
    connection = SocialConnection(
        provider="google_mail",
        account_label="mail@example.com",
        status="active",
        scopes_csv="https://www.googleapis.com/auth/gmail.send",
    )
    connection.access_token = "access-token-123"
    connection.refresh_token = "refresh-token-456"
    db_session.add(connection)
    db_session.commit()
    db_session.expire_all()

    row = _raw_social_connection_row(db_session, connection.id)
    assert row.access_token.startswith("enc:v1:")
    assert row.refresh_token.startswith("enc:v1:")
    assert row.access_token != "access-token-123"
    assert row.refresh_token != "refresh-token-456"

    reloaded = db_session.get(SocialConnection, connection.id)
    assert reloaded is not None
    assert reloaded.access_token == "access-token-123"
    assert reloaded.refresh_token == "refresh-token-456"


def test_social_connection_legacy_plaintext_tokens_upgrade_on_use(db_session):
    db_session.execute(
        text(
            """
            INSERT INTO social_connections (
                provider, account_label, status, scopes_csv, access_token, refresh_token
            ) VALUES (
                :provider, :account_label, :status, :scopes_csv, :access_token, :refresh_token
            )
            """
        ),
        {
            "provider": "google_mail",
            "account_label": "legacy@example.com",
            "status": "active",
            "scopes_csv": "https://www.googleapis.com/auth/gmail.send",
            "access_token": "legacy-access-token",
            "refresh_token": "legacy-refresh-token",
        },
    )
    db_session.commit()

    connection = db_session.query(SocialConnection).filter(SocialConnection.provider == "google_mail").first()
    assert connection is not None
    assert connection.access_token == "legacy-access-token"
    assert connection.refresh_token == "legacy-refresh-token"

    db_session.commit()
    row = _raw_social_connection_row(db_session, connection.id)
    assert row.access_token.startswith("enc:v1:")
    assert row.refresh_token.startswith("enc:v1:")


def test_email_service_persists_token_encryption_for_active_gmail_connection(db_session, monkeypatch):
    db_session.execute(
        text(
            """
            INSERT INTO social_connections (
                provider, account_label, status, scopes_csv, access_token, refresh_token
            ) VALUES (
                :provider, :account_label, :status, :scopes_csv, :access_token, :refresh_token
            )
            """
        ),
        {
            "provider": "google_mail",
            "account_label": "gmail@example.com",
            "status": "active",
            "scopes_csv": "https://www.googleapis.com/auth/gmail.send",
            "access_token": "gmail-access-token",
            "refresh_token": "gmail-refresh-token",
        },
    )
    db_session.commit()

    factory = sessionmaker(bind=db_session.bind, autoflush=False, autocommit=False)
    monkeypatch.setattr(email_service, "SessionLocal", factory)

    connection = email_service._get_active_gmail_connection()
    assert connection is not None
    assert connection.access_token == "gmail-access-token"
    assert connection.refresh_token == "gmail-refresh-token"

    row = _raw_social_connection_row(db_session, connection.id)
    assert row.access_token.startswith("enc:v1:")
    assert row.refresh_token.startswith("enc:v1:")


def test_social_publisher_marks_tokens_for_encryption_on_use(db_session, monkeypatch):
    db_session.execute(
        text(
            """
            INSERT INTO social_connections (
                provider, account_label, status, scopes_csv, access_token
            ) VALUES (
                :provider, :account_label, :status, :scopes_csv, :access_token
            )
            """
        ),
        {
            "provider": "threads",
            "account_label": "threads@example.com",
            "status": "connected",
            "scopes_csv": "threads.basic",
            "access_token": "threads-access-token",
        },
    )
    db_session.commit()

    connection = db_session.query(SocialConnection).filter(SocialConnection.provider == "threads").first()
    assert connection is not None

    def fake_post(*args, **kwargs):
        return SimpleNamespace(status_code=200, json=lambda: {"id": "post-123"}, text="ok")

    monkeypatch.setattr(social_publisher.httpx, "post", fake_post)

    ok, message, external_id = social_publisher.publish_social(connection, text="Hello Threads")

    assert ok is True
    assert message == "Published"
    assert external_id == "post-123"

    db_session.commit()
    row = _raw_social_connection_row(db_session, connection.id)
    assert row.access_token.startswith("enc:v1:")
