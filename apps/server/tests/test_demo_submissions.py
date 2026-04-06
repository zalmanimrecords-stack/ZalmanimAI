from app.api import routes
from app.models.models import DemoSubmission


def test_reject_demo_allows_custom_email_before_sending(
    client,
    db_session,
    admin_headers,
    monkeypatch,
):
    sent_payload = {}

    def fake_send_email_service(*, to_email, subject, body_text, body_html=None):
        sent_payload["to_email"] = to_email
        sent_payload["subject"] = subject
        sent_payload["body_text"] = body_text
        sent_payload["body_html"] = body_html
        return True, "Sent"

    monkeypatch.setattr(routes, "send_email_service", fake_send_email_service)
    monkeypatch.setattr(routes, "is_email_configured", lambda: True)

    submission = DemoSubmission(
        artist_name="Maya Waves",
        email="maya@example.com",
        status="demo",
        source="wordpress_demo_form",
    )
    db_session.add(submission)
    db_session.commit()
    db_session.refresh(submission)

    response = client.patch(
        f"/api/admin/demo-submissions/{submission.id}",
        headers=admin_headers,
        json={
            "status": "rejected",
            "rejection_subject": "Feedback for {artist_name}",
            "rejection_body": "Hi {artist_name}, please keep sharing music via {artist_portal_url}.",
            "send_rejection_email": True,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "rejected"
    assert payload["rejection_email_sent_at"] is not None
    assert payload["rejection_subject"] == "Thank you for your demo submission, Maya Waves"
    assert sent_payload["to_email"] == "maya@example.com"
    assert sent_payload["subject"] == "Feedback for Maya Waves"
    assert "Hi Maya Waves" in sent_payload["body_text"]
    assert "{artist_portal_url}" not in sent_payload["body_text"]


def test_reject_demo_can_skip_email_send(
    client,
    db_session,
    admin_headers,
    monkeypatch,
):
    send_calls = {"count": 0}

    def fake_send_email_service(*, to_email, subject, body_text, body_html=None):
        send_calls["count"] += 1
        return True, "Sent"

    monkeypatch.setattr(routes, "send_email_service", fake_send_email_service)
    monkeypatch.setattr(routes, "is_email_configured", lambda: True)

    submission = DemoSubmission(
        artist_name="Noa Lights",
        email="noa@example.com",
        status="demo",
        source="wordpress_demo_form",
    )
    db_session.add(submission)
    db_session.commit()
    db_session.refresh(submission)

    response = client.patch(
        f"/api/admin/demo-submissions/{submission.id}",
        headers=admin_headers,
        json={
            "status": "rejected",
            "send_rejection_email": False,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "rejected"
    assert payload["rejection_email_sent_at"] is None
    assert send_calls["count"] == 0


def test_reject_demo_without_email_configuration_does_not_send(
    client,
    db_session,
    admin_headers,
    monkeypatch,
):
    send_calls = {"count": 0}

    def fake_send_email_service(*, to_email, subject, body_text, body_html=None):
        send_calls["count"] += 1
        return True, "Sent"

    monkeypatch.setattr(routes, "send_email_service", fake_send_email_service)
    monkeypatch.setattr(routes, "is_email_configured", lambda: False)

    submission = DemoSubmission(
        artist_name="Ariel North",
        email="ariel@example.com",
        status="demo",
        source="wordpress_demo_form",
    )
    db_session.add(submission)
    db_session.commit()
    db_session.refresh(submission)

    response = client.patch(
        f"/api/admin/demo-submissions/{submission.id}",
        headers=admin_headers,
        json={"status": "rejected"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "rejected"
    assert payload["rejection_email_sent_at"] is None
    assert send_calls["count"] == 0


def test_reject_demo_email_limit_error_maps_to_429(
    client,
    db_session,
    admin_headers,
    monkeypatch,
):
    def fake_send_email_service(*, to_email, subject, body_text, body_html=None):
        return False, "Rate limit exceeded"

    monkeypatch.setattr(routes, "send_email_service", fake_send_email_service)
    monkeypatch.setattr(routes, "is_email_configured", lambda: True)

    submission = DemoSubmission(
        artist_name="Lior Sky",
        email="lior@example.com",
        status="demo",
        source="wordpress_demo_form",
    )
    db_session.add(submission)
    db_session.commit()
    db_session.refresh(submission)

    response = client.patch(
        f"/api/admin/demo-submissions/{submission.id}",
        headers=admin_headers,
        json={"status": "rejected"},
    )

    assert response.status_code == 429
    assert response.json()["detail"] == "Rate limit exceeded"
