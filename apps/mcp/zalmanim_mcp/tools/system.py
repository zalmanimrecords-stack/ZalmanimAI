"""System / dashboard / diagnostics tools."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover
    from mcp.server.fastmcp import FastMCP

    from ..client import ZalmanimClient


def register(mcp: "FastMCP", client: "ZalmanimClient") -> None:
    @mcp.tool()
    def health() -> dict[str, Any]:
        """Check that the backend is up (GET /health). Does not require auth."""
        return client.get("/health")

    @mcp.tool()
    def whoami() -> dict[str, Any]:
        """Return the currently authenticated admin user (GET /api/auth/me)."""
        return client.get("/auth/me")

    @mcp.tool()
    def dashboard_stats() -> dict[str, Any]:
        """Get headline counts for the admin dashboard (active artists, total releases)."""
        return client.get("/admin/dashboard/stats")

    @mcp.tool()
    def login_stats() -> dict[str, Any]:
        """Get login activity stats: users/artists active in the last 30 days and recent logins."""
        return client.get("/admin/dashboard/login-stats")

    @mcp.tool()
    def list_system_logs(limit: int = 100) -> list[dict[str, Any]]:
        """List recent system log entries (errors, mail, auth, api)."""
        return client.get("/admin/logs", params={"limit": limit})

    @mcp.tool()
    def list_db_tables() -> Any:
        """List database table names (admin diagnostics)."""
        return client.get("/admin/db/tables")

    @mcp.tool()
    def get_db_table(table_name: str) -> Any:
        """Read rows from a database table by name (admin diagnostics, read-only)."""
        return client.get(f"/admin/db/tables/{table_name}")

    @mcp.tool()
    def run_inactivity_check() -> dict[str, Any]:
        """Run the artist-inactivity check task on demand."""
        return client.post("/admin/tasks/run-inactivity-check")
