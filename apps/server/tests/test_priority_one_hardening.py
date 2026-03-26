import pytest
from sqlalchemy import text

from app.api import routes
from app.core.config import Settings
from app import main
from app.models.models import (
    Artist,
    ArtistRegistrationToken,
    Campaign,
    MailingList,
    MailingSubscriber,
    SocialConnection,
    migrate_legacy_social_connection_tokens,
)
from app.services.campaign_service import claim_scheduled_campaign_for_sending, get_campaign


def test_unsubscribe_page_escapes_user_content(client, db_session):
    mailing_list = MailingList(name='<script>alert("x")</script>')
    db_session.add(mailing_list)
    db_session.commit()
    db_session.refresh(mailing_list)

    subscriber = MailingSubscriber(
        list_id=mailing_list.id,
        email='<b>person@example.com</b>',
        unsubscribe_token="token-123",
        status="subscribed",
    )
    db_session.add(subscriber)
    db_session.commit()

    response = client.get("/api/unsubscribe/token-123")

    assert response.status_code == 200
    assert "<script>alert" not in response.text
    assert "&lt;script&gt;alert" in response.text
    assert "&lt;b&gt;person@example.com&lt;/b&gt;" in response.text


def test_login_endpoint_rate_limits_before_auth_lookup(client, monkeypatch):
    from app.api import routes

    monkeypatch.setattr(routes.auth_rate_limit, "check_login_allowed", lambda **kwargs: (False, 9))

    response = client.post(
        "/api/auth/login",
        json={"email": "admin@example.com", "password": "wrong"},
    )

    assert response.status_code == 429
    assert "Too many login attempts" in response.json()["detail"]


def test_claim_scheduled_campaign_for_sending_is_atomic(db_session):
    campaign = Campaign(
        name="Queued",
        title="Hello",
        body_text="World",
        status="scheduled",
    )
    db_session.add(campaign)
    db_session.commit()
    db_session.refresh(campaign)

    first_claim = claim_scheduled_campaign_for_sending(db_session, campaign.id)
    second_claim = claim_scheduled_campaign_for_sending(db_session, campaign.id)
    refreshed = get_campaign(db_session, campaign.id)

    assert first_claim is not None
    assert second_claim is None
    assert refreshed is not None
    assert refreshed.status == "sending"


def test_security_headers_are_added(client):
    health_response = client.get("/health")
    root_response = client.get("/")

    assert health_response.headers["x-content-type-options"] == "nosniff"
    assert health_response.headers["x-frame-options"] == "DENY"
    assert health_response.headers["referrer-policy"] == "no-referrer"
    assert "content-security-policy" not in health_response.headers
    assert "content-security-policy" in root_response.headers


def test_api_docs_are_disabled_by_default():
    assert Settings().api_docs_enabled is False


def test_cors_origins_require_explicit_values(monkeypatch):
    monkeypatch.setattr(main.settings, "cors_allowed_origins", "", raising=False)

    assert main._cors_origins() == []
    assert main._cors_origin_regex() is not None

    monkeypatch.setattr(
        main.settings,
        "cors_allowed_origins",
        "http://localhost:3000, http://127.0.0.1:5173",
        raising=False,
    )

    assert main._cors_origins() == ["http://localhost:3000", "http://127.0.0.1:5173"]
    assert main._cors_origin_regex() is None


def test_runtime_validation_rejects_missing_required_settings(monkeypatch):
    monkeypatch.setattr(main.settings, "jwt_secret", "", raising=False)
    monkeypatch.setattr(main.settings, "database_url", "", raising=False)
    monkeypatch.setattr(main.settings, "cors_allowed_origins", "", raising=False)

    with pytest.raises(RuntimeError, match="JWT_SECRET is required"):
        main._validate_runtime_configuration()


def test_runtime_validation_rejects_wildcard_cors(monkeypatch):
    monkeypatch.setattr(main.settings, "jwt_secret", "x" * 32, raising=False)
    monkeypatch.setattr(main.settings, "database_url", "sqlite:///test.db", raising=False)
    monkeypatch.setattr(main.settings, "cors_allowed_origins", "http://localhost:3000,*", raising=False)

    with pytest.raises(RuntimeError, match="must not contain"):
        main._validate_runtime_configuration()


def test_runtime_validation_rejects_short_token_encryption_key():
    config = Settings(
        _env_file=None,
        environment="development",
        database_url="sqlite:///prod.db",
        jwt_secret="x" * 32,
        token_encryption_key="short-key",
    )

    with pytest.raises(ValueError, match="TOKEN_ENCRYPTION_KEY"):
        config.validate_runtime()


def test_settings_validate_runtime_rejects_unsafe_production_defaults():
    config = Settings(
        _env_file=None,
        environment="production",
        database_url="sqlite:///prod.db",
        jwt_secret="x" * 32,
    )

    with pytest.raises(ValueError) as exc:
        config.validate_runtime()

    message = str(exc.value)
    assert "CORS_ALLOWED_ORIGINS" in message


def test_trusted_host_list_derives_known_production_domains():
    config = Settings(
        _env_file=None,
        environment="production",
        database_url="sqlite:///prod.db",
        jwt_secret="x" * 32,
        cors_allowed_origins="https://lm.zalmanim.com,https://artists.zalmanim.com",
        oauth_redirect_base="https://lmapi.zalmanim.com/api/admin/social/callback",
    )

    trusted_hosts = config.trusted_host_list()

    assert "lm.zalmanim.com" in trusted_hosts
    assert "artists.zalmanim.com" in trusted_hosts
    assert "lmapi.zalmanim.com" in trusted_hosts


def test_public_demo_submission_allows_configured_origin_without_secret_header(client, monkeypatch):
    monkeypatch.setattr(routes.settings, "demo_submission_token", "shared-secret-demo-token", raising=False)
    monkeypatch.setattr(routes.settings, "public_demo_allowed_origins", "https://artists.zalmanim.com", raising=False)

    response = client.post(
        "/api/public/demo-submissions",
        headers={"Origin": "https://artists.zalmanim.com"},
        json={
            "artist_name": "Maya Waves",
            "email": "maya@example.com",
            "consent_to_emails": True,
            "source": "artists_portal_landing",
            "source_site_url": "https://artists.zalmanim.com",
            "links": ["https://soundcloud.com/demo-track"],
            "fields": {},
        },
    )

    assert response.status_code == 200


def test_public_demo_submission_rejects_unknown_origin_without_secret_header(client, monkeypatch):
    monkeypatch.setattr(routes.settings, "demo_submission_token", "shared-secret-demo-token", raising=False)
    monkeypatch.setattr(routes.settings, "public_demo_allowed_origins", "https://artists.zalmanim.com", raising=False)

    response = client.post(
        "/api/public/demo-submissions",
        headers={"Origin": "https://evil.example"},
        json={
            "artist_name": "Maya Waves",
            "email": "maya@example.com",
            "consent_to_emails": True,
            "source": "artists_portal_landing",
            "source_site_url": "https://artists.zalmanim.com",
            "links": ["https://soundcloud.com/demo-track"],
            "fields": {},
        },
    )

    assert response.status_code == 401


def test_public_artist_registration_rejects_short_password(client, db_session):
    artist = Artist(
        name="Groover Waves",
        email="groover@example.com",
        notes="Source: Groover",
        is_active=True,
    )
    db_session.add(artist)
    db_session.flush()

    raw_token = "groover-token"
    import hashlib
    from datetime import datetime, timedelta, timezone

    token = ArtistRegistrationToken(
        artist_id=artist.id,
        email=artist.email,
        source="groover",
        token_hash=hashlib.sha256(raw_token.encode()).hexdigest(),
        expires_at=datetime.now(timezone.utc) + timedelta(days=1),
    )
    db_session.add(token)
    db_session.commit()

    response = client.post(
        "/api/public/artist-registration",
        json={
            "token": raw_token,
            "artist_name": "Groover Waves",
            "full_name": "Maya Cohen",
            "soundcloud": "https://soundcloud.com/groover-waves",
            "instagram": "https://instagram.com/grooverwaves",
            "password": "Short123",
        },
    )

    assert response.status_code == 400
    assert "at least 12 characters" in response.json()["detail"]


def test_admin_restore_rejects_oversized_upload(client, admin_headers, monkeypatch):
    monkeypatch.setattr(routes, "MAX_RESTORE_BYTES", 5, raising=False)

    response = client.post(
        "/api/admin/restore",
        headers=admin_headers,
        files={"file": ("backup.json", b"0123456789", "application/json")},
    )

    assert response.status_code == 400
    assert "too large" in response.json()["detail"]


def test_social_connection_tokens_are_encrypted_at_rest(db_session, monkeypatch):
    monkeypatch.setattr(routes.settings, "token_encryption_key", "token-encryption-key-1234567890abcd", raising=False)

    connection = SocialConnection(
        provider="google_mail",
        account_label="alerts@example.com",
        status="active",
        access_token="plain-access-token",
        refresh_token="plain-refresh-token",
    )
    db_session.add(connection)
    db_session.commit()
    db_session.expire_all()

    stored = db_session.execute(
        text("SELECT access_token, refresh_token FROM social_connections WHERE id = :id"),
        {"id": connection.id},
    ).mappings().one()

    assert stored["access_token"] != "plain-access-token"
    assert stored["refresh_token"] != "plain-refresh-token"
    assert stored["access_token"].startswith("enc:v1:")
    assert stored["refresh_token"].startswith("enc:v1:")

    reloaded = db_session.get(SocialConnection, connection.id)
    assert reloaded.access_token == "plain-access-token"
    assert reloaded.refresh_token == "plain-refresh-token"


def test_legacy_social_connection_tokens_are_migrated(db_session, monkeypatch):
    monkeypatch.setattr(routes.settings, "token_encryption_key", "token-encryption-key-1234567890abcd", raising=False)

    db_session.execute(
        text(
            """
            INSERT INTO social_connections (
                provider,
                account_label,
                status,
                access_token,
                refresh_token,
                scopes_csv
            ) VALUES (
                'google_mail',
                'legacy@example.com',
                'active',
                'legacy-access-token',
                'legacy-refresh-token',
                ''
            )
            """
        )
    )
    db_session.commit()

    migrated = migrate_legacy_social_connection_tokens(db_session)
    assert migrated == 1

    stored = db_session.execute(
        text(
            "SELECT id, access_token, refresh_token FROM social_connections WHERE account_label = 'legacy@example.com'"
        )
    ).mappings().one()
    assert stored["access_token"].startswith("enc:v1:")
    assert stored["refresh_token"].startswith("enc:v1:")

    reloaded = db_session.get(SocialConnection, stored["id"])
    assert reloaded.access_token == "legacy-access-token"
    assert reloaded.refresh_token == "legacy-refresh-token"
