import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.models import MailingList, MailingSubscriber
from app.schemas.schemas import (
    MailingListCreate,
    MailingListOut,
    MailingListUpdate,
    MailingSubscriberCreate,
    MailingSubscriberOut,
    MailingSubscriberUpdate,
    UserContext,
)
from app.services.auth import decode_token

router = APIRouter()
security = HTTPBearer()
_VALID_SUBSCRIBER_STATUSES = {"subscribed", "unsubscribed", "cleaned"}


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> UserContext:
    try:
        payload = decode_token(credentials.credentials)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token") from exc
    return UserContext(
        user_id=int(payload["sub"]),
        role=str(payload["role"]),
        artist_id=payload.get("artist_id"),
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
    user: UserContext = Depends(get_current_user),
) -> list[MailingListOut]:
    require_admin(user)
    lists = db.query(MailingList).order_by(MailingList.created_at.desc(), MailingList.id.desc()).all()
    return [_list_out(db, mailing_list) for mailing_list in lists]


@router.post("/admin/audiences", response_model=MailingListOut)
def create_audience(
    payload: MailingListCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
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
    user: UserContext = Depends(get_current_user),
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


@router.get("/admin/audiences/{list_id}/subscribers", response_model=list[MailingSubscriberOut])
def list_audience_subscribers(
    list_id: int,
    request: Request,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
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
    user: UserContext = Depends(get_current_user),
) -> MailingSubscriberOut:
    require_admin(user)
    mailing_list = db.get(MailingList, list_id)
    if not mailing_list:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Audience not found")
    subscriber = MailingSubscriber(
        list_id=list_id,
        email=str(payload.email).strip().lower(),
        full_name=(payload.full_name or "").strip() or None,
        status=_validate_status(payload.status),
        consent_source=(payload.consent_source or "").strip() or None,
        consent_at=payload.consent_at or datetime.now(timezone.utc),
        unsubscribed_at=datetime.now(timezone.utc) if _validate_status(payload.status) == "unsubscribed" else None,
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
    user: UserContext = Depends(get_current_user),
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
