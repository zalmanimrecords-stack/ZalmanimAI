"""Manager role can access campaigns but not admin-only user management writes."""

from app.models.models import User
from app.services.auth import create_access_token


def _manager_headers(db_session):
    manager = User(
        email="manager@example.com",
        full_name="Manager",
        role="manager",
        is_active=True,
    )
    db_session.add(manager)
    db_session.commit()
    token = create_access_token(str(manager.id))
    return {"Authorization": f"Bearer {token}"}


def test_manager_can_list_campaigns(client, db_session):
    headers = _manager_headers(db_session)
    response = client.get("/api/admin/campaigns", headers=headers)
    assert response.status_code == 200


def test_manager_can_list_releases(client, db_session):
    headers = _manager_headers(db_session)
    response = client.get("/api/admin/releases", headers=headers)
    assert response.status_code == 200


def test_manager_can_read_settings(client, db_session):
    headers = _manager_headers(db_session)
    response = client.get("/api/admin/settings", headers=headers)
    assert response.status_code == 200


def test_manager_cannot_patch_mail_settings(client, db_session):
    headers = _manager_headers(db_session)
    response = client.patch(
        "/api/admin/settings/mail",
        headers=headers,
        json={"smtp_host": "smtp.example.com", "smtp_port": 587, "smtp_from_email": "a@b.com"},
    )
    assert response.status_code == 403


def test_manager_cannot_create_user(client, db_session, admin_headers):
    headers = _manager_headers(db_session)
    response = client.post(
        "/api/admin/users",
        headers=headers,
        json={
            "email": "newuser@example.com",
            "full_name": "New",
            "role": "manager",
            "password": "Password123!",
        },
    )
    assert response.status_code == 403
