"""Demo submission intake/review tools."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover
    from mcp.server.fastmcp import FastMCP

    from ..client import ZalmanimClient


def register(mcp: "FastMCP", client: "ZalmanimClient") -> None:
    @mcp.tool()
    def list_demo_submissions(status: str | None = None) -> list[dict[str, Any]]:
        """List incoming demo submissions, optionally filtered by status
        (e.g. new, reviewing, approved, rejected)."""
        return client.get("/admin/demo-submissions", params={"status": status})

    @mcp.tool()
    def get_demo_submission(submission_id: int) -> dict[str, Any]:
        """Get one demo submission, including contact details, links, and notes."""
        return client.get(f"/admin/demo-submissions/{submission_id}")

    @mcp.tool()
    def update_demo_submission(submission_id: int, fields: dict[str, Any]) -> dict[str, Any]:
        """Update a demo submission. Pass only the fields to change.

        Useful keys: status, admin_notes, genre, artist_name, approval_subject,
        approval_body, rejection_subject, rejection_body, send_rejection_email.
        """
        return client.patch(f"/admin/demo-submissions/{submission_id}", json=fields)

    @mcp.tool()
    def approve_demo_submission(
        submission_id: int,
        send_email: bool = True,
        approval_subject: str | None = None,
        approval_body: str | None = None,
    ) -> dict[str, Any]:
        """Approve a demo submission. An artist is created or linked by email.

        Args:
            send_email: Whether to send the approval email to the submitter.
            approval_subject: Override the default approval email subject.
            approval_body: Override the default approval email body.
        """
        payload = {
            "send_email": send_email,
            "approval_subject": approval_subject,
            "approval_body": approval_body,
        }
        return client.post(
            f"/admin/demo-submissions/{submission_id}/approve",
            json={k: v for k, v in payload.items() if v is not None},
        )

    @mcp.tool()
    def delete_demo_submission(submission_id: int) -> dict[str, Any]:
        """Delete a demo submission. This is destructive; confirm before calling."""
        return client.delete(f"/admin/demo-submissions/{submission_id}")
