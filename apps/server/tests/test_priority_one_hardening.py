from app.models.models import Campaign, MailingList, MailingSubscriber
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
