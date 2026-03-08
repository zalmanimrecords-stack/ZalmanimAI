"""PKCE (Proof Key for Code Exchange) for OAuth2 without client_secret (browser-session flow)."""
import base64
import hashlib
import secrets


def generate_pkce_pair() -> tuple[str, str]:
    """Return (code_verifier, code_challenge) for S256."""
    code_verifier = (
        base64.urlsafe_b64encode(secrets.token_bytes(64)).rstrip(b"=").decode("utf-8")
    )
    digest = hashlib.sha256(code_verifier.encode("utf-8")).digest()
    code_challenge = (
        base64.urlsafe_b64encode(digest).rstrip(b"=").decode("utf-8")
    )
    return code_verifier, code_challenge
