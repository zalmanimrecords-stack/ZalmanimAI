"""Tests for demo approval domain service and workflow email behavior."""

from app.models.models import DemoSubmission, PendingRelease
from app.schemas.schemas import DemoSubmissionApproveRequest
from app.services import demo_service
from app.services.workflow_email import WorkflowEmailResult


def test_approve_demo_completes_when_email_fails_non_rate_limit(db_session, monkeypatch):
    item = DemoSubmission(
        artist_name="Test Artist",
        email="approve-fail@example.com",
        status="demo",
        source="test",
    )
    db_session.add(item)
    db_session.commit()
    db_session.refresh(item)

    def fake_send_workflow_email(**_kwargs):
        return WorkflowEmailResult(sent=False, message="SMTP connection refused", purpose="demo_approval")

    monkeypatch.setattr(demo_service, "send_workflow_email", fake_send_workflow_email)

    result = demo_service.approve_demo_submission(
        db_session,
        item,
        DemoSubmissionApproveRequest(send_email=True),
    )
    db_session.commit()

    assert result.submission.status == "approved"
    assert result.email_delivery is not None
    assert result.email_delivery.sent is False
    pr = db_session.query(PendingRelease).filter(PendingRelease.demo_submission_id == item.id).first()
    assert pr is not None
    assert item.approval_email_sent_at is None


def test_approve_demo_endpoint_returns_email_warning(client, db_session, admin_headers, monkeypatch):
    submission = DemoSubmission(
        artist_name="Warn Artist",
        email="warn@example.com",
        status="demo",
        source="test",
    )
    db_session.add(submission)
    db_session.commit()
    db_session.refresh(submission)

    def fake_send_workflow_email(**_kwargs):
        return WorkflowEmailResult(sent=False, message="Mailbox unavailable", purpose="demo_approval")

    monkeypatch.setattr(demo_service, "send_workflow_email", fake_send_workflow_email)

    response = client.post(
        f"/api/admin/demo-submissions/{submission.id}/approve",
        headers=admin_headers,
        json={"send_email": True},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["submission"]["status"] == "approved"
    assert payload["email_warning"] == "Mailbox unavailable"
    assert payload["submission"]["approval_email_sent_at"] is None


def test_resend_approval_email_endpoint(client, db_session, admin_headers, monkeypatch):
    submission = DemoSubmission(
        artist_name="Resend Artist",
        email="resend@example.com",
        status="approved",
        approval_subject="Approved",
        approval_body="Body",
        source="test",
    )
    db_session.add(submission)
    db_session.commit()
    db_session.refresh(submission)

    calls = {"count": 0}

    def fake_send_workflow_email(**_kwargs):
        calls["count"] += 1
        return WorkflowEmailResult(sent=True, message="Sent", purpose="demo_approval")

    monkeypatch.setattr(demo_service, "send_workflow_email", fake_send_workflow_email)

    response = client.post(
        f"/api/admin/demo-submissions/{submission.id}/resend-approval-email",
        headers=admin_headers,
    )
    assert response.status_code == 200
    assert calls["count"] == 1
    assert response.json()["approval_email_sent_at"] is not None
