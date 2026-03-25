"""Campaign CRUD and target management. No send logic here."""

import json
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import update
from sqlalchemy.orm import Session, joinedload

from app.models.models import Campaign, CampaignTarget


def create_campaign(
    db: Session,
    *,
    name: str,
    title: str,
    body_text: str = "",
    body_html: str | None = None,
    media_url: str | None = None,
    artist_id: int | None = None,
    targets: list[dict[str, Any]] | None = None,
) -> Campaign:
    """Create a draft campaign with optional targets. Targets: list of {channel_type, external_id, channel_payload}."""
    campaign = Campaign(
        artist_id=artist_id,
        name=name,
        title=title,
        body_text=body_text or "",
        body_html=body_html,
        media_url=media_url,
        status="draft",
    )
    db.add(campaign)
    db.flush()
    if targets:
        for t in targets:
            payload = t.get("channel_payload") or {}
            target = CampaignTarget(
                campaign_id=campaign.id,
                channel_type=t["channel_type"],
                external_id=str(t["external_id"]),
                channel_payload=json.dumps(payload) if isinstance(payload, dict) else str(payload),
            )
            db.add(target)
    db.commit()
    db.refresh(campaign)
    return campaign


def get_campaign(db: Session, campaign_id: int) -> Campaign | None:
    return db.query(Campaign).filter(Campaign.id == campaign_id).first()


def list_campaigns(
    db: Session,
    *,
    status: str | None = None,
    limit: int = 100,
    offset: int = 0,
) -> list[Campaign]:
    q = db.query(Campaign).order_by(Campaign.created_at.desc())
    if status:
        q = q.filter(Campaign.status == status)
    return q.offset(offset).limit(limit).all()


def update_campaign(
    db: Session,
    campaign_id: int,
    *,
    name: str | None = None,
    title: str | None = None,
    body_text: str | None = None,
    body_html: str | None = None,
    media_url: str | None = None,
    artist_id: int | None = None,
    targets: list[dict[str, Any]] | None = None,
) -> Campaign | None:
    """Update campaign fields and optionally replace targets. Only draft/scheduled can be updated."""
    campaign = get_campaign(db, campaign_id)
    if not campaign:
        return None
    if campaign.status not in ("draft", "scheduled"):
        return None
    if name is not None:
        campaign.name = name
    if title is not None:
        campaign.title = title
    if body_text is not None:
        campaign.body_text = body_text
    if body_html is not None:
        campaign.body_html = body_html
    if media_url is not None:
        campaign.media_url = media_url
    if artist_id is not None:
        campaign.artist_id = artist_id
    if targets is not None:
        # Replace targets: delete existing, add new
        db.query(CampaignTarget).filter(CampaignTarget.campaign_id == campaign_id).delete()
        for t in targets:
            payload = t.get("channel_payload") or {}
            target = CampaignTarget(
                campaign_id=campaign.id,
                channel_type=t["channel_type"],
                external_id=str(t["external_id"]),
                channel_payload=json.dumps(payload) if isinstance(payload, dict) else str(payload),
            )
            db.add(target)
    db.commit()
    # Reload campaign with targets so response has correct data
    campaign = db.query(Campaign).options(joinedload(Campaign.targets)).filter(Campaign.id == campaign_id).first()
    return campaign


def delete_campaign(db: Session, campaign_id: int) -> bool:
    """Delete campaign and its targets/deliveries. Only draft or failed can be deleted."""
    campaign = get_campaign(db, campaign_id)
    if not campaign:
        return False
    if campaign.status not in ("draft", "failed"):
        return False
    db.delete(campaign)
    db.commit()
    return True


def set_campaign_scheduled(db: Session, campaign_id: int, scheduled_at: Any) -> Campaign | None:
    """Set status to scheduled and optional scheduled_at. None = send now."""
    campaign = get_campaign(db, campaign_id)
    if not campaign or campaign.status != "draft":
        return None
    campaign.status = "scheduled"
    campaign.scheduled_at = scheduled_at
    db.commit()
    db.refresh(campaign)
    return campaign


def set_campaign_sending(db: Session, campaign_id: int) -> Campaign | None:
    campaign = get_campaign(db, campaign_id)
    if not campaign:
        return None
    campaign.status = "sending"
    db.commit()
    db.refresh(campaign)
    return campaign


def claim_scheduled_campaign_for_sending(db: Session, campaign_id: int) -> Campaign | None:
    result = db.execute(
        update(Campaign)
        .where(Campaign.id == campaign_id, Campaign.status == "scheduled")
        .values(status="sending")
    )
    if result.rowcount != 1:
        db.rollback()
        return None
    db.commit()
    return (
        db.query(Campaign)
        .options(joinedload(Campaign.targets))
        .filter(Campaign.id == campaign_id)
        .first()
    )


def set_campaign_sent(db: Session, campaign_id: int) -> Campaign | None:
    campaign = get_campaign(db, campaign_id)
    if not campaign:
        return None
    campaign.status = "sent"
    campaign.sent_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(campaign)
    return campaign


def set_campaign_failed(db: Session, campaign_id: int) -> Campaign | None:
    campaign = get_campaign(db, campaign_id)
    if not campaign:
        return None
    campaign.status = "failed"
    db.commit()
    db.refresh(campaign)
    return campaign


def cancel_schedule(db: Session, campaign_id: int) -> Campaign | None:
    """Move scheduled campaign back to draft and clear scheduled_at."""
    campaign = get_campaign(db, campaign_id)
    if not campaign or campaign.status != "scheduled":
        return None
    campaign.status = "draft"
    campaign.scheduled_at = None
    db.commit()
    db.refresh(campaign)
    return campaign
