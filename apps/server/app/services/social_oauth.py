import httpx

from app.services.social_providers import social_provider_catalog


class OAuthExchangeError(Exception):
    pass


def exchange_code_for_tokens(
    provider: str,
    code: str,
    code_verifier: str | None = None,
) -> dict:
    """Exchange authorization code for tokens. Uses PKCE (code_verifier) when provided,
    so client_secret is not required (browser-session flow). Falls back to client_secret
    when code_verifier is missing (e.g. legacy or providers that require it)."""
    catalog = social_provider_catalog()
    if provider not in catalog:
        raise OAuthExchangeError("Unsupported provider")

    provider_data = catalog[provider]
    client_id = provider_data.get("client_id")
    client_secret = provider_data.get("client_secret")
    token_url = provider_data.get("token_url")
    redirect_uri = provider_data.get("redirect_uri")

    if not client_id:
        raise OAuthExchangeError("Provider is not configured with client_id")

    if not code_verifier and not client_secret:
        raise OAuthExchangeError(
            "Provider needs either PKCE (code_verifier) or client_secret for token exchange"
        )

    data = {
        "grant_type": "authorization_code",
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "code": code,
    }
    if code_verifier:
        data["code_verifier"] = code_verifier
    # When using PKCE (browser session) we do not send client_secret.
    if client_secret and not code_verifier:
        data["client_secret"] = client_secret

    headers = {"Content-Type": "application/x-www-form-urlencoded"}

    try:
        response = httpx.post(token_url, data=data, headers=headers, timeout=20.0)
    except Exception as exc:  # noqa: BLE001
        raise OAuthExchangeError(f"Token exchange request failed: {exc}") from exc

    if response.status_code >= 400:
        body_preview = response.text[:300]
        raise OAuthExchangeError(f"Token exchange failed ({response.status_code}): {body_preview}")

    payload = response.json()
    if "access_token" not in payload:
        raise OAuthExchangeError("Token response did not include access_token")

    return payload
