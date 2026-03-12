from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.config import settings


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

ROLE_PERMISSIONS = {
    "admin": {
        "artists:read",
        "artists:write",
        "releases:read",
        "releases:write",
        "campaigns:read",
        "campaigns:write",
        "reports:read",
        "settings:read",
        "settings:write",
        "users:read",
        "users:write",
    },
    "manager": {
        "artists:read",
        "artists:write",
        "releases:read",
        "releases:write",
        "campaigns:read",
        "campaigns:write",
        "reports:read",
        "settings:read",
        "users:read",
    },
    "artist": {
        "artist:self",
        "releases:self",
    },
}


def hash_password(password: str) -> str:
    return pwd_context.hash(password)



def verify_password(plain_password: str, hashed_password: str | None) -> bool:
    if not hashed_password:
        return False
    return pwd_context.verify(plain_password, hashed_password)



def permissions_for_role(role: str) -> list[str]:
    return sorted(ROLE_PERMISSIONS.get(role, set()))



def create_access_token(subject: str) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_minutes)
    exp_seconds = int(expires_at.timestamp())
    payload = {"sub": subject, "exp": exp_seconds}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)



def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError as exc:
        raise ValueError("Invalid token") from exc
