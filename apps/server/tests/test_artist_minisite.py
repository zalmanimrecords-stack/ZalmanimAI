import json
from pathlib import Path

from app.models.models import Artist, ArtistMedia
from app.services.auth import create_access_token


def test_artist_can_update_and_publish_minisite(client, db_session):
    existing_file = Path(__file__).resolve()
    artist = Artist(
        name="Aurora Echo",
        email="aurora@example.com",
        notes="Internal note",
        is_active=True,
        extra_json="{}",
    )
    db_session.add(artist)
    db_session.flush()

    profile_media = ArtistMedia(
        artist_id=artist.id,
        filename="profile.png",
        stored_path=str(existing_file),
        content_type="image/png",
        size_bytes=existing_file.stat().st_size,
    )
    gallery_media = ArtistMedia(
        artist_id=artist.id,
        filename="gallery.jpg",
        stored_path=str(existing_file),
        content_type="image/jpeg",
        size_bytes=existing_file.stat().st_size,
    )
    db_session.add_all([profile_media, gallery_media])
    db_session.commit()
    db_session.refresh(artist)
    db_session.refresh(profile_media)
    db_session.refresh(gallery_media)

    artist_headers = {
        "Authorization": f"Bearer {create_access_token(f'artist:{artist.id}')}"
    }
    response = client.patch(
        "/api/artist/me",
        headers=artist_headers,
        json={
            "minisite_headline": "Melodic house and late night emotion",
            "minisite_bio": "Aurora Echo builds cinematic club records for sunrise sets.",
            "minisite_theme": "sunset",
            "minisite_is_public": True,
            "profile_image_media_id": profile_media.id,
            "minisite_gallery_media_ids": [gallery_media.id],
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["extra"]["minisite_theme"] == "sunset"
    assert data["extra"]["minisite_gallery_media_ids"] == [gallery_media.id]

    public_response = client.get(f"/api/public/linktree/{artist.id}")
    assert public_response.status_code == 200
    public_data = public_response.json()
    assert public_data["headline"] == "Melodic house and late night emotion"
    assert public_data["bio"] == "Aurora Echo builds cinematic club records for sunrise sets."
    assert public_data["theme"] == "sunset"
    assert public_data["profile_image_url"].endswith(
        f"/api/public/artist/{artist.id}/profile-image"
    )
    assert public_data["gallery_image_urls"] == [
        f"http://testserver/api/public/artist/{artist.id}/media/{gallery_media.id}"
    ]


def test_public_artist_media_only_serves_selected_minisite_images(client, db_session):
    existing_file = Path(__file__).resolve()
    artist = Artist(
        name="Night Bloom",
        email="night@example.com",
        notes="",
        is_active=True,
        extra_json="{}",
    )
    db_session.add(artist)
    db_session.flush()

    public_media = ArtistMedia(
        artist_id=artist.id,
        filename="public.png",
        stored_path=str(existing_file),
        content_type="image/png",
        size_bytes=existing_file.stat().st_size,
    )
    private_media = ArtistMedia(
        artist_id=artist.id,
        filename="private.png",
        stored_path=str(existing_file),
        content_type="image/png",
        size_bytes=existing_file.stat().st_size,
    )
    db_session.add_all([public_media, private_media])
    db_session.flush()

    artist.extra_json = json.dumps(
        {
            "minisite_is_public": True,
            "minisite_gallery_media_ids": [public_media.id],
        }
    )
    db_session.commit()

    assert client.get(
        f"/api/public/artist/{artist.id}/media/{public_media.id}"
    ).status_code == 200
    assert client.get(
        f"/api/public/artist/{artist.id}/media/{private_media.id}"
    ).status_code == 404
