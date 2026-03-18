from app.models.models import Artist, ArtistRegistrationToken


def test_admin_can_send_groover_invite_and_create_artist(client, db_session, admin_headers, monkeypatch):
    sent_payload = {}

    def _fake_send_email(**kwargs):
        sent_payload.update(kwargs)
        return True, "Sent"

    monkeypatch.setattr("app.api.routes.send_email_service", _fake_send_email)

    response = client.post(
        "/api/admin/artists/send-groover-invite",
        headers=admin_headers,
        json={
            "email": "groover@example.com",
            "artist_name": "Groover Waves",
            "full_name": "Maya Cohen",
            "notes": "Source: Groover",
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "groover@example.com"
    assert data["created_artist"] is True
    assert "artist-registration?token=" in data["registration_url"]

    artist = db_session.query(Artist).filter(Artist.email == "groover@example.com").first()
    assert artist is not None
    token = db_session.query(ArtistRegistrationToken).filter(ArtistRegistrationToken.artist_id == artist.id).first()
    assert token is not None
    assert token.source == "groover"
    assert 'color:#c62828' in (sent_payload.get("body_html") or "")
    assert 'Complete your artist registration form' in (sent_payload.get("body_html") or "")
    assert 'href="https://artists.zalmanim.com/#/artist-registration?token=' in (sent_payload.get("body_html") or "")


def test_public_artist_registration_completes_profile_and_password(client, db_session):
    artist = Artist(
        name="Groover Waves",
        email="groover@example.com",
        notes="Source: Groover",
        is_active=True,
    )
    db_session.add(artist)
    db_session.flush()

    raw_token = "groover-token"
    import hashlib
    from datetime import datetime, timedelta, timezone

    token = ArtistRegistrationToken(
        artist_id=artist.id,
        email=artist.email,
        source="groover",
        token_hash=hashlib.sha256(raw_token.encode()).hexdigest(),
        expires_at=datetime.now(timezone.utc) + timedelta(days=1),
    )
    db_session.add(token)
    db_session.commit()

    info_response = client.get(
        "/api/public/artist-registration",
        params={"token": raw_token},
    )
    assert info_response.status_code == 200
    assert info_response.json()["email"] == "groover@example.com"

    submit_response = client.post(
        "/api/public/artist-registration",
        json={
            "token": raw_token,
            "artist_name": "Groover Waves",
            "full_name": "Maya Cohen",
            "soundcloud": "https://soundcloud.com/groover-waves",
            "instagram": "https://instagram.com/grooverwaves",
            "password": "Strong123",
        },
    )

    assert submit_response.status_code == 200
    db_session.refresh(artist)
    db_session.refresh(token)
    assert artist.password_hash is not None
    assert token.used_at is not None
    assert "Maya Cohen" in (artist.extra_json or "")
