from app.models.models import Artist, LabelInboxMessage, LabelInboxThread
from app.services.auth import create_access_token


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


def test_artist_can_send_and_list_own_inbox_threads(client, db_session):
    artist = Artist(name="Maya Waves", email="maya@example.com", is_active=True)
    db_session.add(artist)
    db_session.commit()
    db_session.refresh(artist)
    artist_headers = {"Authorization": f"Bearer {create_access_token(f'artist:{artist.id}')}"}

    send_response = client.post(
        "/api/artist/me/inbox",
        headers=artist_headers,
        json={"body": "Hello label"},
    )

    assert send_response.status_code == 200
    send_payload = send_response.json()
    assert send_payload["artist_id"] == artist.id
    assert send_payload["message_count"] == 1
    assert send_payload["messages"][0]["body"] == "Hello label"

    list_response = client.get("/api/artist/me/inbox", headers=artist_headers)

    assert list_response.status_code == 200
    threads = list_response.json()
    assert len(threads) == 1
    assert threads[0]["artist_id"] == artist.id
    assert threads[0]["unread_count"] == 1


def test_artist_can_open_only_own_inbox_thread(client, db_session):
    artist = Artist(name="Maya Waves", email="maya@example.com", is_active=True)
    other_artist = Artist(name="Noa Tide", email="noa@example.com", is_active=True)
    db_session.add_all([artist, other_artist])
    db_session.commit()
    db_session.refresh(artist)
    db_session.refresh(other_artist)

    thread = LabelInboxThread(artist_id=other_artist.id)
    db_session.add(thread)
    db_session.commit()
    db_session.refresh(thread)

    db_session.add(
        LabelInboxMessage(
            thread_id=thread.id,
            sender="artist",
            body="Private thread",
            admin_read_at=None,
        )
    )
    db_session.commit()

    artist_headers = {"Authorization": f"Bearer {create_access_token(f'artist:{artist.id}')}"}
    response = client.get(f"/api/artist/me/inbox/threads/{thread.id}", headers=artist_headers)

    assert response.status_code == 404
    assert response.json()["detail"] == "Thread not found"
