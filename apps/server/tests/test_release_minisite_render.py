from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace

from starlette.requests import Request

from app.api import routes


def _request() -> Request:
    scope = {
        "type": "http",
        "method": "GET",
        "path": "/",
        "headers": [],
        "scheme": "http",
        "server": ("testserver", 80),
        "client": ("127.0.0.1", 12345),
    }
    return Request(scope)


def test_release_minisite_html_renders_core_sections():
    release = SimpleNamespace(
        id=42,
        title="Afterglow EP",
        artists=[SimpleNamespace(name="Aurora Echo"), SimpleNamespace(name="Night Bloom")],
        artist=None,
        created_at=datetime(2026, 4, 6, tzinfo=timezone.utc),
        cover_image_path="/tmp/cover.jpg",
        platform_links_json='{"spotify":"https://open.spotify.com/album/abc"}',
        link_candidates=[],
    )
    config = {
        "theme": "sunset_poster",
        "description": "Late night grooves.",
        "download_url": "https://example.com/download",
        "gallery_urls": ["https://cdn.example.com/alt1.jpg"],
    }

    html_out = routes._release_minisite_html(_request(), release, config)

    assert "Afterglow EP" in html_out
    assert "Aurora Echo, Night Bloom" in html_out
    assert "Theme: sunset_poster" in html_out
    assert "Download Release" in html_out
    assert "https://open.spotify.com/album/abc" in html_out
    assert "Late night grooves." in html_out
    assert "Created 2026-04-06" in html_out


def test_release_minisite_html_escapes_untrusted_content():
    release = SimpleNamespace(
        id=7,
        title='Bad <script>alert(1)</script> Title',
        artists=[],
        artist=SimpleNamespace(name='Name <b>Unsafe</b>', extra_json='{"website":"unsafe.example.com"}'),
        created_at=None,
        cover_image_path=None,
        platform_links_json="{}",
        link_candidates=[],
    )
    config = {
        "description": '<img src=x onerror=alert(1)>',
        "gallery_urls": [],
    }

    html_out = routes._release_minisite_html(_request(), release, config)

    assert "<script>alert(1)</script>" not in html_out
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in html_out
    assert "&lt;img src=x onerror=alert(1)&gt;" in html_out
    assert "https://unsafe.example.com" in html_out
