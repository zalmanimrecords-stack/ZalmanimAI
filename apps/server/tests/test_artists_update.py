from app.models.models import Artist


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
