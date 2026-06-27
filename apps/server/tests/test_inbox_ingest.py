from email.message import EmailMessage

from app.models.models import Artist, LabelInboxMessage, LabelInboxThread
from app.services.inbox_ingest_service import (
    SENDER_EXTERNAL_EMAIL,
    THREAD_SOURCE_EMAIL,
    ingest_parsed_email,
    parse_email_message,
)


def _raw_email(
    *,
    from_addr: str = "fan@example.com",
    subject: str = "Hello label",
    body: str = "I love your releases!",
    message_id: str = "<msg-1@example.com>",
    html: str | None = None,
) -> bytes:
    msg = EmailMessage()
    msg["From"] = from_addr
    msg["To"] = "simon@zalmanim.com"
    msg["Subject"] = subject
    msg["Message-ID"] = message_id
    msg["Date"] = "Mon, 23 Jun 2026 10:00:00 +0000"
    msg.set_content(body)
    if html is not None:
        msg.add_alternative(html, subtype="html")
    return msg.as_bytes()


def test_parse_email_message_extracts_fields():
    parsed = parse_email_message(_raw_email())

    assert parsed.from_address == "fan@example.com"
    assert parsed.subject == "Hello label"
    assert parsed.message_id == "<msg-1@example.com>"
    assert "I love your releases!" in parsed.body_text
    assert parsed.sent_at is not None


def test_parse_email_prefers_plain_text_over_html():
    parsed = parse_email_message(
        _raw_email(body="plain body", html="<p>html body</p>")
    )

    assert parsed.body_text == "plain body"


def test_parse_email_normalizes_sender_address_case():
    parsed = parse_email_message(_raw_email(from_addr="Fan Name <FAN@Example.COM>"))

    assert parsed.from_address == "fan@example.com"


def test_ingest_creates_email_thread_and_message(db_session):
    parsed = parse_email_message(_raw_email())

    message = ingest_parsed_email(db_session, parsed)
    db_session.commit()

    assert message is not None
    assert message.sender == SENDER_EXTERNAL_EMAIL
    assert message.external_message_id == "<msg-1@example.com>"
    assert message.external_from == "fan@example.com"
    assert message.external_subject == "Hello label"

    thread = db_session.query(LabelInboxThread).filter_by(id=message.thread_id).one()
    assert thread.source == THREAD_SOURCE_EMAIL
    assert thread.external_from == "fan@example.com"
    assert thread.artist_id is None


def test_ingest_deduplicates_by_message_id(db_session):
    raw = _raw_email(message_id="<dup@example.com>")

    first = ingest_parsed_email(db_session, parse_email_message(raw))
    db_session.commit()
    second = ingest_parsed_email(db_session, parse_email_message(raw))
    db_session.commit()

    assert first is not None
    assert second is None
    assert db_session.query(LabelInboxMessage).count() == 1


def test_ingest_links_thread_to_known_artist(db_session):
    artist = Artist(name="Maya Waves", email="maya@example.com", is_active=True)
    db_session.add(artist)
    db_session.commit()
    db_session.refresh(artist)

    parsed = parse_email_message(_raw_email(from_addr="MAYA@example.com"))
    message = ingest_parsed_email(db_session, parsed)
    db_session.commit()

    thread = db_session.query(LabelInboxThread).filter_by(id=message.thread_id).one()
    assert thread.artist_id == artist.id


def test_ingest_groups_same_sender_into_one_thread(db_session):
    ingest_parsed_email(
        db_session, parse_email_message(_raw_email(message_id="<a@x.com>"))
    )
    db_session.commit()
    ingest_parsed_email(
        db_session, parse_email_message(_raw_email(message_id="<b@x.com>"))
    )
    db_session.commit()

    assert db_session.query(LabelInboxThread).count() == 1
    assert db_session.query(LabelInboxMessage).count() == 2


def test_admin_inbox_lists_email_thread_tagged_as_email(client, db_session, admin_headers):
    ingest_parsed_email(db_session, parse_email_message(_raw_email()))
    db_session.commit()

    response = client.get("/api/admin/inbox", headers=admin_headers)

    assert response.status_code == 200
    threads = response.json()
    assert len(threads) == 1
    thread = threads[0]
    assert thread["source"] == "email"
    assert thread["artist_id"] is None
    assert thread["artist_email"] == "fan@example.com"
    assert thread["subject"] == "Hello label"


def test_artist_portal_does_not_show_email_threads(client, db_session):
    from app.services.auth import create_access_token

    artist = Artist(name="Maya Waves", email="maya@example.com", is_active=True)
    db_session.add(artist)
    db_session.commit()
    db_session.refresh(artist)

    # Email arriving from the artist's own address links artist_id but stays label-only.
    ingest_parsed_email(
        db_session, parse_email_message(_raw_email(from_addr="maya@example.com"))
    )
    db_session.commit()

    token = create_access_token(f"artist:{artist.id}")
    response = client.get(
        "/api/artist/me/inbox", headers={"Authorization": f"Bearer {token}"}
    )

    assert response.status_code == 200
    assert response.json() == []


def test_admin_can_open_artist_less_email_thread(client, db_session, admin_headers):
    message = ingest_parsed_email(db_session, parse_email_message(_raw_email()))
    db_session.commit()
    thread_id = message.thread_id

    response = client.get(f"/api/admin/inbox/threads/{thread_id}", headers=admin_headers)

    assert response.status_code == 200
    detail = response.json()
    assert detail["source"] == "email"
    assert detail["messages"][0]["sender"] == "external_email"
    assert detail["messages"][0]["external_from"] == "fan@example.com"
