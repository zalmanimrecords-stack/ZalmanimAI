"""Authenticated HTTP client for the Zalmanim AI (LabelOps) backend.

Handles JWT login against ``POST /api/auth/login``, attaches the bearer token to
every request, and transparently re-authenticates once on a 401 (e.g. when the
token has expired between calls). All API errors are surfaced as
:class:`ZalmanimApiError` with the server-provided detail so the model gets a
clear, actionable message instead of a raw stack trace.
"""

from __future__ import annotations

import logging
from typing import Any

import httpx

from .config import Config

logger = logging.getLogger("zalmanim_mcp.client")

# Paths that are served at the server root rather than under the /api router.
_ROOT_PATHS = ("/health", "/")


class ZalmanimApiError(RuntimeError):
    """Raised when the backend returns an error or is unreachable."""

    def __init__(self, status_code: int, detail: str, method: str, path: str) -> None:
        self.status_code = status_code
        self.detail = detail
        self.method = method
        self.path = path
        location = f"{method} {path}"
        if status_code:
            super().__init__(f"Zalmanim API {status_code} on {location}: {detail}")
        else:
            super().__init__(f"Zalmanim API request failed on {location}: {detail}")


class ZalmanimClient:
    """Thin synchronous wrapper around the backend admin API."""

    def __init__(self, config: Config, *, transport: httpx.BaseTransport | None = None) -> None:
        self._config = config
        self._token: str | None = None
        self._http = httpx.Client(
            base_url=config.base_url,
            timeout=config.timeout,
            transport=transport,
            headers={"Accept": "application/json"},
        )

    def close(self) -> None:
        self._http.close()

    # -- auth -----------------------------------------------------------------

    def login(self) -> str:
        """Authenticate and cache a bearer token. Returns the token."""
        if not self._config.has_credentials():
            raise ZalmanimApiError(
                0,
                "Missing credentials. Set ZALMANIM_ADMIN_EMAIL and ZALMANIM_ADMIN_PASSWORD "
                "(env or apps/mcp/.env).",
                "POST",
                "/api/auth/login",
            )
        try:
            resp = self._http.post(
                "/api/auth/login",
                json={"email": self._config.email, "password": self._config.password},
            )
        except httpx.HTTPError as exc:
            logger.error("Login transport error: %s", exc)
            raise ZalmanimApiError(0, str(exc), "POST", "/api/auth/login") from exc
        if resp.status_code >= 400:
            detail = self._error_detail(resp)
            logger.warning("Login failed (%s): %s", resp.status_code, detail)
            raise ZalmanimApiError(resp.status_code, detail, "POST", "/api/auth/login")
        token = (resp.json() or {}).get("access_token")
        if not token:
            raise ZalmanimApiError(resp.status_code, "Login response missing access_token", "POST", "/api/auth/login")
        self._token = token
        logger.info("Authenticated as %s", self._config.email)
        return token

    def _auth_headers(self) -> dict[str, str]:
        if not self._token:
            self.login()
        return {"Authorization": f"Bearer {self._token}"}

    # -- requests -------------------------------------------------------------

    def request(
        self,
        method: str,
        path: str,
        *,
        json: Any | None = None,
        params: dict[str, Any] | None = None,
    ) -> Any:
        """Perform an authenticated request and return the parsed body.

        Re-authenticates once on a 401. Raises :class:`ZalmanimApiError` on any
        4xx/5xx response or transport failure.
        """
        normalized = self._normalize_path(path)
        clean_params = {k: v for k, v in (params or {}).items() if v is not None}
        try:
            resp = self._http.request(
                method, normalized, json=json, params=clean_params or None, headers=self._auth_headers()
            )
            if resp.status_code == 401:
                logger.info("Token rejected; re-authenticating once.")
                self._token = None
                resp = self._http.request(
                    method, normalized, json=json, params=clean_params or None, headers=self._auth_headers()
                )
        except httpx.HTTPError as exc:
            logger.error("Transport error on %s %s: %s", method, normalized, exc)
            raise ZalmanimApiError(0, str(exc), method, normalized) from exc

        if resp.status_code >= 400:
            detail = self._error_detail(resp)
            logger.warning("API error %s on %s %s: %s", resp.status_code, method, normalized, detail)
            raise ZalmanimApiError(resp.status_code, detail, method, normalized)
        return self._parse(resp)

    def get(self, path: str, *, params: dict[str, Any] | None = None) -> Any:
        return self.request("GET", path, params=params)

    def post(self, path: str, *, json: Any | None = None, params: dict[str, Any] | None = None) -> Any:
        return self.request("POST", path, json=json, params=params)

    def patch(self, path: str, *, json: Any | None = None) -> Any:
        return self.request("PATCH", path, json=json)

    def delete(self, path: str) -> Any:
        return self.request("DELETE", path)

    # -- helpers --------------------------------------------------------------

    @staticmethod
    def _normalize_path(path: str) -> str:
        p = path if path.startswith("/") else "/" + path
        if p in _ROOT_PATHS or p.startswith("/api/") or p.startswith("/api?"):
            return p
        return "/api" + p

    @staticmethod
    def _error_detail(resp: httpx.Response) -> str:
        try:
            body = resp.json()
        except ValueError:
            return (resp.text or "").strip()[:500] or resp.reason_phrase
        if isinstance(body, dict) and "detail" in body:
            return str(body["detail"])[:500]
        return str(body)[:500]

    @staticmethod
    def _parse(resp: httpx.Response) -> Any:
        if resp.status_code == 204 or not resp.content:
            return {"status": "ok", "status_code": resp.status_code}
        content_type = (resp.headers.get("content-type") or "").lower()
        if "application/json" in content_type:
            return resp.json()
        return {"status_code": resp.status_code, "text": resp.text}
