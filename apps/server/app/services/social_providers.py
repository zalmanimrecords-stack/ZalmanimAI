from urllib.parse import urlencode

from app.core.config import settings


def _redirect_uri(provider: str) -> str:
    return f"{settings.oauth_redirect_base}?provider={provider}"


def social_provider_catalog() -> dict[str, dict]:
    return {
        "facebook_page": {
            "title": "Facebook Page",
            "scopes": ["pages_manage_posts", "pages_read_engagement", "pages_show_list"],
            "client_id": settings.meta_client_id,
            "client_secret": settings.meta_client_secret,
            "auth_url": "https://www.facebook.com/v22.0/dialog/oauth",
            "token_url": "https://graph.facebook.com/v22.0/oauth/access_token",
            "redirect_uri": _redirect_uri("facebook_page"),
        },
        "instagram_business": {
            "title": "Instagram Business",
            "scopes": ["instagram_basic", "instagram_content_publish", "pages_show_list"],
            "client_id": settings.meta_client_id,
            "client_secret": settings.meta_client_secret,
            "auth_url": "https://www.facebook.com/v22.0/dialog/oauth",
            "token_url": "https://graph.facebook.com/v22.0/oauth/access_token",
            "redirect_uri": _redirect_uri("instagram_business"),
        },
        "threads": {
            "title": "Threads",
            "scopes": ["threads_basic", "threads_content_publish"],
            "client_id": settings.meta_client_id,
            "client_secret": settings.meta_client_secret,
            "auth_url": "https://www.threads.net/oauth/authorize",
            "token_url": "https://graph.threads.net/oauth/access_token",
            "redirect_uri": _redirect_uri("threads"),
        },
        "tiktok": {
            "title": "TikTok",
            "scopes": ["user.info.basic", "video.publish"],
            "client_id": settings.tiktok_client_id,
            "client_secret": settings.tiktok_client_secret,
            "auth_url": "https://www.tiktok.com/v2/auth/authorize/",
            "token_url": "https://open.tiktokapis.com/v2/oauth/token/",
            "redirect_uri": _redirect_uri("tiktok"),
        },
        "youtube": {
            "title": "YouTube",
            "scopes": [
                "https://www.googleapis.com/auth/youtube.upload",
                "https://www.googleapis.com/auth/youtube.readonly",
            ],
            "client_id": settings.youtube_client_id,
            "client_secret": settings.youtube_client_secret,
            "auth_url": "https://accounts.google.com/o/oauth2/v2/auth",
            "token_url": "https://oauth2.googleapis.com/token",
            "redirect_uri": _redirect_uri("youtube"),
        },
        "x": {
            "title": "X (Twitter)",
            "scopes": ["tweet.read", "tweet.write", "users.read", "offline.access"],
            "client_id": settings.x_client_id,
            "client_secret": settings.x_client_secret,
            "auth_url": "https://twitter.com/i/oauth2/authorize",
            "token_url": "https://api.twitter.com/2/oauth2/token",
            "redirect_uri": _redirect_uri("x"),
        },
        "linkedin": {
            "title": "LinkedIn",
            "scopes": ["w_member_social", "r_liteprofile", "r_emailaddress"],
            "client_id": settings.linkedin_client_id,
            "client_secret": settings.linkedin_client_secret,
            "auth_url": "https://www.linkedin.com/oauth/v2/authorization",
            "token_url": "https://www.linkedin.com/oauth/v2/accessToken",
            "redirect_uri": _redirect_uri("linkedin"),
        },
        "soundcloud": {
            "title": "SoundCloud",
            "scopes": ["non-expiring"],
            "client_id": settings.soundcloud_client_id,
            "client_secret": settings.soundcloud_client_secret,
            "auth_url": "https://secure.soundcloud.com/authorize",
            "token_url": "https://secure.soundcloud.com/oauth/token",
            "redirect_uri": _redirect_uri("soundcloud"),
        },
    }


def build_provider_auth_url(
    provider: str,
    state: str,
    code_challenge: str | None = None,
) -> str:
    catalog = social_provider_catalog()
    provider_data = catalog[provider]
    query = {
        "client_id": provider_data["client_id"] or "MISSING_CLIENT_ID",
        "redirect_uri": provider_data["redirect_uri"],
        "response_type": "code",
        "state": state,
        "scope": " ".join(provider_data["scopes"]),
    }
    if code_challenge:
        query["code_challenge"] = code_challenge
        query["code_challenge_method"] = "S256"
    return f"{provider_data['auth_url']}?{urlencode(query)}"
