"""Admin artist management and public Groover registration."""

import hashlib
import html
import json
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import desc, func, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.api.artist_admin_helpers import (
    _artist_duplicate_email_detail,
    _artist_search_filter,
    _last_email_sent_map,
)
from app.api.deps import get_current_lm_user, require_permission
from app.api.mail_templates import (
    _artist_portal_url,
    _build_groover_invite_html,
    _get_groover_invite_subject_and_body,
    _get_portal_invite_subject_and_body,
    _get_update_profile_invite_subject_and_body,
)
from app.api.pending_release_helpers import _get_valid_artist_registration_token
from app.schemas.schemas import (
    _artist_extra_from_model,
    ArtistActivityLogOut,
    ArtistCreate,
    ArtistOut,
    ArtistPortalInviteBulkResponse,
    ArtistPortalInviteResponse,
    ArtistRegistrationCompleteRequest,
    ArtistRegistrationCompleteResponse,
    ArtistRegistrationFormInfo,
    ArtistSetPasswordRequest,
    ArtistUpdate,
    GrooverInviteRequest,
    GrooverInviteResponse,
    ReleaseOut,
    UserContext,
)
from app.core.config import settings
from app.db.session import get_db
from app.models.models import Artist, ArtistActivityLog, ArtistRegistrationToken, Release
from app.services.auth import hash_password
from app.services.email_service import send_email as send_email_service
router = APIRouter()


def _artist_registration_link(raw_token: str) -> str:
    portal_url = _artist_portal_url().rstrip("/")
    return f"{portal_url}/#/artist-registration?token={raw_token}"


def _generate_temporary_password(length: int = 12) -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@$%*"
    return "".join(secrets.choice(alphabet) for _ in range(length))

@router.get("/artists", response_model=list[ArtistOut])
def list_artists(
    include_inactive: bool = Query(False, description="Include inactive artists"),
    search: str | None = Query(None, description="Search by brand, name, email, or artist brands"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[ArtistOut]:
    require_permission(user, "artists:read")
    q = db.query(Artist).order_by(Artist.id)
    if not include_inactive:
        q = q.filter(Artist.is_active.is_(True))
    search_term = (search or "").strip()
    if search_term:
        q = _artist_search_filter(q, search_term, db)
    artists = q.offset(offset).limit(limit).all()
    artist_ids = [a.id for a in artists]
    last_email_map = _last_email_sent_map(db, artist_ids)
    out = []
    for a in artists:
        latest = (
            db.query(Release)
            .filter(or_(Release.artist_id == a.id, Release.artists.any(Artist.id == a.id)))
            .order_by(desc(Release.created_at))
            .first()
        )
        last_release = None
        if latest:
            last_release = {
                "title": latest.title,
                "created_at": latest.created_at.isoformat() if latest.created_at else None,
            }
        out.append(
            ArtistOut.from_artist(
                a,
                last_release=last_release,
                last_email_sent_at=last_email_map.get(a.id),
            )
        )
    return out


@router.get("/artists/{artist_id}", response_model=ArtistOut)
def get_artist(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ArtistOut:
    require_permission(user, "artists:read")
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    return ArtistOut.from_artist(artist)


@router.post("/artists", response_model=ArtistOut)
def create_artist(
    payload: ArtistCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ArtistOut:
    require_permission(user, "artists:write")
    extra = _artist_extra_from_model(payload)
    artist = Artist(
        name=payload.name,
        email=payload.email,
        notes=payload.notes,
        extra_json=json.dumps(extra) if extra else "{}",
    )
    db.add(artist)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        dup = db.query(Artist).filter(Artist.email == str(payload.email)).first()
        if dup:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=_artist_duplicate_email_detail(dup, editing_artist_id=None),
            ) from exc
        raise
    db.refresh(artist)
    return ArtistOut.from_artist(artist)


@router.patch("/artists/{artist_id}", response_model=ArtistOut)
@router.put("/artists/{artist_id}", response_model=ArtistOut)
def update_artist(
    artist_id: int,
    payload: ArtistUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ArtistOut:
    require_permission(user, "artists:write")
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if payload.name is not None:
        artist.name = payload.name
    if payload.email is not None:
        email_str = str(payload.email)
        existing = (
            db.query(Artist)
            .filter(Artist.email == email_str, Artist.id != artist_id)
            .first()
        )
        if existing:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=_artist_duplicate_email_detail(
                    existing, editing_artist_id=artist_id
                ),
            )
        artist.email = email_str
    if payload.notes is not None:
        artist.notes = payload.notes
    if payload.is_active is not None:
        artist.is_active = payload.is_active
    extra = _artist_extra_from_model(payload)
    if extra:
        try:
            current = json.loads(artist.extra_json or "{}")
            current.update(extra)
            artist.extra_json = json.dumps(current)
        except (json.JSONDecodeError, TypeError):
            artist.extra_json = json.dumps(extra)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        conflict_email = (
            str(payload.email) if payload.email is not None else artist.email
        )
        dup = (
            db.query(Artist)
            .filter(Artist.email == conflict_email, Artist.id != artist_id)
            .first()
        )
        if dup:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=_artist_duplicate_email_detail(
                    dup, editing_artist_id=artist_id
                ),
            ) from exc
        raise
    db.refresh(artist)
    return ArtistOut.from_artist(artist)


@router.patch("/admin/artists/{artist_id}/set-password")
def admin_set_artist_password(
    artist_id: int,
    payload: ArtistSetPasswordRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    """Set or reset an artist's portal password (artists table). Artist can then log in at artist portal."""
    require_permission(user, "artists:write")
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if not payload.password or len(payload.password) < 9:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 9 characters")
    artist.password_hash = hash_password(payload.password)
    db.commit()
    return {"ok": True, "message": "Password set. Artist can sign in at the artist portal."}


@router.post("/admin/artists/{artist_id}/send-portal-invite", response_model=ArtistPortalInviteResponse)
def admin_send_artist_portal_invite(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ArtistPortalInviteResponse:
    """Generate a temporary artist portal password and email portal login instructions."""
    require_permission(user, "artists:write")
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if not artist.is_active:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist is inactive")
    username = (artist.email or "").strip().lower()
    if not username:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist email is required")

    extra = _artist_extra_from_model(artist)
    display_name = (
        str(extra.get("full_name") or "").strip()
        or str(extra.get("artist_brand") or "").strip()
        or (artist.name or "").strip()
        or username
    )
    portal_url = _artist_portal_url()
    temporary_password = _generate_temporary_password()
    subject, body_text = _get_portal_invite_subject_and_body(
        display_name, portal_url, username, temporary_password
    )
    # Build HTML from plain body: escape and turn paragraphs into <p>, newlines into <br>
    body_html = "<p>" + html.escape(body_text).replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
    # Make portal URL clickable if it appears as plain text
    body_html = body_html.replace(
        html.escape(portal_url),
        f'<a href="{html.escape(portal_url)}">{html.escape(portal_url)}</a>',
    )

    artist.password_hash = hash_password(temporary_password)
    success, message = send_email_service(
        to_email=username,
        subject=subject,
        body_text=body_text,
        body_html=body_html,
    )
    if not success:
        db.rollback()
        if "limit" in message.lower():
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)

    db.add(
        ArtistActivityLog(
            artist_id=artist.id,
            activity_type="portal_invite_email",
            details=f"Portal invite sent to {username}",
        )
    )
    db.commit()
    return ArtistPortalInviteResponse(
        message="Artist portal invitation sent.",
        portal_url=portal_url,
        username=username,
    )


def _groover_base_name(payload: GrooverInviteRequest, email: str) -> str:
    return (
        (payload.artist_name or "").strip()
        or (payload.full_name or "").strip()
        or email.split("@")[0]
    )


def _groover_create_artist_from_payload(db: Session, payload: GrooverInviteRequest, email: str) -> Artist:
    base_name = _groover_base_name(payload, email)
    extra = {
        "artist_brand": (payload.artist_name or "").strip() or base_name,
        "full_name": (payload.full_name or "").strip(),
        "source_row": "groover",
    }
    artist = Artist(
        name=base_name[:120],
        email=email,
        notes=(payload.notes or "").strip(),
        extra_json=json.dumps({k: v for k, v in extra.items() if v}),
    )
    db.add(artist)
    db.flush()
    return artist


def _groover_update_existing_artist_from_payload(artist: Artist, payload: GrooverInviteRequest) -> None:
    extra = _artist_extra_from_model(artist)
    changed = False
    artist_brand = (payload.artist_name or "").strip()
    full_name = (payload.full_name or "").strip()
    if artist_brand and not str(extra.get("artist_brand") or "").strip():
        extra["artist_brand"] = artist_brand
        changed = True
    if full_name and not str(extra.get("full_name") or "").strip():
        extra["full_name"] = full_name
        changed = True
    if "source_row" not in extra:
        extra["source_row"] = "groover"
        changed = True
    if changed:
        artist.extra_json = json.dumps(extra)

    groover_note = (payload.notes or "").strip()
    if groover_note:
        notes_prefix = (artist.notes or "").strip()
        if groover_note not in notes_prefix:
            artist.notes = f"{notes_prefix}\n\n{groover_note}".strip()


def _prepare_groover_artist(db: Session, payload: GrooverInviteRequest, email: str) -> tuple[Artist, bool]:
    artist = db.query(Artist).filter(func.lower(Artist.email) == email).first()
    if not artist:
        return _groover_create_artist_from_payload(db, payload, email), True
    _groover_update_existing_artist_from_payload(artist, payload)
    return artist, False


def _create_groover_registration_token(db: Session, artist_id: int, email: str) -> str:
    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    expires_at = datetime.now(timezone.utc) + timedelta(days=14)
    token_row = ArtistRegistrationToken(
        artist_id=artist_id,
        token_hash=token_hash,
        email=email,
        source="groover",
        expires_at=expires_at,
    )
    db.add(token_row)
    return raw_token


def _groover_invite_email_payload(
    payload: GrooverInviteRequest, artist: Artist, email: str, raw_token: str
) -> tuple[str, str, str, str]:
    extra = _artist_extra_from_model(artist)
    display_name = (
        (payload.full_name or "").strip()
        or str(extra.get("full_name") or "").strip()
        or (payload.artist_name or "").strip()
        or str(extra.get("artist_brand") or "").strip()
        or (artist.name or "").strip()
        or email
    )
    portal_url = _artist_portal_url()
    registration_url = _artist_registration_link(raw_token)
    subject, body_text = _get_groover_invite_subject_and_body(display_name, registration_url, portal_url)
    body_html = _build_groover_invite_html(
        body_text=body_text,
        registration_url=registration_url,
        portal_url=portal_url,
    )
    return subject, body_text, body_html, registration_url


@router.post("/admin/artists/send-groover-invite", response_model=GrooverInviteResponse)
def admin_send_groover_invite(
    payload: GrooverInviteRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> GrooverInviteResponse:
    """Create or reuse an artist and send a Groover follow-up email with registration form link."""
    require_permission(user, "artists:write")
    email = (payload.email or "").strip().lower()
    if not email:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email is required")

    artist, created_artist = _prepare_groover_artist(db, payload, email)
    raw_token = _create_groover_registration_token(db, artist.id, email)
    subject, body_text, body_html, registration_url = _groover_invite_email_payload(
        payload, artist, email, raw_token
    )

    success, message = send_email_service(
        to_email=email,
        subject=subject,
        body_text=body_text,
        body_html=body_html,
    )
    if not success:
        db.rollback()
        if "limit" in message.lower():
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)

    db.add(
        ArtistActivityLog(
            artist_id=artist.id,
            activity_type="groover_invite_email",
            details=f"Groover invite sent to {email}",
        )
    )
    db.commit()
    return GrooverInviteResponse(
        message="Groover invite sent.",
        artist_id=artist.id,
        email=email,
        registration_url=registration_url,
        created_artist=created_artist,
    )


@router.post("/admin/artists/send-portal-invite-all", response_model=ArtistPortalInviteBulkResponse)
def admin_send_portal_invite_all(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ArtistPortalInviteBulkResponse:
    """Send portal access email to all active artists that have an email address."""
    require_permission(user, "artists:write")
    artists = (
        db.query(Artist)
        .filter(Artist.is_active.is_(True))
        .filter(Artist.email.isnot(None), Artist.email != "")
        .order_by(Artist.id)
        .all()
    )
    sent = 0
    errors: list[dict] = []
    for artist in artists:
        username = (artist.email or "").strip().lower()
        if not username:
            continue
        extra = _artist_extra_from_model(artist)
        display_name = (
            str(extra.get("full_name") or "").strip()
            or str(extra.get("artist_brand") or "").strip()
            or (artist.name or "").strip()
            or username
        )
        portal_url = _artist_portal_url()
        temporary_password = _generate_temporary_password()
        subject, body_text = _get_portal_invite_subject_and_body(
            display_name, portal_url, username, temporary_password
        )
        body_html = "<p>" + html.escape(body_text).replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
        body_html = body_html.replace(
            html.escape(portal_url),
            f'<a href="{html.escape(portal_url)}">{html.escape(portal_url)}</a>',
        )
        artist.password_hash = hash_password(temporary_password)
        success, message = send_email_service(
            to_email=username,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )
        if not success:
            errors.append({"artist_id": artist.id, "email": username, "detail": message})
            db.rollback()
            continue
        db.add(
            ArtistActivityLog(
                artist_id=artist.id,
                activity_type="portal_invite_email",
                details=f"Portal invite sent to {username}",
            )
        )
        db.commit()
        sent += 1
    return ArtistPortalInviteBulkResponse(
        sent=sent,
        failed=len(errors),
        errors=[ArtistPortalInviteBulkError(**e) for e in errors],
    )


@router.post("/admin/artists/{artist_id}/send-update-profile-invite", response_model=ArtistPortalInviteResponse)
def admin_send_artist_update_profile_invite(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ArtistPortalInviteResponse:
    """Email artist inviting them to update their portal page and see their releases (no password change unless not set)."""
    require_permission(user, "artists:write")
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if not artist.is_active:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist is inactive")
    username = (artist.email or "").strip().lower()
    if not username:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist email is required")

    extra = _artist_extra_from_model(artist)
    display_name = (
        str(extra.get("full_name") or "").strip()
        or str(extra.get("artist_brand") or "").strip()
        or (artist.name or "").strip()
        or username
    )
    portal_url = _artist_portal_url()
    temporary_password: str | None = None
    if not artist.password_hash:
        temporary_password = _generate_temporary_password()
        artist.password_hash = hash_password(temporary_password)
    subject, body_text = _get_update_profile_invite_subject_and_body(
        display_name,
        portal_url,
        username,
        temporary_password,
    )
    body_html = "<p>" + html.escape(body_text).replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
    body_html = body_html.replace(
        html.escape(portal_url),
        f'<a href="{html.escape(portal_url)}">{html.escape(portal_url)}</a>',
    )
    success, message = send_email_service(
        to_email=username,
        subject=subject,
        body_text=body_text,
        body_html=body_html,
    )
    if not success:
        db.rollback()
        if "limit" in message.lower():
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)
    db.add(
        ArtistActivityLog(
            artist_id=artist.id,
            activity_type="update_profile_invite_email",
            details=f"Update profile invite sent to {username}",
        )
    )
    db.commit()
    return ArtistPortalInviteResponse(
        message="Update profile invitation sent.",
        portal_url=portal_url,
        username=username,
    )


@router.get("/artists/{artist_id}/releases", response_model=list[ReleaseOut])
def list_artist_releases(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[ReleaseOut]:
    require_permission(user, "releases:read")
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    releases = (
        db.query(Release)
        .options(
            joinedload(Release.artists),
            joinedload(Release.artist),
            joinedload(Release.link_candidates),
            joinedload(Release.link_scan_runs),
        )
        .filter(or_(Release.artist_id == artist_id, Release.artists.any(Artist.id == artist_id)))
        .order_by(desc(Release.created_at))
        .all()
    )
    return [ReleaseOut.from_release(r) for r in releases]


@router.get("/admin/artists/{artist_id}/activity", response_model=list[ArtistActivityLogOut])
def list_artist_activity(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[ArtistActivityLogOut]:
    """List activity log for an artist (reminder emails, etc.) for the Logs tab."""
    require_permission(user, "artists:read")
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    logs = (
        db.query(ArtistActivityLog)
        .filter(ArtistActivityLog.artist_id == artist_id)
        .order_by(desc(ArtistActivityLog.created_at))
        .all()
    )
    return [
        ArtistActivityLogOut(
            id=log.id,
            activity_type=log.activity_type,
            details=log.details,
            created_at=log.created_at,
        )
        for log in logs
    ]


@router.delete("/artists/{artist_id}")
def delete_artist(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    require_permission(user, "artists:write")
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    try:
        # Unlink any users from this artist so we can delete it
        db.execute(update(User).where(User.artist_id == artist_id).values(artist_id=None))
        # Clear artist_id on campaigns so we can delete the artist
        db.execute(update(Campaign).where(Campaign.artist_id == artist_id).values(artist_id=None))
        # Delete dependent records first (no FK cascade on artist_id)
        db.query(AutomationTask).filter(AutomationTask.artist_id == artist_id).delete(synchronize_session=False)
        db.execute(release_artists_table.delete().where(release_artists_table.c.artist_id == artist_id))
        db.query(Release).filter(Release.artist_id == artist_id).delete(synchronize_session=False)
        db.query(SocialConnection).filter(SocialConnection.artist_id == artist_id).delete(synchronize_session=False)
        db.delete(artist)
        db.commit()
    except SQLAlchemyError as e:
        db.rollback()
        logging.exception("Delete artist %s failed", artist_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Delete failed: {e!s}",
        ) from e
    return {"ok": True}


@router.get("/public/artist-registration", response_model=ArtistRegistrationFormInfo)
def public_artist_registration_info(
    token: str = Query(..., description="One-time token from Groover invite email"),
    db: Session = Depends(get_db),
) -> ArtistRegistrationFormInfo:
    """Validate registration token and return prefilled artist info."""
    row = _get_valid_artist_registration_token(db, token)
    artist = db.query(Artist).filter(Artist.id == row.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    extra = _artist_extra_from_model(artist)
    return ArtistRegistrationFormInfo(
        artist_id=artist.id,
        email=row.email,
        artist_name=str(extra.get("artist_brand") or artist.name or "").strip(),
        full_name=str(extra.get("full_name") or "").strip(),
        notes=(artist.notes or "").strip(),
        expires_at=row.expires_at,
    )


@router.post("/public/artist-registration", response_model=ArtistRegistrationCompleteResponse)
def public_artist_registration_submit(
    payload: ArtistRegistrationCompleteRequest,
    db: Session = Depends(get_db),
) -> ArtistRegistrationCompleteResponse:
    """Complete artist registration from email invite and enable portal sign-in."""
    row = _get_valid_artist_registration_token(db, payload.token)
    artist = db.query(Artist).filter(Artist.id == row.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if not payload.artist_name.strip():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist name is required")
    if not payload.password or len(payload.password) < 9:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 12 characters")

    artist.name = payload.artist_name.strip()[:120]
    artist.notes = (payload.notes or "").strip()
    current = _artist_extra_from_model(artist)
    current.update(
        {
            "artist_brand": payload.artist_name.strip(),
            "full_name": (payload.full_name or "").strip(),
            "website": (payload.website or "").strip(),
            "soundcloud": (payload.soundcloud or "").strip(),
            "instagram": (payload.instagram or "").strip(),
            "spotify": (payload.spotify or "").strip(),
            "apple_music": (payload.apple_music or "").strip(),
            "youtube": (payload.youtube or "").strip(),
            "tiktok": (payload.tiktok or "").strip(),
            "facebook": (payload.facebook or "").strip(),
            "linktree": (payload.linktree or "").strip(),
            "source_row": current.get("source_row") or "groover",
        }
    )
    artist.extra_json = json.dumps({k: v for k, v in current.items() if v not in (None, "")})
    artist.password_hash = hash_password(payload.password)
    artist.last_profile_updated_at = datetime.now(timezone.utc)
    row.used_at = datetime.now(timezone.utc)
    db.add(
        ArtistActivityLog(
            artist_id=artist.id,
            activity_type="groover_registration_completed",
            details=f"Registration completed for {artist.email}",
        )
    )
    db.commit()
    return ArtistRegistrationCompleteResponse(
        message="Registration completed. You can now sign in to the artist portal.",
        portal_url=_artist_portal_url(),
    )


# ---- Social and Connectors routes removed (rebuild from scratch) ----
# Placeholder so next section comment is not orphaned











