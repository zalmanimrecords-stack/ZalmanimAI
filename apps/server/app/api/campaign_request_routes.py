import hashlib
import logging
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import desc, or_
from sqlalchemy.orm import Session, joinedload

from app.api.deps import get_current_lm_user, get_current_user, require_admin, require_artist
from app.core.config import settings
from app.db.session import get_db
from app.models.models import Artist, CampaignRequest, PendingReleaseToken, Release
from app.schemas.schemas import CampaignRequestCreate, CampaignRequestOut, CampaignRequestUpdate, UserContext
from app.services.email_service import is_email_configured, send_email as send_email_service

router = APIRouter()


def _pending_release_form_link(raw_token: str) -> str:
    portal_url = (settings.artist_portal_base_url or "").strip() or "https://artists.zalmanim.com"
    return f"{portal_url.rstrip('/')}/#/pending-release?token={raw_token}"


def _campaign_request_out(r: CampaignRequest, artist_name: str, release_title: str | None) -> CampaignRequestOut:
    return CampaignRequestOut(
        id=r.id,
        artist_id=r.artist_id,
        artist_name=artist_name,
        release_id=r.release_id,
        release_title=release_title,
        message=r.message,
        status=r.status,
        admin_notes=r.admin_notes,
        created_at=r.created_at,
        updated_at=r.updated_at,
    )


def _create_pending_release_token_and_send_approval_email(
    db: Session,
    req: CampaignRequest,
    artist: Artist,
    release_title: str | None,
) -> None:
    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    form_link = _pending_release_form_link(raw_token)
    expires_at = datetime.now(timezone.utc) + timedelta(days=30)
    token_row = PendingReleaseToken(
        token_hash=token_hash,
        campaign_request_id=req.id,
        pending_release_id=None,
        artist_id=req.artist_id,
        expires_at=expires_at,
    )
    db.add(token_row)
    db.flush()

    artist_name = (artist.name or "").strip() or "there"
    subject = f"Your track was approved - next steps, {artist_name}"
    body = (
        f"Hi {artist_name},\n\n"
        "Thank you! We're happy to move forward and release the track you sent.\n\n"
        "Please fill in the form below with your full artist details and the track/release details "
        "so we can proceed:\n\n"
        f"{form_link}\n\n"
        "Best regards,\nZalmanim"
    )
    if release_title:
        body = (
            f"Hi {artist_name},\n\n"
            f'Thank you! We\'re happy to move forward and release "{release_title}".\n\n'
            "Please fill in the form below with your full artist details and the track/release details "
            "so we can proceed:\n\n"
            f"{form_link}\n\n"
            "Best regards,\nZalmanim"
        )
    if is_email_configured():
        success, message = send_email_service(
            to_email=artist.email,
            subject=subject,
            body_text=body,
        )
        if not success:
            logging.getLogger(__name__).warning(
                "Failed to send track-approved email to %s: %s", artist.email, message
            )


@router.post("/artist/me/campaign-requests", response_model=CampaignRequestOut)
def artist_create_campaign_request(
    payload: CampaignRequestCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> CampaignRequestOut:
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    release_title = None
    if payload.release_id:
        release = db.query(Release).filter(
            Release.id == payload.release_id,
            or_(Release.artist_id == user.artist_id, Release.artists.any(Artist.id == user.artist_id)),
        ).first()
        if not release:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release not found")
        release_title = release.title
    req = CampaignRequest(
        artist_id=user.artist_id,
        release_id=payload.release_id,
        message=(payload.message or "").strip() or None,
        status="pending",
    )
    db.add(req)
    db.commit()
    db.refresh(req)
    return _campaign_request_out(req, artist.name, release_title)


@router.get("/artist/me/campaign-requests", response_model=list[CampaignRequestOut])
def artist_list_my_campaign_requests(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[CampaignRequestOut]:
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        return []
    items = (
        db.query(CampaignRequest)
        .filter(CampaignRequest.artist_id == user.artist_id)
        .order_by(desc(CampaignRequest.created_at))
        .all()
    )
    return [_campaign_request_out(r, artist.name, r.release.title if r.release else None) for r in items]


@router.get("/admin/campaign-requests", response_model=list[CampaignRequestOut])
def admin_list_campaign_requests(
    status_filter: str | None = Query(None, description="pending | approved | rejected"),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[CampaignRequestOut]:
    require_admin(user)
    q = db.query(CampaignRequest).order_by(desc(CampaignRequest.created_at))
    if status_filter:
        q = q.filter(CampaignRequest.status == status_filter)
    items = q.all()
    out = []
    for r in items:
        artist = db.query(Artist).filter(Artist.id == r.artist_id).first()
        release_title = r.release.title if r.release else None
        out.append(_campaign_request_out(r, artist.name if artist else "", release_title))
    return out


@router.patch("/admin/campaign-requests/{request_id}", response_model=CampaignRequestOut)
def admin_update_campaign_request(
    request_id: int,
    payload: CampaignRequestUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> CampaignRequestOut:
    require_admin(user)
    req = db.query(CampaignRequest).options(
        joinedload(CampaignRequest.artist),
        joinedload(CampaignRequest.release),
    ).filter(CampaignRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Campaign request not found")
    old_status = req.status
    if payload.status is not None:
        req.status = payload.status
    if payload.admin_notes is not None:
        req.admin_notes = payload.admin_notes

    if req.status == "approved" and old_status != "approved":
        artist = req.artist or db.query(Artist).filter(Artist.id == req.artist_id).first()
        if artist:
            release_title = req.release.title if req.release else None
            _create_pending_release_token_and_send_approval_email(db, req, artist, release_title)

    db.commit()
    db.refresh(req)
    artist = db.query(Artist).filter(Artist.id == req.artist_id).first()
    release_title = req.release.title if req.release else None
    return _campaign_request_out(req, artist.name if artist else "", release_title)
