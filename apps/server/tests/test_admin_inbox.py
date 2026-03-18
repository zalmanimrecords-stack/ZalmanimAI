from app.models.models import Artist, LabelInboxMessage, LabelInboxThread


def test_admin_can_delete_inbox_thread_and_messages(client, db_session, admin_headers):
    artist = Artist(name="Maya Waves", email="maya@example.com", is_active=True)
    db_session.add(artist)
    db_session.commit()
    db_session.refresh(artist)

    thread = LabelInboxThread(artist_id=artist.id)
    db_session.add(thread)
    db_session.commit()
    db_session.refresh(thread)

    db_session.add_all(
        [
            LabelInboxMessage(thread_id=thread.id, sender="artist", body="First message"),
            LabelInboxMessage(thread_id=thread.id, sender="label", body="Reply message"),
        ]
    )
    db_session.commit()
    thread_id = thread.id

    response = client.delete(f"/api/admin/inbox/threads/{thread_id}", headers=admin_headers)

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    db_session.expire_all()
    assert db_session.query(LabelInboxThread).filter(LabelInboxThread.id == thread_id).count() == 0
    assert db_session.query(LabelInboxMessage).filter(LabelInboxMessage.thread_id == thread_id).count() == 0


def test_admin_inbox_marks_artist_messages_read_when_thread_is_opened(
    client,
    db_session,
    admin_headers,
):
    artist = Artist(name="Maya Waves", email="maya@example.com", is_active=True)
    db_session.add(artist)
    db_session.commit()
    db_session.refresh(artist)

    thread = LabelInboxThread(artist_id=artist.id)
    db_session.add(thread)
    db_session.commit()
    db_session.refresh(thread)

    db_session.add_all(
        [
            LabelInboxMessage(
                thread_id=thread.id,
                sender="artist",
                body="First unread message",
                admin_read_at=None,
            ),
            LabelInboxMessage(
                thread_id=thread.id,
                sender="artist",
                body="Second unread message",
                admin_read_at=None,
            ),
            LabelInboxMessage(
                thread_id=thread.id,
                sender="label",
                body="Reply message",
            ),
        ]
    )
    db_session.commit()

    inbox_response = client.get("/api/admin/inbox", headers=admin_headers)

    assert inbox_response.status_code == 200
    inbox_payload = inbox_response.json()
    assert len(inbox_payload) == 1
    assert inbox_payload[0]["unread_count"] == 2

    thread_response = client.get(
        f"/api/admin/inbox/threads/{thread.id}",
        headers=admin_headers,
    )

    assert thread_response.status_code == 200
    thread_payload = thread_response.json()
    assert thread_payload["unread_count"] == 0
    assert all(
        message["admin_read_at"] is not None
        for message in thread_payload["messages"]
        if message["sender"] == "artist"
    )

    db_session.expire_all()
    artist_messages = (
        db_session.query(LabelInboxMessage)
        .filter(
            LabelInboxMessage.thread_id == thread.id,
            LabelInboxMessage.sender == "artist",
        )
        .all()
    )
    assert len(artist_messages) == 2
    assert all(message.admin_read_at is not None for message in artist_messages)
