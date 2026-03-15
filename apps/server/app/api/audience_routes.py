import csv
import io
import secrets
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, status
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.db.session import get_db
from app.models.models import Artist, MailingList, MailingSubscriber, User
from app.schemas.schemas import (
    MailingListCreate,
    MailingListOut,
    MailingListUpdate,
    MailingSubscriberCreate,
    MailingSubscriberOut,
    MailingSubscriberUpdate,
    UserContext,
)
from app.services.auth import decode_token, permissions_for_role

router = APIRouter()
security = HTTPBearer()
_VALID_SUBSCRIBER_STATUSES = {"subscribed", "unsubscribed", "cleaned"}
_MAILCHIMP_EMAIL_KEYS = ("email address", "email", "email_address")
_MAILCHIMP_FIRST_NAME_KEYS = ("first name", "fname", "first_name")
_MAILCHIMP_LAST_NAME_KEYS = ("last name", "lname", "last_name")
_MAILCHIMP_STATUS_KEYS = ("status", "email marketing status")
_MAILCHIMP_CONSENT_KEYS = ("timestamp signup", "optin time", "date added")


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
) -> UserContext:
    """Resolve user or artist from JWT (sub) and DB; role comes from DB, not from token."""
    try:
        payload = decode_token(credentials.credentials)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token") from exc
    sub = payload.get("sub")
    if isinstance(sub, str) and sub.startswith("artist:"):
        try:
            artist_id = int(sub[7:])
        except ValueError:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
        artist = db.query(Artist).filter(Artist.id == artist_id).first()
        if not artist or not artist.is_active:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Artist is inactive or missing")
        return UserContext(
            user_id=0,
            role="artist",
            email=artist.email,
            full_name=artist.name,
            permissions=permissions_for_role("artist"),
            artist_id=artist.id,
            is_active=artist.is_active,
        )
    # Admin/manager token (users table)
    try:
        user_id = int(payload["sub"])
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user = (
        db.query(User)
        .options(joinedload(User.artist), joinedload(User.identities))
        .filter(User.id == user_id)
        .first()
    )
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User is inactive or missing")
    return UserContext(
        user_id=user.id,
        role=user.role,
        email=user.email,
        full_name=user.full_name,
        permissions=permissions_for_role(user.role),
        artist_id=user.artist_id,
        is_active=user.is_active,
    )



# Reject artist tokens on LM-only routes (same message as routes.LM_FORBIDDEN_ARTIST_DETAIL).
LM_FORBIDDEN_ARTIST_DETAIL = "Artists cannot access the LM system. Use the artist portal."


def get_current_lm_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
) -> UserContext:
    """
    Same as get_current_user but rejects artist portal tokens with 403.
    Use for all LM (label management) routes; only users from the users table are allowed.
    """
    try:
        payload = decode_token(credentials.credentials)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token") from exc
    sub = payload.get("sub")
    if isinstance(sub, str) and sub.startswith("artist:"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=LM_FORBIDDEN_ARTIST_DETAIL,
        )
    try:
        user_id = int(payload["sub"])
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user = (
        db.query(User)
        .options(joinedload(User.artist), joinedload(User.identities))
        .filter(User.id == user_id)
        .first()
    )
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User is inactive or missing")
    return UserContext(
        user_id=user.id,
        role=user.role,
        email=user.email,
        full_name=user.full_name,
        permissions=permissions_for_role(user.role),
        artist_id=user.artist_id,
        is_active=user.is_active,
    )


def require_admin(user: UserContext) -> None:
    if user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin only")



def _validate_status(value: str) -> str:
    status_value = (value or "").strip().lower()
    if status_value not in _VALID_SUBSCRIBER_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid subscriber status. Allowed: {', '.join(sorted(_VALID_SUBSCRIBER_STATUSES))}",
        )
    return status_value



def _normalize_mailchimp_status(value: str | None) -> str:
    raw = (value or "").strip().lower()
    if raw in {"", "subscribed"}:
        return "subscribed"
    if raw in {"unsubscribed", "archived"}:
        return "unsubscribed"
    if raw in {"cleaned", "non-subscribed", "nonsubscribed", "pending", "transactional"}:
        return "cleaned"
    return "subscribed"



def _parse_datetime(value: str | None) -> datetime | None:
    text = (value or "").strip()
    if not text:
        return None
    for pattern in (
        "%Y-%m-%d %H:%M:%S",
        "%m/%d/%Y %H:%M",
        "%m/%d/%Y %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S%z",
        "%Y-%m-%dT%H:%M:%S",
    ):
        try:
            parsed = datetime.strptime(text, pattern)
            if parsed.tzinfo is None:
                return parsed.replace(tzinfo=timezone.utc)
            return parsed.astimezone(timezone.utc)
        except ValueError:
            continue
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return None



def _cell(row: dict[str, str], *keys: str) -> str:
    normalized = {str(k).strip().lower(): (v or "") for k, v in row.items()}
    for key in keys:
        if key in normalized and normalized[key].strip():
            return normalized[key].strip()
    return ""



def _build_full_name(row: dict[str, str]) -> str | None:
    first_name = _cell(row, *_MAILCHIMP_FIRST_NAME_KEYS)
    last_name = _cell(row, *_MAILCHIMP_LAST_NAME_KEYS)
    full_name = " ".join(part for part in [first_name, last_name] if part).strip()
    return full_name or None



def _decode_csv_bytes(data: bytes) -> str:
    for encoding in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Could not decode CSV file")



def _ensure_target_list(
    db: Session,
    *,
    existing_list_id: int | None,
    list_name: str | None,
    filename: str | None,
) -> MailingList:
    if existing_list_id is not None:
        mailing_list = db.get(MailingList, existing_list_id)
        if not mailing_list:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Audience not found")
        return mailing_list

    resolved_name = (list_name or "").strip()
    if not resolved_name:
        resolved_name = Path(filename or "mailchimp-import.csv").stem.replace("_", " ").replace("-", " ").strip() or "Mailchimp Import"

    mailing_list = MailingList(name=resolved_name, description="Imported from Mailchimp CSV")
    db.add(mailing_list)
    db.commit()
    db.refresh(mailing_list)
    return mailing_list



def _subscriber_out(request: Request, subscriber: MailingSubscriber) -> MailingSubscriberOut:
    return MailingSubscriberOut(
        id=subscriber.id,
        list_id=subscriber.list_id,
        email=subscriber.email,
        full_name=subscriber.full_name,
        status=subscriber.status,
        consent_source=subscriber.consent_source,
        consent_at=subscriber.consent_at,
        unsubscribed_at=subscriber.unsubscribed_at,
        notes=subscriber.notes,
        unsubscribe_url=str(request.url_for("public_unsubscribe", token=subscriber.unsubscribe_token)),
        created_at=subscriber.created_at,
        updated_at=subscriber.updated_at,
    )



def _list_out(db: Session, mailing_list: MailingList) -> MailingListOut:
    counts = dict(
        db.query(MailingSubscriber.status, func.count(MailingSubscriber.id))
        .filter(MailingSubscriber.list_id == mailing_list.id)
        .group_by(MailingSubscriber.status)
        .all()
    )
    return MailingListOut(
        id=mailing_list.id,
        name=mailing_list.name,
        description=mailing_list.description or "",
        from_name=mailing_list.from_name,
        reply_to_email=mailing_list.reply_to_email,
        company_name=mailing_list.company_name,
        physical_address=mailing_list.physical_address,
        default_language=mailing_list.default_language,
        subscribed_count=int(counts.get("subscribed", 0)),
        unsubscribed_count=int(counts.get("unsubscribed", 0)),
        created_at=mailing_list.created_at,
        updated_at=mailing_list.updated_at,
    )


@router.get("/admin/audiences", response_model=list[MailingListOut])
def list_audiences(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[MailingListOut]:
    require_admin(user)
    lists = db.query(MailingList).order_by(MailingList.created_at.desc(), MailingList.id.desc()).all()
    return [_list_out(db, mailing_list) for mailing_list in lists]


@router.post("/admin/audiences", response_model=MailingListOut)
def create_audience(
    payload: MailingListCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> MailingListOut:
    require_admin(user)
    mailing_list = MailingList(
        name=payload.name.strip(),
        description=payload.description,
        from_name=payload.from_name,
        reply_to_email=str(payload.reply_to_email) if payload.reply_to_email else None,
        company_name=payload.company_name,
        physical_address=payload.physical_address,
        default_language=(payload.default_language or "en").strip() or "en",
    )
    db.add(mailing_list)
    db.commit()
    db.refresh(mailing_list)
    return _list_out(db, mailing_list)


@router.patch("/admin/audiences/{list_id}", response_model=MailingListOut)
def update_audience(
    list_id: int,
    payload: MailingListUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> MailingListOut:
    require_admin(user)
    mailing_list = db.get(MailingList, list_id)
    if not mailing_list:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Audience not found")
    data = payload.model_dump(exclude_unset=True)
    if "name" in data:
        mailing_list.name = (payload.name or "").strip() or mailing_list.name
    if "description" in data:
        mailing_list.description = payload.description or ""
    if "from_name" in data:
        mailing_list.from_name = payload.from_name
    if "reply_to_email" in data:
        mailing_list.reply_to_email = str(payload.reply_to_email) if payload.reply_to_email else None
    if "company_name" in data:
        mailing_list.company_name = payload.company_name
    if "physical_address" in data:
        mailing_list.physical_address = payload.physical_address
    if "default_language" in data:
        mailing_list.default_language = (payload.default_language or "en").strip() or "en"
    db.commit()
    db.refresh(mailing_list)
    return _list_out(db, mailing_list)


@router.post("/admin/audiences/import/mailchimp")
async def import_mailchimp_audience(
    request: Request,
    file: UploadFile = File(...),
    existing_list_id: int | None = Form(None),
    list_name: str | None = Form(None),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    require_admin(user)
    if not (file.filename or "").lower().endswith(".csv"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Upload a Mailchimp CSV export")

    raw_data = await file.read()
    if not raw_data:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSV file is empty")

    mailing_list = _ensure_target_list(
        db,
        existing_list_id=existing_list_id,
        list_name=list_name,
        filename=file.filename,
    )
    csv_text = _decode_csv_bytes(raw_data)
    reader = csv.DictReader(io.StringIO(csv_text))
    if not reader.fieldnames:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSV header row is missing")

    created = 0
    updated = 0
    skipped = 0
    source_label = f"mailchimp_import:{file.filename or 'upload.csv'}"

    for row in reader:
        email = _cell(row, *_MAILCHIMP_EMAIL_KEYS).lower()
        if not email:
            skipped += 1
            continue

        full_name = _build_full_name(row)
        status_value = _normalize_mailchimp_status(_cell(row, *_MAILCHIMP_STATUS_KEYS))
        consent_at = _parse_datetime(_cell(row, *_MAILCHIMP_CONSENT_KEYS))
        subscriber = (
            db.query(MailingSubscriber)
            .filter(MailingSubscriber.list_id == mailing_list.id, MailingSubscriber.email == email)
            .first()
        )

        if subscriber:
            subscriber.full_name = full_name or subscriber.full_name
            subscriber.status = status_value
            subscriber.consent_source = subscriber.consent_source or source_label
            subscriber.consent_at = subscriber.consent_at or consent_at or datetime.now(timezone.utc)
            subscriber.unsubscribed_at = datetime.now(timezone.utc) if status_value == "unsubscribed" else None
            updated += 1
            continue

        db.add(
            MailingSubscriber(
                list_id=mailing_list.id,
                email=email,
                full_name=full_name,
                status=status_value,
                consent_source=source_label,
                consent_at=consent_at or datetime.now(timezone.utc),
                unsubscribed_at=datetime.now(timezone.utc) if status_value == "unsubscribed" else None,
                unsubscribe_token=secrets.token_urlsafe(24),
            )
        )
        created += 1

    db.commit()

    return {
        "ok": True,
        "list_id": mailing_list.id,
        "list_name": mailing_list.name,
        "created": created,
        "updated": updated,
        "skipped": skipped,
        "message": f"Imported Mailchimp CSV into '{mailing_list.name}': {created} created, {updated} updated, {skipped} skipped.",
        "audience": _list_out(db, mailing_list).model_dump(),
    }


@router.get("/admin/audiences/{list_id}/subscribers", response_model=list[MailingSubscriberOut])
def list_audience_subscribers(
    list_id: int,
    request: Request,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[MailingSubscriberOut]:
    require_admin(user)
    mailing_list = db.get(MailingList, list_id)
    if not mailing_list:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Audience not found")
    subscribers = (
        db.query(MailingSubscriber)
        .filter(MailingSubscriber.list_id == list_id)
        .order_by(MailingSubscriber.created_at.desc(), MailingSubscriber.id.desc())
        .all()
    )
    return [_subscriber_out(request, subscriber) for subscriber in subscribers]


@router.post("/admin/audiences/{list_id}/subscribers", response_model=MailingSubscriberOut)
def create_audience_subscriber(
    list_id: int,
    payload: MailingSubscriberCreate,
    request: Request,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> MailingSubscriberOut:
    require_admin(user)
    mailing_list = db.get(MailingList, list_id)
    if not mailing_list:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Audience not found")
    normalized_status = _validate_status(payload.status)
    subscriber = MailingSubscriber(
        list_id=list_id,
        email=str(payload.email).strip().lower(),
        full_name=(payload.full_name or "").strip() or None,
        status=normalized_status,
        consent_source=(payload.consent_source or "").strip() or None,
        consent_at=payload.consent_at or datetime.now(timezone.utc),
        unsubscribed_at=datetime.now(timezone.utc) if normalized_status == "unsubscribed" else None,
        unsubscribe_token=secrets.token_urlsafe(24),
        notes=payload.notes,
    )
    db.add(subscriber)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Subscriber already exists in this audience") from exc
    db.refresh(subscriber)
    return _subscriber_out(request, subscriber)


@router.patch("/admin/audiences/{list_id}/subscribers/{subscriber_id}", response_model=MailingSubscriberOut)
def update_audience_subscriber(
    list_id: int,
    subscriber_id: int,
    payload: MailingSubscriberUpdate,
    request: Request,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> MailingSubscriberOut:
    require_admin(user)
    subscriber = db.get(MailingSubscriber, subscriber_id)
    if not subscriber or subscriber.list_id != list_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subscriber not found")

    data = payload.model_dump(exclude_unset=True)
    if "email" in data:
        subscriber.email = str(payload.email).strip().lower() if payload.email else subscriber.email
    if "full_name" in data:
        subscriber.full_name = (payload.full_name or "").strip() or None
    if "consent_source" in data:
        subscriber.consent_source = (payload.consent_source or "").strip() or None
    if "consent_at" in data:
        subscriber.consent_at = payload.consent_at
    if "notes" in data:
        subscriber.notes = payload.notes
    if "status" in data:
        subscriber.status = _validate_status(payload.status or subscriber.status)
        if subscriber.status == "unsubscribed":
            subscriber.unsubscribed_at = subscriber.unsubscribed_at or datetime.now(timezone.utc)
        else:
            subscriber.unsubscribed_at = None
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Subscriber email already exists in this audience") from exc
    db.refresh(subscriber)
    return _subscriber_out(request, subscriber)


@router.get("/unsubscribe/{token}", response_class=HTMLResponse, name="public_unsubscribe")
def public_unsubscribe(
    token: str,
    db: Session = Depends(get_db),
) -> HTMLResponse:
    subscriber = db.query(MailingSubscriber).filter(MailingSubscriber.unsubscribe_token == token).first()
    if not subscriber:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Unsubscribe link is invalid")

    if subscriber.status != "unsubscribed":
        subscriber.status = "unsubscribed"
        subscriber.unsubscribed_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(subscriber)

    list_name = subscriber.mailing_list.name if subscriber.mailing_list else "the mailing list"
    return HTMLResponse(
        content=f"""
        <!DOCTYPE html>
        <html lang=\"en\">
        <head>
          <meta charset=\"utf-8\" />
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
          <title>Unsubscribed</title>
        </head>
        <body style=\"font-family: Arial, sans-serif; max-width: 640px; margin: 40px auto; padding: 24px; line-height: 1.5;\">
          <h1>You have been unsubscribed</h1>
          <p><strong>{subscriber.email}</strong> will no longer receive marketing emails from <strong>{list_name}</strong>.</p>
          <p>If this was a mistake, an administrator can resubscribe you manually.</p>
        </body>
        </html>
        """,
    )
