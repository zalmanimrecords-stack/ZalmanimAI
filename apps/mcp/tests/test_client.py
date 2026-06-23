"""Tests for the authenticated Zalmanim API client."""

from __future__ import annotations

import httpx
import pytest

from zalmanim_mcp.client import ZalmanimApiError, ZalmanimClient
from zalmanim_mcp.config import Config


def _config(**overrides) -> Config:
    base = {"base_url": "http://testserver", "email": "admin@example.com", "password": "secret", "timeout": 5.0}
    base.update(overrides)
    return Config(**base)


def _client(handler, **config_overrides) -> ZalmanimClient:
    transport = httpx.MockTransport(handler)
    return ZalmanimClient(_config(**config_overrides), transport=transport)


def test_login_caches_token_and_authorizes_requests():
    seen_headers: list[str | None] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/auth/login":
            return httpx.Response(200, json={"access_token": "tok-123", "role": "admin", "email": "a"})
        seen_headers.append(request.headers.get("authorization"))
        return httpx.Response(200, json=[{"id": 1}])

    client = _client(handler)
    result = client.get("/artists")

    assert result == [{"id": 1}]
    assert seen_headers == ["Bearer tok-123"]


def test_missing_credentials_raises_clear_error():
    def handler(request: httpx.Request) -> httpx.Response:  # pragma: no cover - never called
        return httpx.Response(200, json={})

    client = _client(handler, email="", password="")
    with pytest.raises(ZalmanimApiError) as exc:
        client.get("/artists")
    assert "Missing credentials" in str(exc.value)


def test_reauthenticates_once_on_401():
    calls = {"login": 0, "artists": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/auth/login":
            calls["login"] += 1
            return httpx.Response(200, json={"access_token": f"tok-{calls['login']}"})
        calls["artists"] += 1
        # First protected call returns 401, second (after re-login) succeeds.
        if calls["artists"] == 1:
            return httpx.Response(401, json={"detail": "expired"})
        return httpx.Response(200, json={"ok": True})

    client = _client(handler)
    assert client.get("/artists") == {"ok": True}
    assert calls["login"] == 2
    assert calls["artists"] == 2


def test_api_error_surfaces_detail():
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/auth/login":
            return httpx.Response(200, json={"access_token": "tok"})
        return httpx.Response(404, json={"detail": "Artist not found"})

    client = _client(handler)
    with pytest.raises(ZalmanimApiError) as exc:
        client.get("/artists/999")
    assert exc.value.status_code == 404
    assert "Artist not found" in str(exc.value)


def test_login_failure_raises():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"detail": "Invalid credentials"})

    client = _client(handler)
    with pytest.raises(ZalmanimApiError) as exc:
        client.get("/artists")
    assert exc.value.status_code == 401
    assert "Invalid credentials" in str(exc.value)


def test_204_returns_ok_status():
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/auth/login":
            return httpx.Response(200, json={"access_token": "tok"})
        return httpx.Response(204)

    client = _client(handler)
    assert client.delete("/artists/1") == {"status": "ok", "status_code": 204}


def test_none_params_are_dropped():
    captured: dict[str, str] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/auth/login":
            return httpx.Response(200, json={"access_token": "tok"})
        captured.update(dict(request.url.params))
        return httpx.Response(200, json=[])

    client = _client(handler)
    client.get("/artists", params={"search": None, "limit": 50, "include_inactive": False})
    assert "search" not in captured
    assert captured["limit"] == "50"


@pytest.mark.parametrize(
    "path,expected",
    [
        ("/artists", "/api/artists"),
        ("artists", "/api/artists"),
        ("/api/admin/campaigns", "/api/admin/campaigns"),
        ("/health", "/health"),
    ],
)
def test_path_normalization(path, expected):
    assert ZalmanimClient._normalize_path(path) == expected


def test_transport_error_wrapped():
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/auth/login":
            return httpx.Response(200, json={"access_token": "tok"})
        raise httpx.ConnectError("connection refused")

    client = _client(handler)
    with pytest.raises(ZalmanimApiError) as exc:
        client.get("/artists")
    assert exc.value.status_code == 0
    assert "connection refused" in str(exc.value)
