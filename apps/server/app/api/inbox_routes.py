import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import desc
from sqlalchemy.orm import Session, joinedload

from app.api.deps import get_current_lm_user, get_current_user, require_admin, require_artist
from app.db.session import get_db
from app.models.models import Artist, LabelInboxMessage, LabelInboxThread, PendingRelease
from app.schemas.schemas import (
    LabelInboxMessageOut,
    LabelInboxReply,
    LabelInboxSend,
    LabelInboxThreadDetailOut,
    LabelInboxThreadOut,
    UserContext,
)
from app.services.email_service import is_email_configured, send_email as send_email_service

router = APIRouter()


def _label_inbox_message_out(m: LabelInboxMessage) -> LabelInboxMessageOut:
    return LabelInboxMessageOut(
        id=m.id,
        sender=m.sender,
        body=m.body,
        created_at=m.created_at,
        admin_read_at=m.admin_read_at,
        reply_email_sent_at=m.reply_email_sent_at,
    )


def _label_inbox_unread_count(messages: list[LabelInboxMessage]) -> int:
    return sum(1 for m in messages if m.sender == "artist" and m.admin_read_at is None)


def _label_inbox_thread_out(
    thread: LabelInboxThread,
    artist: Artist,
    last_message_preview: str,
    last_message_at: datetime,
    message_count: int,
    has_label_reply: bool,
    unread_count: int,
) -> LabelInboxThreadOut:
    return LabelInboxThreadOut(
        id=thread.id,
        artist_id=thread.artist_id,
        artist_name=artist.name or "",
        artist_email=artist.email or "",
        last_message_preview=last_message_preview,
        last_message_at=last_message_at,
        created_at=thread.created_at,
        updated_at=thread.updated_at,
        message_count=message_count,
        has_label_reply=has_label_reply,
        unread_count=unread_count,
    )


def _label_inbox_thread_detail_out(
    thread: LabelInboxThread,
    artist: Artist,
    messages: list[LabelInboxMessage],
) -> LabelInboxThreadDetailOut:
    has_label_reply = any(m.sender == "label" for m in messages)
    unread_count = _label_inbox_unread_count(messages)
    return LabelInboxThreadDetailOut(
        id=thread.id,
        artist_id=thread.artist_id,
        artist_name=artist.name or "",
        artist_email=artist.email or "",
        created_at=thread.created_at,
        updated_at=thread.updated_at,
        message_count=len(messages),
        has_label_reply=has_label_reply,
        unread_count=unread_count,
        messages=[_label_inbox_message_out(m) for m in messages],
    )


def _get_or_create_latest_label_inbox_thread(db: Session, artist_id: int) -> LabelInboxThread:
    thread = (
        db.query(LabelInboxThread)
        .filter(LabelInboxThread.artist_id == artist_id)
        .order_by(desc(LabelInboxThread.updated_at), desc(LabelInboxThread.id))
        .first()
    )
    if thread:
        return thread
    thread = LabelInboxThread(artist_id=artist_id)
    db.add(thread)
    db.flush()
    return thread


def _mark_admin_thread_as_read(
    db: Session,
    *,
    thread: LabelInboxThread,
    read_at: datetime | None = None,
) -> bool:
    timestamp = read_at or datetime.now(timezone.utc)
    unread_messages = [
        message
        for message in (thread.messages or [])
        if message.sender == "artist" and message.admin_read_at is None
    ]
    if not unread_messages:
        return False
    for message in unread_messages:
        message.admin_read_at = timestamp
    return True


def _create_pending_release_inbox_message(
    db: Session,
    *,
    pending_release: PendingRelease,
    message_prefix: str,
) -> None:
    if pending_release.artist_id is None:
        return
    thread = _get_or_create_latest_label_inbox_thread(db, pending_release.artist_id)
    release_title = (pending_release.release_title or "").strip() or "Untitled"
    message_body = (
        f"{message_prefix}\n\n"
        f"Release: {release_title}\n"
        f"Artist: {(pending_release.artist_name or '').strip() or 'Artist'}\n"
        f"Email: {(pending_release.artist_email or '').strip().lower()}"
    )
    db.add(
        LabelInboxMessage(
            thread_id=thread.id,
            sender="artist",
            body=message_body,
            admin_read_at=None,
        )
    )
    thread.updated_at = datetime.now(timezone.utc)


@router.post("/artist/me/inbox", response_model=LabelInboxThreadDetailOut)
def artist_send_inbox_message(
    payload: LabelInboxSend,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> LabelInboxThreadDetailOut:
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    body = (payload.body or "").strip()
    if not body:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Message body is required")
    thread = LabelInboxThread(artist_id=artist.id)
    db.add(thread)
    db.flush()
    msg = LabelInboxMessage(
        thread_id=thread.id,
        sender="artist",
        body=body,
        admin_read_at=None,
    )
    db.add(msg)
    db.commit()
    db.refresh(thread)
    db.refresh(msg)
    return _label_inbox_thread_detail_out(thread, artist, [msg])


@router.get("/artist/me/inbox", response_model=list[LabelInboxThreadOut])
def artist_list_my_inbox(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[LabelInboxThreadOut]:
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        return []
    threads = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.messages))
        .filter(LabelInboxThread.artist_id == user.artist_id)
        .order_by(desc(LabelInboxThread.updated_at))
        .all()
    )
    out = []
    for thread in threads:
        msgs = thread.messages or []
        if not msgs:
            continue
        last = msgs[-1]
        preview = (last.body or "")[:120].strip()
        if len(last.body or "") > 120:
            preview += "..."
        has_label = any(m.sender == "label" for m in msgs)
        out.append(
            _label_inbox_thread_out(
                thread,
                artist,
                preview,
                last.created_at,
                len(msgs),
                has_label,
                _label_inbox_unread_count(msgs),
            )
        )
    return out


@router.get("/artist/me/inbox/threads/{thread_id}", response_model=LabelInboxThreadDetailOut)
def artist_get_inbox_thread(
    thread_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> LabelInboxThreadDetailOut:
    require_artist(user)
    thread = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.messages), joinedload(LabelInboxThread.artist))
        .filter(LabelInboxThread.id == thread_id, LabelInboxThread.artist_id == user.artist_id)
        .first()
    )
    if not thread:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    messages = sorted(thread.messages or [], key=lambda m: m.created_at)
    return _label_inbox_thread_detail_out(thread, thread.artist, messages)


@router.get("/admin/inbox", response_model=list[LabelInboxThreadOut])
def admin_list_inbox(
    artist_id: int | None = Query(None, description="Filter by artist id"),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[LabelInboxThreadOut]:
    require_admin(user)
    q = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.artist), joinedload(LabelInboxThread.messages))
        .order_by(desc(LabelInboxThread.updated_at))
        .offset(offset)
        .limit(limit)
    )
    if artist_id is not None:
        q = q.filter(LabelInboxThread.artist_id == artist_id)
    threads = q.all()
    out = []
    for thread in threads:
        artist = thread.artist
        if not artist:
            continue
        msgs = thread.messages or []
        if not msgs:
            continue
        last = msgs[-1]
        preview = (last.body or "")[:120].strip()
        if len(last.body or "") > 120:
            preview += "..."
        has_label = any(m.sender == "label" for m in msgs)
        out.append(
            _label_inbox_thread_out(
                thread,
                artist,
                preview,
                last.created_at,
                len(msgs),
                has_label,
                _label_inbox_unread_count(msgs),
            )
        )
    return out


@router.get("/admin/inbox/threads/{thread_id}", response_model=LabelInboxThreadDetailOut)
def admin_get_inbox_thread(
    thread_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> LabelInboxThreadDetailOut:
    require_admin(user)
    thread = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.messages), joinedload(LabelInboxThread.artist))
        .filter(LabelInboxThread.id == thread_id)
        .first()
    )
    if not thread:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    artist = thread.artist
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if _mark_admin_thread_as_read(db, thread=thread):
        db.commit()
        db.refresh(thread)
    messages = sorted(thread.messages or [], key=lambda m: m.created_at)
    return _label_inbox_thread_detail_out(thread, artist, messages)


@router.post("/admin/inbox/threads/{thread_id}/reply", response_model=LabelInboxThreadDetailOut)
def admin_reply_inbox_thread(
    thread_id: int,
    payload: LabelInboxReply,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> LabelInboxThreadDetailOut:
    require_admin(user)
    thread = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.messages), joinedload(LabelInboxThread.artist))
        .filter(LabelInboxThread.id == thread_id)
        .first()
    )
    if not thread:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    artist = thread.artist
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    body = (payload.body or "").strip()
    if not body:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Reply body is required")
    now = datetime.now(timezone.utc)
    _mark_admin_thread_as_read(db, thread=thread, read_at=now)
    reply_msg = LabelInboxMessage(
        thread_id=thread.id,
        sender="label",
        body=body,
        admin_read_at=now,
    )
    db.add(reply_msg)
    db.flush()
    if is_email_configured():
        label_name = "Zalmanim"
        subject = f"Re: Your message to {label_name}"
        email_body = (
            "The label has replied to your message.\n\n"
            "---\n\n"
            f"{body}\n\n"
            "---\n\nBest regards,\n" + label_name
        )
        success, msg = send_email_service(
            to_email=artist.email,
            subject=subject,
            body_text=email_body,
        )
        if success:
            reply_msg.reply_email_sent_at = now
        else:
            logging.getLogger(__name__).warning(
                "Failed to send inbox reply email to %s: %s", artist.email, msg
            )
    thread.updated_at = now
    db.commit()
    db.refresh(thread)
    db.refresh(reply_msg)
    thread = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.messages), joinedload(LabelInboxThread.artist))
        .filter(LabelInboxThread.id == thread_id)
        .first()
    )
    artist = thread.artist if thread else None
    if not thread or not artist:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Thread not found after reply")
    messages = sorted(thread.messages or [], key=lambda m: m.created_at)
    return _label_inbox_thread_detail_out(thread, artist, messages)


@router.delete("/admin/inbox/threads/{thread_id}")
def admin_delete_inbox_thread(
    thread_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    require_admin(user)
    thread = db.query(LabelInboxThread).filter(LabelInboxThread.id == thread_id).first()
    if not thread:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    db.delete(thread)
    db.commit()
    return {"ok": True}
