"""Advanced connectors hub: Mailchimp, WordPress Codex WP, etc. Credentials from env when set (no API key in UI)."""

import hashlib
import hmac
import json
import secrets
import time
from urllib.parse import urlparse

import httpx

from app.core.config import settings


def _connector_types_catalog() -> dict:
    """Build catalog: when env credentials are set, config_fields are empty (no API key asked in UI)."""
    mailchimp_from_env = bool(settings.mailchimp_api_key.strip())
    wp_from_env = bool(
        settings.wordpress_rest_base_url.strip()
        and settings.wordpress_client_key.strip()
        and settings.wordpress_client_secret.strip()
    )
    return {
        "mailchimp": {
            "key": "mailchimp",
            "title": "Mailchimp",
            "description": "Email marketing and audiences. "
            + ("Credentials from environment (MAILCHIMP_API_KEY). Just enter a label." if mailchimp_from_env else "Set MAILCHIMP_API_KEY in env, then add a connection with a label only."),
            "config_fields": [] if mailchimp_from_env else [
                {"name": "api_key", "label": "API Key", "type": "password", "required": True},
            ],
        },
        "wordpress_codex": {
            "key": "wordpress_codex",
            "title": "WordPress (Codex WP)",
            "description": "Connect via Codex Bridge plugin. "
            + ("Credentials from environment. Just enter a label." if wp_from_env else "Set WORDPRESS_REST_BASE_URL, WORDPRESS_CLIENT_KEY, WORDPRESS_CLIENT_SECRET in env, or enter them below."),
            "config_fields": [] if wp_from_env else [
                {"name": "rest_base_url", "label": "REST Base URL", "type": "text", "required": True, "placeholder": "https://yoursite.com/wp-json/codex-bridge/v1"},
                {"name": "client_key", "label": "Client Key", "type": "text", "required": True},
                {"name": "client_secret", "label": "Client Secret", "type": "password", "required": True},
            ],
        },
    }


def hub_connector_types() -> dict:
    return _connector_types_catalog()


def _codex_signed_headers(method: str, url: str, client_key: str, client_secret: str, body: str = "") -> dict:
    parsed = urlparse(url)
    route = parsed.path or "/"
    timestamp = str(int(time.time()))
    nonce = secrets.token_hex(16)
    body_hash = hashlib.sha256((body or "").encode()).hexdigest()
    string_to_sign = f"{method}\n{route}\n{timestamp}\n{nonce}\n{body_hash}"
    signature = hmac.new(
        client_secret.encode(),
        string_to_sign.encode(),
        hashlib.sha256,
    ).hexdigest()
    return {
        "X-Codex-Key": client_key,
        "X-Codex-Timestamp": timestamp,
        "X-Codex-Nonce": nonce,
        "X-Codex-Signature": signature,
        "Content-Type": "application/json",
    }


def _resolve_config(connector_type: str, config: dict) -> dict:
    """Merge env credentials into config so we never ask for API keys when env is set."""
    out = dict(config)
    if connector_type == "mailchimp" and not (out.get("api_key") or "").strip():
        out["api_key"] = settings.mailchimp_api_key
    if connector_type == "wordpress_codex":
        if not (out.get("rest_base_url") or "").strip():
            out["rest_base_url"] = settings.wordpress_rest_base_url
        if not (out.get("client_key") or "").strip():
            out["client_key"] = settings.wordpress_client_key
        if not (out.get("client_secret") or "").strip():
            out["client_secret"] = settings.wordpress_client_secret
    return out


def test_connector(connector_type: str, config: dict) -> tuple[bool, str]:
    """Test a connector configuration. Uses env credentials when config does not have them."""
    cfg = _resolve_config(connector_type, config)
    if connector_type == "mailchimp":
        api_key = (cfg.get("api_key") or "").strip()
        if not api_key:
            return False, "API key is required. Set MAILCHIMP_API_KEY in env or provide in config."
        if "-" not in api_key:
            return False, "API key should contain datacenter (e.g. xxxxx-us21)"
        dc = api_key.split("-")[-1]
        try:
            r = httpx.get(
                f"https://{dc}.api.mailchimp.com/3.0/ping",
                auth=("anystring", api_key),
                timeout=10.0,
            )
            if r.status_code == 200:
                return True, "Connected"
            return False, r.text[:200] or f"HTTP {r.status_code}"
        except Exception as e:
            return False, str(e)

    if connector_type == "wordpress_codex":
        base = (cfg.get("rest_base_url") or "").strip().rstrip("/")
        client_key = (cfg.get("client_key") or "").strip()
        client_secret = (cfg.get("client_secret") or "").strip()
        if not base or not client_key or not client_secret:
            return False, "REST Base URL, Client Key and Client Secret required. Set in env (WORDPRESS_*) or in config."
        url = f"{base}/context"
        try:
            headers = _codex_signed_headers("GET", url, client_key, client_secret, "")
            r = httpx.get(url, headers=headers, timeout=10.0)
            if r.status_code == 200:
                return True, "Connected"
            return False, r.text[:200] or f"HTTP {r.status_code}"
        except Exception as e:
            return False, str(e)

    return False, f"Unknown connector type: {connector_type}"


def publish_wordpress_content(
    config: dict,
    *,
    title: str,
    content: str,
    post_type: str = "post",
    status: str = "publish",
) -> tuple[bool, str, str | None]:
    """Publish content to WordPress via Codex Bridge /content. Returns (success, message, external_id)."""
    cfg = _resolve_config("wordpress_codex", config)
    base = (cfg.get("rest_base_url") or "").strip().rstrip("/")
    client_key = (cfg.get("client_key") or "").strip()
    client_secret = (cfg.get("client_secret") or "").strip()
    if not base or not client_key or not client_secret:
        return False, "WordPress connector not configured.", None
    url = f"{base}/content"
    body = {
        "operation": "upsert",
        "post_type": post_type,
        "title": title,
        "content": content,
        "status": status,
    }
    body_str = json.dumps(body)
    try:
        headers = _codex_signed_headers("POST", url, client_key, client_secret, body_str)
        r = httpx.post(url, headers=headers, content=body_str, timeout=30.0)
        if r.status_code in (200, 201):
            data = r.json() if r.content else {}
            external_id = data.get("id") or data.get("post_id")
            if external_id is not None:
                external_id = str(external_id)
            return True, "Published", external_id
        return False, r.text[:500] or f"HTTP {r.status_code}", None
    except Exception as e:
        return False, str(e), None
