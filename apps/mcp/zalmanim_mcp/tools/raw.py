"""Generic escape hatch for any backend endpoint not covered by a typed tool."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover
    from mcp.server.fastmcp import FastMCP

    from ..client import ZalmanimClient

_ALLOWED_METHODS = {"GET", "POST", "PATCH", "PUT", "DELETE"}


def register(mcp: "FastMCP", client: "ZalmanimClient") -> None:
    @mcp.tool()
    def api_request(
        method: str,
        path: str,
        json_body: dict[str, Any] | None = None,
        params: dict[str, Any] | None = None,
    ) -> Any:
        """Call any Zalmanim AI endpoint directly. Use this for endpoints that
        don't have a dedicated tool yet.

        Args:
            method: HTTP method (GET, POST, PATCH, PUT, DELETE).
            path: Endpoint path. A bare path like "/artists" is sent under the
                "/api" prefix; pass "/health" for the root health check.
            json_body: Optional JSON request body.
            params: Optional query parameters.
        """
        verb = method.strip().upper()
        if verb not in _ALLOWED_METHODS:
            raise ValueError(f"Unsupported method '{method}'. Use one of: {', '.join(sorted(_ALLOWED_METHODS))}.")
        return client.request(verb, path, json=json_body, params=params)
