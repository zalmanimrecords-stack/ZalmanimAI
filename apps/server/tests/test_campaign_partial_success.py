"""Campaign partial success and retry-failed targets."""

from unittest.mock import patch

from app.models.models import Campaign, CampaignDelivery, CampaignTarget
from app.services.campaign_send import run_campaign_retry_failed, run_campaign_send


def _campaign_with_two_targets(db_session) -> Campaign:
    campaign = Campaign(name="Test", title="Title", body_text="Body", status="scheduled")
    db_session.add(campaign)
    db_session.flush()
    db_session.add_all(
        [
            CampaignTarget(
                campaign_id=campaign.id,
                channel_type="social",
                external_id="1",
                channel_payload="{}",
            ),
            CampaignTarget(
                campaign_id=campaign.id,
                channel_type="wordpress",
                external_id="2",
                channel_payload="{}",
            ),
        ]
    )
    db_session.commit()
    db_session.refresh(campaign)
    return campaign


def test_campaign_send_sets_partial_when_mixed_results(db_session):
    campaign = _campaign_with_two_targets(db_session)

    def fake_send(db, *, target, title, body_text, body_html, media_url):
        if target.channel_type == "social":
            return "sent", "ext-1", None
        return "failed", None, "wordpress down"

    with patch("app.services.campaign_send._send_single_target", side_effect=fake_send):
        run_campaign_send(db_session, campaign.id)

    db_session.refresh(campaign)
    assert campaign.status == "partial"
    assert campaign.sent_at is not None
    deliveries = db_session.query(CampaignDelivery).filter(CampaignDelivery.campaign_id == campaign.id).all()
    assert len(deliveries) == 2


def test_retry_failed_only_retries_failed_targets(db_session):
    campaign = _campaign_with_two_targets(db_session)
    targets = db_session.query(CampaignTarget).filter(CampaignTarget.campaign_id == campaign.id).all()
    social_target, wp_target = targets[0], targets[1]
    db_session.add_all(
        [
            CampaignDelivery(
                campaign_id=campaign.id,
                target_id=social_target.id,
                channel_type="social",
                status="sent",
                external_id="ok",
            ),
            CampaignDelivery(
                campaign_id=campaign.id,
                target_id=wp_target.id,
                channel_type="wordpress",
                status="failed",
                error_message="first fail",
            ),
        ]
    )
    campaign.status = "partial"
    db_session.commit()

    calls = []

    def fake_send(db, *, target, title, body_text, body_html, media_url):
        calls.append(target.channel_type)
        return "sent", "retry-ok", None

    with patch("app.services.campaign_send._send_single_target", side_effect=fake_send):
        run_campaign_retry_failed(db_session, campaign.id)

    assert calls == ["wordpress"]
    db_session.refresh(campaign)
    assert campaign.status == "sent"
