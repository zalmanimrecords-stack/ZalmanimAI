"""Execute campaign send: load campaign and targets, call senders, record deliveries."""

import json
from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models.models import Campaign, CampaignDelivery, CampaignTarget, HubConnector, SocialConnection
from app.services.campaign_service import (
    get_campaign,
    set_campaign_failed,
    set_campaign_sending,
    set_campaign_sent,
)
from app.services.hub_connectors import publish_wordpress_content
from app.services.mailchimp_service import send_mailchimp_campaign
from app.services.social_publisher import publish_social


def run_campaign_send(db: Session, campaign_id: int) -> None:
    """
    Load campaign and targets, set status to sending, run each target sender, record deliveries.
    Sets campaign status to sent or failed.
    """
    campaign = get_campaign(db, campaign_id)
    if not campaign:
        return
    if campaign.status != "scheduled":
        return
    set_campaign_sending(db, campaign_id)
    db.commit()

    title = campaign.title or ""
    body_text = campaign.body_text or ""
    body_html = campaign.body_html or body_text.replace("\n", "<br>\n")
    media_url = campaign.media_url

    any_failed = False
    for target in campaign.targets:
        delivery_status = "sent"
        external_id = None
        error_message = None
        try:
            if target.channel_type == "social":
                conn = db.query(SocialConnection).filter(
                    SocialConnection.id == int(target.external_id),
                    SocialConnection.status == "connected",
                ).first()
                if not conn:
                    delivery_status = "failed"
                    error_message = "Social connection not found or disconnected."
                else:
                    ok, msg, ext_id = publish_social(conn, text=body_text, media_url=media_url)
                    if not ok:
                        delivery_status = "failed"
                        error_message = msg
                    else:
                        external_id = ext_id
            elif target.channel_type == "mailchimp":
                connector = db.query(HubConnector).filter(
                    HubConnector.id == int(target.external_id),
                    HubConnector.connector_type == "mailchimp",
                ).first()
                if not connector:
                    delivery_status = "failed"
                    error_message = "Mailchimp connector not found."
                else:
                    config = json.loads(connector.config_json or "{}")
                    payload = json.loads(target.channel_payload or "{}")
                    list_id = payload.get("list_id")
                    if not list_id:
                        delivery_status = "failed"
                        error_message = "list_id required in target payload."
                    else:
                        ok, msg, ext_id = send_mailchimp_campaign(
                            config,
                            list_id=list_id,
                            subject_line=title,
                            html_content=body_html,
                            from_name=payload.get("from_name") or "LabelOps",
                            reply_to=payload.get("reply_to"),
                        )
                        if not ok:
                            delivery_status = "failed"
                            error_message = msg
                        else:
                            external_id = ext_id
            elif target.channel_type == "wordpress":
                connector = db.query(HubConnector).filter(
                    HubConnector.id == int(target.external_id),
                    HubConnector.connector_type == "wordpress_codex",
                ).first()
                if not connector:
                    delivery_status = "failed"
                    error_message = "WordPress connector not found."
                else:
                    config = json.loads(connector.config_json or "{}")
                    payload = json.loads(target.channel_payload or "{}")
                    post_type = payload.get("post_type") or "post"
                    status = payload.get("status") or "publish"
                    ok, msg, ext_id = publish_wordpress_content(
                        config,
                        title=title,
                        content=body_html,
                        post_type=post_type,
                        status=status,
                    )
                    if not ok:
                        delivery_status = "failed"
                        error_message = msg
                    else:
                        external_id = ext_id
            else:
                delivery_status = "failed"
                error_message = f"Unknown channel_type: {target.channel_type}"
        except Exception as e:
            delivery_status = "failed"
            error_message = str(e)
        if delivery_status == "failed":
            any_failed = True
        delivery = CampaignDelivery(
            campaign_id=campaign_id,
            target_id=target.id,
            channel_type=target.channel_type,
            status=delivery_status,
            external_id=external_id,
            error_message=error_message,
        )
        db.add(delivery)
    db.commit()
    if any_failed:
        set_campaign_failed(db, campaign_id)
    else:
        set_campaign_sent(db, campaign_id)
    db.commit()


def get_campaigns_ready_to_send(db: Session, limit: int = 10) -> list[Campaign]:
    """Return campaigns with status=scheduled and (scheduled_at is None or scheduled_at <= now)."""
    now = datetime.now(timezone.utc)
    return (
        db.query(Campaign)
        .filter(
            Campaign.status == "scheduled",
            (Campaign.scheduled_at.is_(None)) | (Campaign.scheduled_at <= now),
        )
        .order_by(Campaign.scheduled_at.asc().nullsfirst())
        .limit(limit)
        .all()
    )