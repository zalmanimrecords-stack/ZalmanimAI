"""Artist portal (authenticated artist) routes."""

import json
import os
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session, joinedload

from app.api.deps import get_current_user, require_artist
from app.api.pending_release_helpers import (
    _get_valid_pending_release_token,
    _notify_pending_release_artist,
    _pending_release_upload_path_from_public_url,
    _save_pending_release_data,
    _serialize_pending_release_detail,
)
from app.api.upload_helpers import _read_upload_bytes
from app.core.config import settings
from app.db.session import get_db
from app.models.models import Artist, ArtistMedia, DemoSubmission, PendingRelease, PendingReleaseComment, Release
from app.schemas.schemas import (
    _artist_extra_from_model,
    ArtistChangePasswordRequest,
    ArtistDashboard,
    ArtistMediaListResponse,
    ArtistMediaOut,
    ArtistOut,
    ArtistSelfUpdate,
    DemoSubmissionCreate,
    DemoSubmissionOut,
    PendingReleaseCommentCreate,
    PendingReleaseDetailOut,
    PendingReleaseFormInfo,
    PendingReleaseNotificationSettingsUpdate,
    PendingReleaseOut,
    PendingReleaseReferenceUploadOut,
    PendingReleaseSelectImageRequest,
    PendingReleaseSubmit,
    ReleaseOut,
    UserContext,
)
from app.services.auth import hash_password, verify_password

router = APIRouter()

@router.get("/artist/me/dashboard", response_model=ArtistDashboard)
def artist_dashboard(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistDashboard:
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")

    releases = (
        db.query(Release)
        .options(joinedload(Release.artists))
        .filter(or_(Release.artist_id == artist.id, Release.artists.any(Artist.id == artist.id)))
        .order_by(desc(Release.created_at))
        .all()
    )
    tasks = (
        db.query(AutomationTask)
        .filter(AutomationTask.artist_id == artist.id)
        .order_by(desc(AutomationTask.created_at))
        .all()
    )
    pending_releases = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.artist_id == artist.id, PendingRelease.status != "archived")
        .order_by(desc(PendingRelease.created_at))
        .all()
    )

    return ArtistDashboard(
        artist=ArtistOut.from_artist(artist),
        releases=[ReleaseOut.from_release(item) for item in releases],
        tasks=[TaskOut.model_validate(item) for item in tasks],
        pending_releases=[_serialize_pending_release_detail(item) for item in pending_releases],
    )


@router.post("/artist/me/releases/upload", response_model=ReleaseOut)
def upload_release(
    title: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> Release:
    require_artist(user)

    os.makedirs(settings.upload_dir, exist_ok=True)
    extension = os.path.splitext(file.filename or "")[1]
    if not extension:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Release file must have an extension")
    filename = f"{uuid.uuid4().hex}{extension}"
    path = os.path.join(settings.upload_dir, filename)
    content = _read_upload_bytes(file, max_bytes=MAX_RELEASE_UPLOAD_BYTES, description="Release file")

    with open(path, "wb") as out:
        out.write(content)

    release = Release(artist_id=user.artist_id, title=title, status="submitted", file_path=path)
    db.add(release)
    db.flush()
    artist = db.get(Artist, user.artist_id)
    if artist:
        release.artists.append(artist)

    db.add(
        AutomationTask(
            artist_id=user.artist_id,
            title=f"Review submission: {title}",
            status="queued",
            details="System queued internal review and release preparation.",
        )
    )

    db.commit()
    db.refresh(release)
    return ReleaseOut.from_release(release)


@router.get("/artist/me", response_model=ArtistOut)
def artist_get_me(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistOut:
    """Get current artist profile (artist role only)."""
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    return ArtistOut.from_artist(artist)


@router.patch("/artist/me", response_model=ArtistOut)
def artist_patch_me(
    payload: ArtistSelfUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistOut:
    """Update current artist profile (artist role only; name, notes, extra fields)."""
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if payload.name is not None:
        artist.name = payload.name
    if payload.notes is not None:
        artist.notes = payload.notes
    if payload.profile_image_media_id is not None:
        media = db.query(ArtistMedia).filter(
            ArtistMedia.id == payload.profile_image_media_id,
            ArtistMedia.artist_id == user.artist_id,
        ).first()
        if not media:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Profile image: file not found or not yours")
    if payload.logo_media_id is not None:
        media = db.query(ArtistMedia).filter(
            ArtistMedia.id == payload.logo_media_id,
            ArtistMedia.artist_id == user.artist_id,
        ).first()
        if not media:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Logo: file not found or not yours")
    if payload.minisite_gallery_media_ids is not None:
        gallery_ids = [item for item in payload.minisite_gallery_media_ids if isinstance(item, int) and item > 0]
        if gallery_ids:
            owned_ids = {
                media_id
                for (media_id,) in db.query(ArtistMedia.id)
                .filter(ArtistMedia.artist_id == user.artist_id, ArtistMedia.id.in_(gallery_ids))
                .all()
            }
            missing_ids = sorted(set(gallery_ids) - owned_ids)
            if missing_ids:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Gallery images not found or not yours: {', '.join(str(item) for item in missing_ids)}",
                )
    extra = _artist_extra_from_model(payload)
    if extra:
        try:
            current = json.loads(artist.extra_json or "{}")
            current.update(extra)
            artist.extra_json = json.dumps(current)
        except (json.JSONDecodeError, TypeError):
            artist.extra_json = json.dumps(extra)
    artist.last_profile_updated_at = datetime.now(timezone.utc)
    db.add(
        ArtistActivityLog(
            artist_id=artist.id,
            activity_type="profile_updated",
            details="Artist updated their portal profile",
        )
    )
    db.commit()
    db.refresh(artist)
    return ArtistOut.from_artist(artist)


@router.patch("/artist/me/password")
def artist_change_password(
    payload: ArtistChangePasswordRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    """Change current artist's portal password (must know current password)."""
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if not artist.password_hash:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password not set. Contact the label.")
    if not verify_password(payload.current_password, artist.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Current password is incorrect")
    if not payload.new_password or len(payload.new_password) < 12:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="New password must be at least 12 characters")
    artist.password_hash = hash_password(payload.new_password)
    db.commit()
    return {"ok": True, "message": "Password updated."}


@router.get("/artist/me/demos", response_model=list[DemoSubmissionOut])
def artist_list_my_demos(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[DemoSubmissionOut]:
    """List demo submissions for the current artist."""
    require_artist(user)
    items = (
        db.query(DemoSubmission)
        .filter(DemoSubmission.artist_id == user.artist_id)
        .order_by(desc(DemoSubmission.created_at))
        .all()
    )
    return [_serialize_demo_submission(item) for item in items]


@router.post("/artist/me/demos", response_model=DemoSubmissionOut)
def artist_submit_demo(
    track_name: str = Form(""),
    musical_style: str = Form(""),
    message: str = Form(""),
    file: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> DemoSubmissionOut:
    """Submit a demo from the artist portal (track name, musical style, optional message + optional file)."""
    require_artist(user)
    track_name_clean = track_name.strip()
    musical_style_clean = musical_style.strip()
    if not track_name_clean:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Track name is required")
    if not musical_style_clean:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Musical style is required")

    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    email = user.email or artist.email

    demo_file_path: str | None = None
    if file and file.filename:
        demo_uploads_dir = os.path.join(settings.upload_dir, "demo_uploads")
        os.makedirs(demo_uploads_dir, exist_ok=True)
        ext = os.path.splitext(file.filename)[1]
        if ext.lower() not in {".mp3"}:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only MP3 files are allowed for demos")
        stored_name = f"{uuid.uuid4().hex}{ext}"
        path = os.path.join(demo_uploads_dir, stored_name)
        content = _read_upload_bytes(file, max_bytes=MAX_ARTIST_DEMO_UPLOAD_BYTES, description="Demo file")
        with open(path, "wb") as out:
            out.write(content)
        demo_file_path = path

    fields = {"track_name": track_name_clean, "musical_style": musical_style_clean}
    if demo_file_path:
        fields["demo_file_path"] = demo_file_path
    item = DemoSubmission(
        artist_name=artist.name,
        email=email,
        consent_to_emails=False,
        consent_at=None,
        message=message.strip() or None,
        links_json="[]",
        fields_json=json.dumps(fields),
        source="artist_portal",
        source_site_url=None,
        status="demo",
        artist_id=artist.id,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return _serialize_demo_submission(item)


@router.get("/artist/me/demos/{demo_id}/download", response_model=None)
def artist_download_demo_file(
    demo_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> FileResponse | Response:
    """Download the attached file for a demo submission (only own demos)."""
    require_artist(user)
    item = (
        db.query(DemoSubmission)
        .filter(DemoSubmission.id == demo_id, DemoSubmission.artist_id == user.artist_id)
        .first()
    )
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo not found")
    try:
        fields = json.loads(item.fields_json or "{}")
        path = fields.get("demo_file_path")
    except (json.JSONDecodeError, TypeError):
        path = None
    if not path or not os.path.isfile(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No file attached")
    return FileResponse(path, filename=os.path.basename(path))


ARTIST_MEDIA_QUOTA_BYTES = 50 * 1024 * 1024  # 50 MiB per artist


def _artist_media_dir() -> str:
    return os.path.join(settings.upload_dir, "artist_media")


def _artist_media_used_bytes(db: Session, artist_id: int) -> int:
    r = db.query(func.coalesce(func.sum(ArtistMedia.size_bytes), 0)).filter(
        ArtistMedia.artist_id == artist_id
    ).scalar()
    return int(r) if r is not None else 0


@router.get("/artist/me/media", response_model=ArtistMediaListResponse)
def artist_list_my_media(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistMediaListResponse:
    """List current artist's media folder files and quota."""
    require_artist(user)
    items = (
        db.query(ArtistMedia)
        .filter(ArtistMedia.artist_id == user.artist_id)
        .order_by(desc(ArtistMedia.created_at))
        .all()
    )
    used = _artist_media_used_bytes(db, user.artist_id)
    return ArtistMediaListResponse(
        items=[
            ArtistMediaOut(
                id=m.id,
                artist_id=m.artist_id,
                filename=m.filename,
                content_type=m.content_type,
                size_bytes=m.size_bytes,
                created_at=m.created_at,
            )
            for m in items
        ],
        used_bytes=used,
        quota_bytes=ARTIST_MEDIA_QUOTA_BYTES,
    )


@router.post("/artist/me/media", response_model=ArtistMediaOut)
def artist_upload_media(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistMediaOut:
    """Upload a file to the artist's media folder (50MB quota per artist)."""
    require_artist(user)
    if not file.filename or not file.filename.strip():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Filename required")
    content = _read_upload_bytes(file, max_bytes=MAX_ARTIST_MEDIA_UPLOAD_BYTES, description="Media file")
    size = len(content)
    used = _artist_media_used_bytes(db, user.artist_id)
    if used + size > ARTIST_MEDIA_QUOTA_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Media quota exceeded. Used {used // (1024*1024)}MB of 50MB. Free { (ARTIST_MEDIA_QUOTA_BYTES - used) // (1024*1024) }MB.",
        )
    artist_media_root = _artist_media_dir()
    per_artist_dir = os.path.join(artist_media_root, str(user.artist_id))
    os.makedirs(per_artist_dir, exist_ok=True)
    safe_name = os.path.basename(file.filename)
    stored_name = f"{uuid.uuid4().hex}_{safe_name}"
    path = os.path.join(per_artist_dir, stored_name)
    content_type = file.content_type
    with open(path, "wb") as out:
        out.write(content)
    media = ArtistMedia(
        artist_id=user.artist_id,
        filename=safe_name,
        stored_path=path,
        content_type=content_type,
        size_bytes=size,
    )
    db.add(media)
    db.commit()
    db.refresh(media)
    return ArtistMediaOut(
        id=media.id,
        artist_id=media.artist_id,
        filename=media.filename,
        content_type=media.content_type,
        size_bytes=media.size_bytes,
        created_at=media.created_at,
    )


@router.get("/artist/me/media/{media_id}", response_model=None)
def artist_download_media(
    media_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> FileResponse:
    """Download a file from the artist's media folder."""
    require_artist(user)
    media = (
        db.query(ArtistMedia)
        .filter(ArtistMedia.id == media_id, ArtistMedia.artist_id == user.artist_id)
        .first()
    )
    if not media or not os.path.isfile(media.stored_path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    return FileResponse(media.stored_path, filename=media.filename, media_type=media.content_type)


@router.delete("/artist/me/media/{media_id}")
def artist_delete_media(
    media_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    """Delete a file from the artist's media folder."""
    require_artist(user)
    media = (
        db.query(ArtistMedia)
        .filter(ArtistMedia.id == media_id, ArtistMedia.artist_id == user.artist_id)
        .first()
    )
    if not media:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    if os.path.isfile(media.stored_path):
        try:
            os.remove(media.stored_path)
        except OSError:
            pass
    db.delete(media)
    db.commit()
    return {"ok": True}


def _create_pending_release_reminder_token(
    db: Session,
    *,
    pending_release: PendingRelease,
    artist: Artist | None,
    expires_in_days: int,
) -> tuple[str, datetime]:
    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    expires_at = datetime.now(timezone.utc) + timedelta(days=expires_in_days)
    token_row = PendingReleaseToken(
        token_hash=token_hash,
        campaign_request_id=pending_release.campaign_request_id,
        pending_release_id=pending_release.id,
        artist_id=artist.id if artist else pending_release.artist_id,
        expires_at=expires_at,
    )
    db.add(token_row)
    db.flush()
    return _pending_release_form_link(raw_token), expires_at


@router.get("/public/pending-release-form", response_model=PendingReleaseFormInfo)
def public_pending_release_form_validate(
    token: str = Query(..., description="One-time token from approval email"),
    db: Session = Depends(get_db),
) -> PendingReleaseFormInfo:
    """Validate token and return artist/release names for the pending-release form (no auth)."""
    row = _get_valid_pending_release_token(db, token)
    artist = db.query(Artist).filter(Artist.id == row.artist_id).first()
    pending_release = _resolve_pending_release_from_token(db, row)
    release_title = None
    if row.campaign_request_id:
        cr = db.query(CampaignRequest).filter(CampaignRequest.id == row.campaign_request_id).first()
        if cr and cr.release_id:
            rel = db.query(Release).filter(Release.id == cr.release_id).first()
            if rel:
                release_title = rel.title
    if pending_release and pending_release.release_title:
        release_title = pending_release.release_title
    return PendingReleaseFormInfo(
        artist_name=(pending_release.artist_name if pending_release else None) or (artist.name if artist else "Artist"),
        artist_email=(pending_release.artist_email if pending_release else None) or (artist.email if artist else ""),
        artist_data=_safe_json_dict(pending_release.artist_data_json) if pending_release else {},
        release_title=release_title or "Your release",
        release_data=_safe_json_dict(pending_release.release_data_json) if pending_release else {},
        expires_at=row.expires_at,
    )


@router.post("/public/pending-release-submit", response_model=PendingReleaseOut)
def public_pending_release_submit(
    payload: PendingReleaseSubmit,
    db: Session = Depends(get_db),
) -> PendingReleaseOut:
    """Submit artist + track details using the token (no auth). Updates existing pending release when available."""
    row = _get_valid_pending_release_token(db, payload.token)
    pr = _resolve_pending_release_from_token(db, row)
    if pr is None:
        pr = PendingRelease(
            campaign_request_id=row.campaign_request_id,
            artist_id=row.artist_id,
            artist_name="Artist",
            artist_email="",
            artist_data_json="{}",
            release_title="Untitled",
            release_data_json="{}",
            status="pending",
        )
        db.add(pr)
        db.flush()
        if getattr(row, "pending_release_id", None) is None:
            row.pending_release_id = pr.id
    pr.artist_name = (payload.artist_name or "").strip() or "Artist"
    pr.artist_email = payload.artist_email.strip().lower()
    pr.artist_data_json = json.dumps(payload.artist_data if isinstance(payload.artist_data, dict) else {})
    pr.release_title = (payload.release_title or "").strip() or "Untitled"
    pr.release_data_json = json.dumps(payload.release_data if isinstance(payload.release_data, dict) else {})
    pr.status = "pending"
    _create_pending_release_inbox_message(
        db,
        pending_release=pr,
        message_prefix="Pending Release form submitted by the artist.",
    )
    db.commit()
    db.refresh(pr)
    return _serialize_pending_release(pr)


@router.post("/public/pending-release-reference-image", response_model=PendingReleaseReferenceUploadOut)
def public_upload_pending_release_reference_image(
    request: Request,
    token: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
) -> PendingReleaseReferenceUploadOut:
    """Upload a cover reference image using a valid pending-release token."""
    _get_valid_pending_release_token(db, token)
    filename = (file.filename or "").strip()
    ext = os.path.splitext(filename)[1].lower()
    if ext not in _ALLOWED_PENDING_RELEASE_IMAGE_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only image files are allowed (jpg, jpeg, png, gif, webp).",
        )
    if not (file.content_type or "").lower().startswith("image/"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only image content types are allowed.")
    reference_dir = os.path.join(settings.upload_dir, "pending_release_references")
    os.makedirs(reference_dir, exist_ok=True)
    stored_name = f"{uuid.uuid4().hex}{ext}"
    path = os.path.join(reference_dir, stored_name)
    content = _read_upload_bytes(file, max_bytes=MAX_PENDING_RELEASE_IMAGE_BYTES, description="Reference image")
    with open(path, "wb") as out:
        out.write(content)
    return PendingReleaseReferenceUploadOut(
        url=str(request.url_for("public_pending_release_reference_image_file", filename=stored_name)),
        filename=filename or stored_name,
    )


@router.get(
    "/public/pending-release-reference-image/{filename}",
    response_class=FileResponse,
    name="public_pending_release_reference_image_file",
)
def public_pending_release_reference_image_file(filename: str) -> FileResponse:
    path = os.path.join(settings.upload_dir, "pending_release_references", filename)
    if not os.path.isfile(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")
    media_types = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".gif": "image/gif",
        ".webp": "image/webp",
    }
    return FileResponse(path, media_type=media_types.get(os.path.splitext(filename)[1].lower(), "application/octet-stream"))


@router.get(
    "/public/pending-release-label-image/{filename}",
    response_class=FileResponse,
    name="public_pending_release_label_image_file",
)
def public_pending_release_label_image_file(filename: str) -> FileResponse:
    path = os.path.join(settings.upload_dir, "pending_release_label_images", filename)
    if not os.path.isfile(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")
    media_types = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".gif": "image/gif",
        ".webp": "image/webp",
    }
    return FileResponse(path, media_type=media_types.get(os.path.splitext(filename)[1].lower(), "application/octet-stream"))


@router.get("/artist/me/pending-releases/{pending_release_id}", response_model=PendingReleaseDetailOut)
def artist_get_pending_release_detail(
    pending_release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> PendingReleaseDetailOut:
    require_artist(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(
            PendingRelease.id == pending_release_id,
            PendingRelease.artist_id == user.artist_id,
        )
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    return _serialize_pending_release_detail(pending_release)


@router.post("/artist/me/pending-releases/{pending_release_id}/comments", response_model=PendingReleaseDetailOut)
def artist_add_pending_release_comment(
    pending_release_id: int,
    payload: PendingReleaseCommentCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> PendingReleaseDetailOut:
    require_artist(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(
            PendingRelease.id == pending_release_id,
            PendingRelease.artist_id == user.artist_id,
        )
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    body = (payload.body or "").strip()
    if not body:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Comment body is required")
    db.add(PendingReleaseComment(pending_release_id=pending_release.id, sender="artist", body=body))
    db.commit()
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Pending release not found after comment")
    return _serialize_pending_release_detail(pending_release)


@router.post("/artist/me/pending-releases/{pending_release_id}/select-image", response_model=PendingReleaseDetailOut)
def artist_select_pending_release_image(
    pending_release_id: int,
    payload: PendingReleaseSelectImageRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> PendingReleaseDetailOut:
    require_artist(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(
            PendingRelease.id == pending_release_id,
            PendingRelease.artist_id == user.artist_id,
        )
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    release_data = _safe_json_dict(pending_release.release_data_json)
    image_ids = {item.id for item in _pending_release_image_options(release_data)}
    if payload.image_id not in image_ids:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Image option not found")
    release_data["selected_image_id"] = payload.image_id
    _save_pending_release_data(pending_release, release_data)
    db.commit()
    db.refresh(pending_release)
    return _serialize_pending_release_detail(pending_release)


@router.patch("/artist/me/pending-releases/{pending_release_id}/notifications", response_model=PendingReleaseDetailOut)
def artist_update_pending_release_notification_settings(
    pending_release_id: int,
    payload: PendingReleaseNotificationSettingsUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> PendingReleaseDetailOut:
    require_artist(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(
            PendingRelease.id == pending_release_id,
            PendingRelease.artist_id == user.artist_id,
        )
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    release_data = _safe_json_dict(pending_release.release_data_json)
    release_data["notifications_muted"] = payload.notifications_muted
    _save_pending_release_data(pending_release, release_data)
    db.commit()
    db.refresh(pending_release)
    return _serialize_pending_release_detail(pending_release)


