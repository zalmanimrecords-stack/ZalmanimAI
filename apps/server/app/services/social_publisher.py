"""Publish campaign content to social providers (Meta/Facebook/Instagram, etc.)."""

from typing import Any

import httpx

from app.models.models import SocialConnection


def publish_social(
    connection: SocialConnection,
    *,
    text: str,
    media_url: str | None = None,
) -> tuple[bool, str, str | None]:
    """
    Publish text (and optional media) to the given social connection.
    Returns (success, message, external_id e.g. post id).
    """
    provider = (connection.provider or "").strip().lower()
    token = (connection.access_token or "").strip()
    if not token:
        return False, "Connection has no access token.", None
    if not text:
        return False, "Content text is required.", None

    if provider == "facebook_page":
        return _publish_facebook_page(connection, text=text, media_url=media_url)
    if provider == "instagram_business":
        return _publish_instagram_business(connection, text=text, media_url=media_url)
    if provider == "threads":
        return _publish_threads(connection, text=text, media_url=media_url)
    # Placeholders for other providers
    return False, f"Publishing not yet implemented for provider: {provider}", None


def _get_meta_page_token(connection: SocialConnection) -> tuple[str, str] | None:
    """Get (page_id, page_access_token) using connection's user access_token. Returns None on failure."""
    token = (connection.access_token or "").strip()
    if not token:
        return None
    try:
        r = httpx.get(
            "https://graph.facebook.com/v22.0/me/accounts",
            params={"access_token": token},
            timeout=15.0,
        )
        if r.status_code != 200:
            return None
        data = r.json()
        pages = data.get("data") or []
        if not pages:
            return None
        page = pages[0]
        return page.get("id"), page.get("access_token", "")
    except Exception:
        return None


def _publish_facebook_page(
    connection: SocialConnection,
    *,
    text: str,
    media_url: str | None = None,
) -> tuple[bool, str, str | None]:
    """Post to Facebook Page feed. Uses page token from /me/accounts if needed."""
    page_info = _get_meta_page_token(connection)
    if not page_info:
        return False, "Could not get Facebook Page token (check /me/accounts).", None
    page_id, page_token = page_info
    try:
        if media_url:
            # Create photo post with message
            r = httpx.post(
                f"https://graph.facebook.com/v22.0/{page_id}/photos",
                params={
                    "access_token": page_token,
                    "url": media_url,
                    "message": text,
                },
                timeout=30.0,
            )
        else:
            r = httpx.post(
                f"https://graph.facebook.com/v22.0/{page_id}/feed",
                params={
                    "access_token": page_token,
                    "message": text,
                },
                timeout=15.0,
            )
        if r.status_code not in (200, 201):
            return False, r.text[:400] or f"HTTP {r.status_code}", None
        data = r.json()
        post_id = data.get("id") or data.get("post_id")
        return True, "Published", str(post_id) if post_id else None
    except Exception as e:
        return False, str(e), None


def _publish_instagram_business(
    connection: SocialConnection,
    *,
    text: str,
    media_url: str | None = None,
) -> tuple[bool, str, str | None]:
    """Publish to Instagram Business. Requires page token and Instagram Business Account linked to page."""
    page_info = _get_meta_page_token(connection)
    if not page_info:
        return False, "Could not get Facebook Page token.", None
    page_id, page_token = page_info
    try:
        # Get Instagram Business Account id linked to this page
        r = httpx.get(
            f"https://graph.facebook.com/v22.0/{page_id}",
            params={
                "access_token": page_token,
                "fields": "instagram_business_account",
            },
            timeout=15.0,
        )
        if r.status_code != 200:
            return False, r.text[:300] or f"HTTP {r.status_code}", None
        data = r.json()
        ig_account = data.get("instagram_business_account")
        if not ig_account:
            return False, "No Instagram Business Account linked to this Page.", None
        ig_id = ig_account.get("id") if isinstance(ig_account, dict) else ig_account
        if not ig_id:
            return False, "Instagram Business Account id missing.", None

        if media_url:
            # Create media container with image url, then publish
            r2 = httpx.post(
                f"https://graph.facebook.com/v22.0/{ig_id}/media",
                params={
                    "access_token": page_token,
                    "image_url": media_url,
                    "caption": text,
                },
                timeout=15.0,
            )
            if r2.status_code not in (200, 201):
                return False, r2.text[:300] or f"HTTP {r2.status_code}", None
            container_id = r2.json().get("id")
            if not container_id:
                return False, "No container id in response.", None
            r3 = httpx.post(
                f"https://graph.facebook.com/v22.0/{ig_id}/media_publish",
                params={
                    "access_token": page_token,
                    "creation_id": container_id,
                },
                timeout=15.0,
            )
            if r3.status_code not in (200, 201):
                return False, r3.text[:300] or f"HTTP {r3.status_code}", None
            return True, "Published", r3.json().get("id")
        else:
            # Text-only: Instagram doesn't support text-only posts; need at least one image.
            return False, "Instagram requires an image. Provide a media_url.", None
    except Exception as e:
        return False, str(e), None


def _publish_threads(
    connection: SocialConnection,
    *,
    text: str,
    media_url: str | None = None,
) -> tuple[bool, str, str | None]:
    """Publish to Threads. Uses Threads Graph API."""
    token = (connection.access_token or "").strip()
    try:
        # Threads API: create post (v1.0)
        payload: dict[str, Any] = {"media_type": "TEXT", "text": text}
        if media_url:
            payload["media_type"] = "IMAGE"
            payload["image_url"] = media_url
        r = httpx.post(
            "https://graph.threads.net/v1.0/me/threads",
            params={"access_token": token},
            json=payload,
            timeout=15.0,
        )
        if r.status_code not in (200, 201):
            return False, r.text[:400] or f"HTTP {r.status_code}", None
        data = r.json()
        post_id = data.get("id")
        return True, "Published", str(post_id) if post_id else None
    except Exception as e:
        return False, str(e), None
