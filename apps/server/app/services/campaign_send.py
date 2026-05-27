"""Execute campaign send: load campaign and targets, call senders, record deliveries."""

import json
from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models.models import Campaign, CampaignDelivery, CampaignTarget, HubConnector, SocialConnection
from app.services.campaign_service import (
    claim_campaign_for_retry,
    claim_scheduled_campaign_for_sending,
    finalize_campaign_send_status,
    latest_delivery_by_target,
)
from app.services.hub_connectors import publish_wordpress_content
from app.services.mailchimp_service import send_mailchimp_campaign
from app.services.social_publisher import publish_social


def _send_single_target(
    db: Session,
    *,
    target: CampaignTarget,
    title: str,
    body_text: str,
    body_html: str,
    media_url: str | None,
) -> tuple[str, str | None, str | None]:
    """Returns (delivery_status, external_id, error_message)."""
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
                post_status = payload.get("status") or "publish"
                ok, msg, ext_id = publish_wordpress_content(
                    config,
                    title=title,
                    content=body_html,
                    post_type=post_type,
                    status=post_status,
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
    return delivery_status, external_id, error_message


def _record_delivery(
    db: Session,
    *,
    campaign_id: int,
    target: CampaignTarget,
    delivery_status: str,
    external_id: str | None,
    error_message: str | None,
) -> bool:
    db.add(
        CampaignDelivery(
            campaign_id=campaign_id,
            target_id=target.id,
            channel_type=target.channel_type,
            status=delivery_status,
            external_id=external_id,
            error_message=error_message,
        )
    )
    return delivery_status == "sent"


def run_campaign_send(db: Session, campaign_id: int) -> None:
    """
    Load campaign and targets, set status to sending, run each target sender, record deliveries.
    Sets campaign status to sent, partial, or failed.
    """
    campaign = claim_scheduled_campaign_for_sending(db, campaign_id)
    if not campaign:
        return

    _execute_campaign_targets(db, campaign)
    db.commit()


def run_campaign_retry_failed(db: Session, campaign_id: int) -> None:
    """Retry only targets whose latest delivery failed (or have no delivery yet)."""
    campaign = claim_campaign_for_retry(db, campaign_id)
    if not campaign:
        return

    latest = latest_delivery_by_target(db, campaign_id)
    targets_to_retry = [
        target
        for target in campaign.targets
        if target.id not in latest or latest[target.id].status == "failed"
    ]
    if not targets_to_retry:
        finalize_campaign_send_status(db, campaign_id)
        db.commit()
        return

    _execute_campaign_targets(db, campaign, targets=targets_to_retry)
    db.commit()


def _execute_campaign_targets(
    db: Session,
    campaign: Campaign,
    *,
    targets: list[CampaignTarget] | None = None,
) -> None:
    title = campaign.title or ""
    body_text = campaign.body_text or ""
    body_html = campaign.body_html or body_text.replace("\n", "<br>\n")
    media_url = campaign.media_url
    target_list = targets if targets is not None else list(campaign.targets)

    sent_count = 0
    failed_count = 0
    for target in target_list:
        delivery_status, external_id, error_message = _send_single_target(
            db,
            target=target,
            title=title,
            body_text=body_text,
            body_html=body_html,
            media_url=media_url,
        )
        if _record_delivery(
            db,
            campaign_id=campaign.id,
            target=target,
            delivery_status=delivery_status,
            external_id=external_id,
            error_message=error_message,
        ):
            sent_count += 1
        else:
            failed_count += 1

    db.flush()
    finalize_campaign_send_status(db, campaign.id, sent_delta=sent_count, failed_delta=failed_count)


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
