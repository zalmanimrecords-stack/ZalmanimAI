from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

import httpx
from fastapi import HTTPException, Request, status
from fastapi.responses import RedirectResponse
from jose import JWTError, jwt

from app.core.config import settings

_GOOGLE_AUTH_SCOPES = [
    "openid",
    "email",
    "profile",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/gmail.compose",
]

_FACEBOOK_AUTH_SCOPES = [
    "email",
    "public_profile",
    "pages_show_list",
    "pages_manage_posts",
    "pages_read_engagement",
    "instagram_basic",
    "instagram_content_publish",
]


def _oauth_callback_url(request: Request, provider: str) -> str:
    return str(request.url_for("oauth_callback", provider=provider))


def _origin_from_url(value: str | None) -> str:
    parsed = urlparse((value or "").strip())
    if not parsed.scheme or not parsed.netloc:
        return ""
    return f"{parsed.scheme}://{parsed.netloc}"


def _sanitize_redirect_target(base_url: str) -> str:
    candidate = (base_url or "").strip()
    if not candidate:
        candidate = (settings.oauth_success_redirect or settings.admin_app_base_url or "/").strip() or "/"
    parsed = urlparse(candidate)
    if not parsed.scheme and not parsed.netloc:
        if not candidate.startswith("/"):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid redirect URI")
        query = urlencode(parse_qsl(parsed.query, keep_blank_values=True))
        return urlunparse(("", "", parsed.path or "/", "", query, ""))
    origin = _origin_from_url(candidate)
    if not origin or origin not in set(settings.oauth_allowed_redirect_origin_list()):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Redirect URI is not allowed")
    query = urlencode(parse_qsl(parsed.query, keep_blank_values=True))
    return urlunparse((parsed.scheme, parsed.netloc, parsed.path or "/", "", query, ""))


def _redirect_with_params(base_url: str, **params: str) -> RedirectResponse:
    clean_params = {k: v for k, v in params.items() if v}
    parsed = urlparse(base_url)
    existing = dict(parse_qsl(parsed.query, keep_blank_values=True))
    existing.update(clean_params)
    url = urlunparse(
        (
            parsed.scheme,
            parsed.netloc,
            parsed.path or "/",
            parsed.params,
            urlencode(existing),
            "",
        )
    )
    return RedirectResponse(url=url)


def _redirect_with_fragment_params(base_url: str, **params: str) -> RedirectResponse:
    clean_params = {k: v for k, v in params.items() if v}
    parsed = urlparse(base_url)
    existing = dict(parse_qsl(parsed.fragment, keep_blank_values=True))
    existing.update(clean_params)
    url = urlunparse(
        (
            parsed.scheme,
            parsed.netloc,
            parsed.path or "/",
            parsed.params,
            parsed.query,
            urlencode(existing),
        )
    )
    return RedirectResponse(url=url)


def _build_oauth_state(*, provider: str, purpose: str, app_redirect: str, user_id: int | None = None) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)
    payload = {
        "provider": provider,
        "purpose": purpose,
        "app_redirect": app_redirect,
        "user_id": user_id,
        "exp": int(expires_at.timestamp()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def _decode_oauth_state(state: str) -> dict:
    try:
        return jwt.decode(state, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid OAuth state") from exc


def _build_google_auth_url(*, request: Request, state: str) -> str:
    if not settings.google_client_id or not settings.google_client_secret:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Google OAuth is not configured")
    query = {
        "client_id": settings.google_client_id,
        "redirect_uri": _oauth_callback_url(request, "google"),
        "response_type": "code",
        "scope": " ".join(_GOOGLE_AUTH_SCOPES),
        "access_type": "offline",
        "include_granted_scopes": "true",
        "prompt": "consent",
        "state": state,
    }
    return f"https://accounts.google.com/o/oauth2/v2/auth?{urlencode(query)}"


def _exchange_google_code(*, request: Request, code: str) -> dict:
    response = httpx.post(
        "https://oauth2.googleapis.com/token",
        data={
            "client_id": settings.google_client_id,
            "client_secret": settings.google_client_secret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": _oauth_callback_url(request, "google"),
        },
        timeout=20.0,
    )
    if response.status_code >= 400:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Google token exchange failed: {response.text[:300]}")
    payload = response.json()
    if not payload.get("access_token"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Google token exchange returned no access_token")
    return payload


def _fetch_google_userinfo(access_token: str) -> dict:
    response = httpx.get(
        "https://openidconnect.googleapis.com/v1/userinfo",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=20.0,
    )
    if response.status_code >= 400:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Failed to load Google profile: {response.text[:300]}")
    data = response.json()
    if not data.get("email"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Google profile did not include email")
    return data


def _build_facebook_auth_url(*, request: Request, state: str) -> str:
    if not settings.meta_client_id or not settings.meta_client_secret:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Facebook OAuth is not configured")
    query = {
        "client_id": settings.meta_client_id,
        "redirect_uri": _oauth_callback_url(request, "facebook"),
        "response_type": "code",
        "scope": ",".join(_FACEBOOK_AUTH_SCOPES),
        "state": state,
    }
    return f"https://www.facebook.com/v22.0/dialog/oauth?{urlencode(query)}"


def _exchange_facebook_code(*, request: Request, code: str) -> dict:
    response = httpx.get(
        "https://graph.facebook.com/v22.0/oauth/access_token",
        params={
            "client_id": settings.meta_client_id,
            "client_secret": settings.meta_client_secret,
            "code": code,
            "redirect_uri": _oauth_callback_url(request, "facebook"),
        },
        timeout=20.0,
    )
    if response.status_code >= 400:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Facebook token exchange failed: {response.text[:300]}")
    payload = response.json()
    if not payload.get("access_token"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Facebook token exchange returned no access_token")
    return payload


def _fetch_facebook_userinfo(access_token: str) -> dict:
    response = httpx.get(
        "https://graph.facebook.com/me",
        params={"fields": "id,name,email", "access_token": access_token},
        timeout=20.0,
    )
    if response.status_code >= 400:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Failed to load Facebook profile: {response.text[:300]}")
    data = response.json()
    if not data.get("email"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Facebook profile did not include email")
    return data


def _build_provider_auth_url(provider: str, *, request: Request, state: str) -> str:
    if provider == "google":
        return _build_google_auth_url(request=request, state=state)
    if provider == "facebook":
        return _build_facebook_auth_url(request=request, state=state)
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Unsupported auth provider")


def _exchange_provider_code(provider: str, *, request: Request, code: str) -> dict:
    if provider == "google":
        return _exchange_google_code(request=request, code=code)
    if provider == "facebook":
        return _exchange_facebook_code(request=request, code=code)
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Unsupported auth provider")


def _fetch_provider_profile(provider: str, access_token: str) -> tuple[str, str, str | None]:
    if provider == "google":
        profile = _fetch_google_userinfo(access_token)
        return str(profile.get("sub") or ""), str(profile.get("email") or ""), profile.get("name")
    if provider == "facebook":
        profile = _fetch_facebook_userinfo(access_token)
        return str(profile.get("id") or ""), str(profile.get("email") or ""), profile.get("name")
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Unsupported auth provider")
