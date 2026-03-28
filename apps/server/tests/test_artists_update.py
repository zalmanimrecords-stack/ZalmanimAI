from app.models.models import Artist, ArtistMedia


def test_admin_can_update_artist_with_put(client, db_session, admin_headers):
    artist = Artist(
        name="Before Name",
        email="before@example.com",
        notes="before",
        is_active=True,
        extra_json="{}",
    )
    db_session.add(artist)
    db_session.commit()
    db_session.refresh(artist)

    response = client.put(
        f"/api/artists/{artist.id}",
        headers=admin_headers,
        json={
            "name": "After Name",
            "email": "after@example.com",
            "notes": "after",
            "artist_brand": "After Brand",
            "is_active": False,
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "After Name"
    assert data["email"] == "after@example.com"
    assert data["notes"] == "after"
    assert data["is_active"] is False
    assert data["extra"]["artist_brand"] == "After Brand"


def test_admin_update_artist_duplicate_email_returns_409(client, db_session, admin_headers):
    a1 = Artist(
        name="First",
        email="first@example.com",
        notes="",
        is_active=True,
        extra_json="{}",
    )
    a2 = Artist(
        name="Second",
        email="second@example.com",
        notes="",
        is_active=True,
        extra_json="{}",
    )
    db_session.add_all([a1, a2])
    db_session.commit()
    db_session.refresh(a1)
    db_session.refresh(a2)

    response = client.put(
        f"/api/artists/{a1.id}",
        headers=admin_headers,
        json={"email": "second@example.com"},
    )
    assert response.status_code == 409
    d = response.json()["detail"]
    assert isinstance(d, dict)
    assert d.get("suggest_merge") is True
    assert d.get("existing_artist_id") == a2.id
    assert d.get("editing_artist_id") == a1.id


def test_admin_create_artist_duplicate_email_returns_409(client, db_session, admin_headers):
    existing = Artist(
        name="Existing",
        email="taken@example.com",
        notes="",
        is_active=True,
        extra_json="{}",
    )
    db_session.add(existing)
    db_session.commit()

    response = client.post(
        "/api/artists",
        headers=admin_headers,
        json={
            "name": "New Artist",
            "email": "taken@example.com",
            "notes": "",
        },
    )
    assert response.status_code == 409
    d = response.json()["detail"]
    assert isinstance(d, dict)
    assert d.get("suggest_merge") is False
    assert d.get("existing_artist_id") == existing.id
    assert "editing_artist_id" not in d


def test_admin_can_update_artist_with_profile_image_reference(client, db_session, admin_headers):
    artist = Artist(
        name="Before Name",
        email="before@example.com",
        notes="before",
        is_active=True,
        extra_json="{}",
    )
    db_session.add(artist)
    db_session.flush()

    media = ArtistMedia(
        artist_id=artist.id,
        filename="avatar.png",
        stored_path="storage/uploads/avatar.png",
        content_type="image/png",
        size_bytes=123,
    )
    db_session.add(media)
    db_session.commit()
    db_session.refresh(artist)
    db_session.refresh(media)

    response = client.put(
        f"/api/artists/{artist.id}",
        headers=admin_headers,
        json={"profile_image_media_id": media.id},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["extra"]["profile_image_media_id"] == media.id
