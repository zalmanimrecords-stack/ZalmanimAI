"""Ingest incoming email (delivered to the label mailbox) into the label inbox.

Mail for the label domain is delivered to a self-hosted docker-mailserver mailbox.
This service polls that mailbox over IMAP (read-only — it never deletes server mail)
and stores each new message as a LabelInboxMessage with sender == 'external_email',
so the admin inbox can show real incoming email tagged separately from portal messages.

Layering: pure parsing + DB ingestion live here and are unit-tested; the IMAP transport
wrapper is a thin, separately guarded function used by the worker.
"""

from __future__ import annotations

import email
import email.policy
import imaplib
import logging
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from email.message import EmailMessage
from email.utils import parseaddr, parsedate_to_datetime

from sqlalchemy import desc, func
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.models import Artist, LabelInboxMessage, LabelInboxThread

logger = logging.getLogger(__name__)

SENDER_EXTERNAL_EMAIL = "external_email"
THREAD_SOURCE_EMAIL = "email"

_HTML_TAG_RE = re.compile(r"<[^>]+>")
_MAX_BODY_CHARS = 50_000  # Guard against pathological emails bloating the row


@dataclass(frozen=True)
class ParsedEmail:
    """Normalized view of an incoming email, independent of the transport."""

    message_id: str | None
    from_address: str
    subject: str
    body_text: str
    sent_at: datetime | None


def _decode_part_to_text(part: EmailMessage) -> str:
    """Decode a message part to text, falling back gracefully on bad charsets."""
    try:
        content = part.get_content()
    except (LookupError, ValueError, UnicodeDecodeError):
        payload = part.get_payload(decode=True) or b""
        content = payload.decode("utf-8", errors="replace")
    if isinstance(content, bytes):
        content = content.decode("utf-8", errors="replace")
    return content


def _strip_html(html: str) -> str:
    text = _HTML_TAG_RE.sub(" ", html)
    return re.sub(r"[ \t]+\n", "\n", text).strip()


def _extract_body_text(msg: EmailMessage) -> str:
    """Prefer the text/plain body; fall back to a stripped text/html body."""
    plain = msg.get_body(preferencelist=("plain",))
    if plain is not None:
        return _decode_part_to_text(plain).strip()[:_MAX_BODY_CHARS]
    html = msg.get_body(preferencelist=("html",))
    if html is not None:
        return _strip_html(_decode_part_to_text(html))[:_MAX_BODY_CHARS]
    # Non-multipart or unusual structure: best-effort decode of the whole message.
    return _decode_part_to_text(msg).strip()[:_MAX_BODY_CHARS]


def parse_email_message(raw: bytes) -> ParsedEmail:
    """Parse raw RFC822 bytes into a ParsedEmail. Never raises on malformed mail."""
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    _, from_address = parseaddr(str(msg.get("From", "")))
    subject = str(msg.get("Subject", "")).strip()
    message_id = (str(msg.get("Message-ID", "")).strip() or None)
    sent_at: datetime | None = None
    date_header = msg.get("Date")
    if date_header is not None:
        try:
            sent_at = parsedate_to_datetime(str(date_header))
        except (TypeError, ValueError):
            sent_at = None
    return ParsedEmail(
        message_id=message_id,
        from_address=(from_address or "").strip().lower(),
        subject=subject,
        body_text=_extract_body_text(msg),
        sent_at=sent_at,
    )


def _find_artist_by_email(db: Session, address: str) -> Artist | None:
    if not address:
        return None
    return (
        db.query(Artist)
        .filter(Artist.email.isnot(None))
        .filter(func.lower(Artist.email) == address)
        .first()
    )


def _already_ingested(db: Session, message_id: str | None) -> bool:
    if not message_id:
        return False
    return (
        db.query(LabelInboxMessage)
        .filter(LabelInboxMessage.external_message_id == message_id)
        .first()
        is not None
    )


def _get_or_create_email_thread(db: Session, *, from_address: str, subject: str, artist: Artist | None) -> LabelInboxThread:
    """Group an external sender's mail into a single email-source thread."""
    thread = (
        db.query(LabelInboxThread)
        .filter(LabelInboxThread.source == THREAD_SOURCE_EMAIL)
        .filter(LabelInboxThread.external_from == from_address)
        .order_by(desc(LabelInboxThread.updated_at), desc(LabelInboxThread.id))
        .first()
    )
    if thread:
        if artist and thread.artist_id is None:
            thread.artist_id = artist.id
        return thread
    thread = LabelInboxThread(
        artist_id=artist.id if artist else None,
        source=THREAD_SOURCE_EMAIL,
        external_from=from_address,
        subject=subject[:500] or None,
    )
    db.add(thread)
    db.flush()
    return thread


def ingest_parsed_email(db: Session, parsed: ParsedEmail) -> LabelInboxMessage | None:
    """Store a parsed email as an inbox message. Returns None if it was a duplicate.

    Deduplicates by RFC Message-ID so repeated polls of the same mailbox do not
    create duplicate rows. The caller commits.
    """
    if _already_ingested(db, parsed.message_id):
        return None

    artist = _find_artist_by_email(db, parsed.from_address)
    thread = _get_or_create_email_thread(
        db,
        from_address=parsed.from_address,
        subject=parsed.subject,
        artist=artist,
    )
    message = LabelInboxMessage(
        thread_id=thread.id,
        sender=SENDER_EXTERNAL_EMAIL,
        body=parsed.body_text or "(empty message)",
        admin_read_at=None,
        external_message_id=parsed.message_id,
        external_from=parsed.from_address or None,
        external_subject=parsed.subject[:500] or None,
    )
    db.add(message)
    thread.updated_at = parsed.sent_at or datetime.now(timezone.utc)
    db.flush()
    return message


def _connect_imap() -> imaplib.IMAP4:
    if settings.imap_use_ssl:
        client: imaplib.IMAP4 = imaplib.IMAP4_SSL(settings.imap_host, settings.imap_port)
    else:
        client = imaplib.IMAP4(settings.imap_host, settings.imap_port)
        try:
            client.starttls()
        except (imaplib.IMAP4.error, OSError):
            # Server without STARTTLS on plain port — proceed unencrypted only on an internal host.
            logger.warning("IMAP STARTTLS unavailable on %s:%s", settings.imap_host, settings.imap_port)
    client.login(settings.imap_user, settings.imap_password)
    return client


def fetch_and_ingest(db: Session) -> int:
    """Poll the configured mailbox for unseen mail and ingest it. Returns count ingested.

    Marks fetched messages as Seen on the server (so they are not re-fetched) but never
    deletes them. Safe no-op when IMAP is not configured.
    """
    if not settings.imap_ingest_enabled():
        return 0

    client: imaplib.IMAP4 | None = None
    ingested = 0
    try:
        client = _connect_imap()
        client.select(settings.imap_mailbox)
        status, data = client.search(None, "UNSEEN")
        if status != "OK":
            logger.warning("IMAP search failed for %s: %s", settings.imap_user, status)
            return 0
        message_numbers = (data[0] or b"").split()
        for num in message_numbers:
            fetch_status, fetch_data = client.fetch(num, "(RFC822)")
            if fetch_status != "OK" or not fetch_data or not isinstance(fetch_data[0], tuple):
                logger.warning("IMAP fetch failed for message %s", num)
                continue
            raw = fetch_data[0][1]
            try:
                parsed = parse_email_message(raw)
                if ingest_parsed_email(db, parsed) is not None:
                    ingested += 1
            except Exception:  # one bad email must not abort the whole batch
                logger.exception("Failed to ingest an incoming email")
                db.rollback()
                continue
            client.store(num, "+FLAGS", "\\Seen")
        db.commit()
    except (imaplib.IMAP4.error, OSError) as exc:
        logger.error("IMAP ingestion failed for %s: %s", settings.imap_user, exc)
        db.rollback()
    finally:
        if client is not None:
            try:
                client.logout()
            except (imaplib.IMAP4.error, OSError):
                pass
    return ingested
