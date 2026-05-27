"""Admin pending-release HTTP routes (extracted from routes.py)."""

import logging
import os
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile, status
from sqlalchemy.orm import Session, joinedload

from app.api.deps import get_current_lm_user, require_admin
from app.api.mail_templates import _safe_json_dict
from app.api.pending_release_helpers import (
    _normalize_public_image_url_path_for_match,
    _notify_pending_release_artist,
    _pending_release_upload_path_from_public_url,
    _save_pending_release_data,
    _serialize_pending_release_detail,
    create_pending_release_reminder_token,
)
from app.api.upload_helpers import (
    _bytes_to_jpg_3000_square,
    _pending_release_label_image_base_name,
    _read_upload_bytes,
    _unique_filename,
)
from app.core.config import settings
from app.db.session import get_db
from app.models.models import Artist, ArtistActivityLog, PendingRelease
from app.schemas.schemas import (
    PendingReleaseActionResponse,
    PendingReleaseCommentCreate,
    PendingReleaseDetailOut,
    PendingReleaseReminderResponse,
    PendingReleaseRemoveStoredImageBody,
    UserContext,
)
from app.services.email_service import send_email as send_email_service
from app.services.pending_release_service import (
    add_label_comment,
    archive_pending_release,
    delete_pending_release,
    get_pending_release_detail,
    list_pending_releases_for_admin,
)

router = APIRouter()

_ALLOWED_PENDING_RELEASE_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}
MAX_PENDING_RELEASE_IMAGE_BYTES = 10 * 1024 * 1024


@router.get("/admin/pending-releases", response_model=list[PendingReleaseDetailOut])
def admin_list_pending_releases(
    status_filter: str | None = Query(None, description="pending | processed | archived"),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[PendingReleaseDetailOut]:
    """List pending-for-release items (tracks with full details submitted, waiting for treatment)."""
    require_admin(user)
    return list_pending_releases_for_admin(
        db,
        status_filter=status_filter,
        limit=limit,
        offset=offset,
    )


@router.get("/admin/pending-releases/{pending_release_id}", response_model=PendingReleaseDetailOut)
def admin_get_pending_release_detail(
    pending_release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseDetailOut:
    require_admin(user)
    detail = get_pending_release_detail(db, pending_release_id)
    if not detail:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    return detail


@router.post("/admin/pending-releases/{pending_release_id}/comments", response_model=PendingReleaseDetailOut)
def admin_add_pending_release_comment(
    pending_release_id: int,
    payload: PendingReleaseCommentCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseDetailOut:
    require_admin(user)
    body = (payload.body or "").strip()
    if not body:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Comment body is required")
    pending_release = add_label_comment(db, pending_release_id, body)
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    db.commit()
    detail = get_pending_release_detail(db, pending_release_id)
    if not detail:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Pending release not found after comment")
    return detail


@router.post("/admin/pending-releases/{pending_release_id}/images", response_model=PendingReleaseDetailOut)
def admin_upload_pending_release_image(
    request: Request,
    pending_release_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseDetailOut:
    require_admin(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    filename = (file.filename or "").strip()
    ext = os.path.splitext(filename)[1].lower()
    if ext not in _ALLOWED_PENDING_RELEASE_IMAGE_EXTENSIONS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only image files are allowed.")
    if not (file.content_type or "").lower().startswith("image/"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only image content types are allowed.")
    image_dir = os.path.join(settings.upload_dir, "pending_release_label_images")
    os.makedirs(image_dir, exist_ok=True)
    base_name = _pending_release_label_image_base_name(pending_release)
    stored_name = _unique_filename(image_dir, base_name, ext)
    path = os.path.join(image_dir, stored_name)
    content = _read_upload_bytes(file, max_bytes=MAX_PENDING_RELEASE_IMAGE_BYTES, description="Label image")
    with open(path, "wb") as out:
        out.write(content)
    release_data = _safe_json_dict(pending_release.release_data_json)
    image_options = release_data.get("image_options")
    if not isinstance(image_options, list):
        image_options = []
    image_options.append(
        {
            "id": uuid.uuid4().hex,
            "url": str(request.url_for("public_pending_release_label_image_file", filename=stored_name)),
            "filename": stored_name,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
    )
    release_data["image_options"] = image_options
    if not release_data.get("selected_image_id") and image_options:
        release_data["selected_image_id"] = image_options[0]["id"]
    _save_pending_release_data(pending_release, release_data)
    db.commit()
    db.refresh(pending_release)
    _notify_pending_release_artist(
        pending_release,
        subject=f'New image option for "{pending_release.release_title}"',
        body_lines=[
            "The label uploaded a new image option for your release.",
            "Open the pending release page in the artist portal to review and choose the image you want.",
        ],
    )
    return _serialize_pending_release_detail(pending_release)


@router.delete(
    "/admin/pending-releases/{pending_release_id}/images/{image_id}",
    response_model=PendingReleaseDetailOut,
)
def admin_delete_pending_release_image_option(
    pending_release_id: int,
    image_id: str,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseDetailOut:
    require_admin(user)
    image_id = (image_id or "").strip()
    if not image_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="image_id is required")
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    release_data = _safe_json_dict(pending_release.release_data_json)
    image_options = release_data.get("image_options")
    if not isinstance(image_options, list):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")
    target: dict | None = None
    for item in image_options:
        if isinstance(item, dict) and (item.get("id") or "").strip() == image_id:
            target = item
            break
    if not target:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")
    url = (target.get("url") or "").strip() if isinstance(target.get("url"), str) else ""
    resolved = _pending_release_upload_path_from_public_url(url)
    if resolved is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only images uploaded to this system can be removed.",
        )
    fs_path, kind = resolved
    if kind != "label":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This image can only be removed from the label upload list.",
        )
    if os.path.isfile(fs_path):
        try:
            os.remove(fs_path)
        except OSError:
            pass
    new_options = [
        item
        for item in image_options
        if not (isinstance(item, dict) and (item.get("id") or "").strip() == image_id)
    ]
    release_data["image_options"] = new_options
    sel = (release_data.get("selected_image_id") or "").strip() if isinstance(release_data.get("selected_image_id"), str) else ""
    if sel == image_id:
        release_data["selected_image_id"] = (
            (new_options[0].get("id") or "").strip()
            if new_options and isinstance(new_options[0], dict)
            else None
        )
    _save_pending_release_data(pending_release, release_data)
    db.commit()
    db.refresh(pending_release)
    return _serialize_pending_release_detail(pending_release)


@router.post(
    "/admin/pending-releases/{pending_release_id}/remove-stored-image",
    response_model=PendingReleaseDetailOut,
)
def admin_remove_pending_release_stored_image(
    pending_release_id: int,
    body: PendingReleaseRemoveStoredImageBody,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseDetailOut:
    """Remove a server-stored image: label option (uploads dir) or artist cover reference (references dir)."""
    require_admin(user)
    raw_url = (body.url or "").strip()
    if not raw_url:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="url is required")
    resolved = _pending_release_upload_path_from_public_url(raw_url)
    if resolved is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Not a server-stored pending release image URL.",
        )
    fs_path, kind = resolved
    req_path = _normalize_public_image_url_path_for_match(raw_url)

    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    release_data = _safe_json_dict(pending_release.release_data_json)

    if kind == "label":
        image_options = release_data.get("image_options")
        if not isinstance(image_options, list):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")
        target: dict | None = None
        for item in image_options:
            if not isinstance(item, dict):
                continue
            u = (item.get("url") or "").strip()
            if _normalize_public_image_url_path_for_match(u) == req_path:
                target = item
                break
        if not target:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found in options")
        image_id = (target.get("id") or "").strip()
        if not image_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Image option has no id")
        url = (target.get("url") or "").strip() if isinstance(target.get("url"), str) else ""
        path_resolved = _pending_release_upload_path_from_public_url(url)
        if path_resolved is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only images uploaded to this system can be removed.",
            )
        path_fs, path_kind = path_resolved
        if path_kind != "label":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="This image can only be removed from the label upload list.",
            )
        if os.path.isfile(path_fs):
            try:
                os.remove(path_fs)
            except OSError:
                pass
        new_options = [
            item
            for item in image_options
            if not (isinstance(item, dict) and (item.get("id") or "").strip() == image_id)
        ]
        release_data["image_options"] = new_options
        sel = (release_data.get("selected_image_id") or "").strip() if isinstance(release_data.get("selected_image_id"), str) else ""
        if sel == image_id:
            release_data["selected_image_id"] = (
                (new_options[0].get("id") or "").strip()
                if new_options and isinstance(new_options[0], dict)
                else None
            )
    else:
        cov = (release_data.get("cover_reference_image_url") or "").strip()
        if _normalize_public_image_url_path_for_match(cov) != req_path:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="URL does not match the stored cover reference.",
            )
        if os.path.isfile(fs_path):
            try:
                os.remove(fs_path)
            except OSError:
                pass
        release_data["cover_reference_image_url"] = ""
        release_data["cover_reference_image_name"] = ""

    _save_pending_release_data(pending_release, release_data)
    db.commit()
    db.refresh(pending_release)
    return _serialize_pending_release_detail(pending_release)


@router.post(
    "/admin/pending-releases/{pending_release_id}/images/{image_id}/normalize-jpg",
    response_model=PendingReleaseDetailOut,
)
def admin_normalize_pending_release_image_jpg_3000(
    request: Request,
    pending_release_id: int,
    image_id: str,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseDetailOut:
    require_admin(user)
    image_id = (image_id or "").strip()
    if not image_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="image_id is required")
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    release_data = _safe_json_dict(pending_release.release_data_json)
    image_options = release_data.get("image_options")
    if not isinstance(image_options, list):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")
    target: dict | None = None
    for item in image_options:
        if isinstance(item, dict) and (item.get("id") or "").strip() == image_id:
            target = item
            break
    if not target:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")
    url = (target.get("url") or "").strip() if isinstance(target.get("url"), str) else ""
    resolved = _pending_release_upload_path_from_public_url(url)
    if resolved is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only images uploaded to this system can be converted.",
        )
    fs_path, kind = resolved
    if kind != "label":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only label-uploaded images can be converted.",
        )
    if not os.path.isfile(fs_path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image file missing on disk")
    try:
        with open(fs_path, "rb") as fh:
            raw_bytes = fh.read()
        jpg_bytes = _bytes_to_jpg_3000_square(raw_bytes)
    except Exception as exc:
        logging.getLogger(__name__).warning("normalize pending release image failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Could not read or convert this image.",
        ) from exc
    image_dir = os.path.join(settings.upload_dir, "pending_release_label_images")
    os.makedirs(image_dir, exist_ok=True)
    new_name = f"{uuid.uuid4().hex}.jpg"
    new_path = os.path.join(image_dir, new_name)
    with open(new_path, "wb") as out:
        out.write(jpg_bytes)
    try:
        if os.path.abspath(fs_path) != os.path.abspath(new_path):
            os.remove(fs_path)
    except OSError:
        pass
    try:
        old_base = (target.get("filename") or "").strip() or os.path.basename(fs_path)
        stem = os.path.splitext(old_base)[0] or "cover"
        new_filename = f"{stem}.jpg"
    except Exception:
        new_filename = new_name
    target["url"] = str(request.url_for("public_pending_release_label_image_file", filename=new_name))
    target["filename"] = new_filename
    if isinstance(target.get("created_at"), str):
        target["created_at"] = datetime.now(timezone.utc).isoformat()
    release_data["image_options"] = image_options
    _save_pending_release_data(pending_release, release_data)
    db.commit()
    db.refresh(pending_release)
    return _serialize_pending_release_detail(pending_release)


@router.post("/admin/pending-releases/{pending_release_id}/archive", response_model=PendingReleaseActionResponse)
def admin_archive_pending_release(
    pending_release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseActionResponse:
    require_admin(user)
    if not archive_pending_release(db, pending_release_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    db.commit()
    return PendingReleaseActionResponse(success=True, message="Pending release archived")


@router.delete("/admin/pending-releases/{pending_release_id}", response_model=PendingReleaseActionResponse)
def admin_delete_pending_release(
    pending_release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseActionResponse:
    require_admin(user)
    if not delete_pending_release(db, pending_release_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    db.commit()
    return PendingReleaseActionResponse(success=True, message="Pending release deleted")


@router.post("/admin/pending-releases/{pending_release_id}/send-reminder", response_model=PendingReleaseReminderResponse)
def admin_send_pending_release_reminder(
    pending_release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseReminderResponse:
    """Send a reminder email with a one-week link so the artist can complete or update release details."""
    require_admin(user)
    pending_release = db.query(PendingRelease).filter(PendingRelease.id == pending_release_id).first()
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    artist = None
    if pending_release.artist_id is not None:
        artist = db.query(Artist).filter(Artist.id == pending_release.artist_id).first()
    to_email = (pending_release.artist_email or (artist.email if artist else "") or "").strip().lower()
    if not to_email:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist email is missing for this pending release")
    form_link, expires_at = create_pending_release_reminder_token(
        db,
        pending_release=pending_release,
        artist=artist,
        expires_in_days=7,
    )
    artist_name = (pending_release.artist_name or (artist.name if artist else "") or "").strip() or "there"
    release_title = (pending_release.release_title or "").strip() or "your release"
    expires_label = expires_at.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    subject = f"Reminder: please complete the details for \"{release_title}\""
    body = (
        f"Hi {artist_name},\n\n"
        f"We still need a few details to complete your approved release \"{release_title}\".\n\n"
        "Please update the release details here:\n"
        f"{form_link}\n\n"
        f"This link is valid until {expires_label}.\n\n"
        "You can add the WAV download link, confirm whether mastering is needed, add a cover reference image, "
        "update the musical style, and send any marketing/story notes for the release.\n\n"
        "If mastering is needed, please make sure the files have 6 dB headroom.\n\n"
        "Best regards,\nZalmanim"
    )
    success, message = send_email_service(
        to_email=to_email,
        subject=subject,
        body_text=body,
    )
    if not success:
        db.rollback()
        if "limit" in message.lower():
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)
    if pending_release.artist_id is not None:
        db.add(
            ArtistActivityLog(
                artist_id=pending_release.artist_id,
                activity_type="pending_release_reminder_email",
                details=f"pending_release_id={pending_release.id}",
            )
        )
    
    db.commit()
    return PendingReleaseReminderResponse(
        success=True,
        message="Completion email sent",
        expires_at=expires_at,
    )