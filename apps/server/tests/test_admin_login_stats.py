from datetime import datetime, timedelta, timezone

from app.models.models import Artist, User


def test_admin_login_stats_counts_distinct_artists_and_sorts_recent(client, db_session, admin_headers):
    now = datetime.now(timezone.utc)
    within_window = now - timedelta(days=2)
    older_than_window = now - timedelta(days=45)

    portal_artist = Artist(
        name="Portal Artist",
        email="portal@example.com",
        is_active=True,
        last_login_at=within_window,
    )
    overlap_artist = Artist(
        name="Overlap Artist",
        email="overlap@example.com",
        is_active=True,
        last_login_at=within_window - timedelta(minutes=5),
    )
    old_artist = Artist(
        name="Old Artist",
        email="old-artist@example.com",
        is_active=True,
        last_login_at=older_than_window,
    )
    db_session.add_all([portal_artist, overlap_artist, old_artist])
    db_session.flush()

    db_session.add_all(
        [
            User(
                email="manager@example.com",
                full_name="Manager",
                role="manager",
                is_active=True,
                last_login_at=within_window - timedelta(minutes=10),
            ),
            User(
                email="artist-linked@example.com",
                full_name="Artist Linked",
                role="artist",
                artist_id=overlap_artist.id,
                is_active=True,
                last_login_at=within_window - timedelta(minutes=3),
            ),
            User(
                email="artist-unlinked@example.com",
                full_name="Artist Unlinked",
                role="artist",
                artist_id=None,
                is_active=True,
                last_login_at=within_window - timedelta(minutes=1),
            ),
            User(
                email="old-user@example.com",
                full_name="Old User",
                role="manager",
                is_active=True,
                last_login_at=older_than_window,
            ),
        ]
    )
    db_session.commit()

    response = client.get("/api/admin/dashboard/login-stats", headers=admin_headers)
    assert response.status_code == 200

    payload = response.json()
    assert payload["users_logged_in_last_30_days"] == 3
    assert payload["artists_logged_in_last_30_days"] == 3

    recent = payload["recent_logins"]
    assert len(recent) >= 4
    timestamps = [item["last_login_at"] for item in recent]
    assert timestamps == sorted(timestamps, reverse=True)
    assert recent[0]["email"] == "portal@example.com"
    recent_emails = {item["email"] for item in recent}
    assert "artist-unlinked@example.com" in recent_emails
