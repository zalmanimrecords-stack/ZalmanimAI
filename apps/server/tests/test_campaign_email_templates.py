import secrets
from unittest.mock import patch

from app.models.models import EmailCampaignTemplate, MailingList, MailingSubscriber
from app.services.campaign_email_service import merge_campaign_content, send_email_campaign_to_list


def test_merge_campaign_content_placeholders():
    out = merge_campaign_content(
        "Hi {{first_name}}, unsubscribe: {unsubscribe_url}",
        email="a@b.com",
        full_name="Maya Cohen",
        unsubscribe_url="https://example.com/u/1",
    )
    assert "Hi Maya," in out
    assert "https://example.com/u/1" in out


def test_admin_crud_campaign_email_templates(client, admin_headers):
    create = client.post(
        "/api/admin/campaign-email-templates",
        headers=admin_headers,
        json={
            "name": "Launch",
            "subject": "New music from {first_name}",
            "body_text": "Hello {{full_name}}",
        },
    )
    assert create.status_code == 200
    tid = create.json()["id"]

    listed = client.get("/api/admin/campaign-email-templates", headers=admin_headers)
    assert listed.status_code == 200
    assert any(row["id"] == tid for row in listed.json())

    updated = client.patch(
        f"/api/admin/campaign-email-templates/{tid}",
        headers=admin_headers,
        json={"description": "Release blast"},
    )
    assert updated.status_code == 200
    assert updated.json()["description"] == "Release blast"

    deleted = client.delete(
        f"/api/admin/campaign-email-templates/{tid}",
        headers=admin_headers,
    )
    assert deleted.status_code == 200


def test_send_email_campaign_to_list(db_session):
    mailing_list = MailingList(
        name="Fans",
        physical_address="123 Main St, Tel Aviv",
        company_name="Zalmanim",
    )
    db_session.add(mailing_list)
    db_session.flush()
    db_session.add(
        MailingSubscriber(
            list_id=mailing_list.id,
            email="fan@example.com",
            full_name="Fan One",
            status="subscribed",
            unsubscribe_token=secrets.token_urlsafe(24),
        )
    )
    db_session.commit()

    with patch("app.services.campaign_email_service.send_email", return_value=(True, "Sent")):
        ok, msg, summary = send_email_campaign_to_list(
            db_session,
            list_id=mailing_list.id,
            subject="Hello",
            body_text="Body",
            body_html=None,
        )
    assert ok is True
    assert "sent=1" in summary
