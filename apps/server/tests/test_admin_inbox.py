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
