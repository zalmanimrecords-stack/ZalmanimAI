"""
Shared FastAPI dependencies for authentication and authorization.
Used by routes.py and audience_routes.py to avoid duplication and drift.
"""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session, joinedload

from app.db.session import get_db
from app.models.models import Artist, User
from app.schemas.schemas import UserContext
from app.services.auth import decode_token, permissions_for_role

security = HTTPBearer()

# 403 detail when artist token is used on LM-only routes (client can show copyable message).
LM_FORBIDDEN_ARTIST_DETAIL = "Artists cannot access the LM system. Use the artist portal."


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
) -> UserContext:
    """Resolve user or artist from JWT (sub) and DB; role comes from DB, not from token."""
    try:
        payload = decode_token(credentials.credentials)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token") from exc
    sub = payload.get("sub")
    if isinstance(sub, str) and sub.startswith("artist:"):
        try:
            artist_id = int(sub[7:])
        except ValueError:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
        artist = db.query(Artist).filter(Artist.id == artist_id).first()
        if not artist or not artist.is_active:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Artist is inactive or missing")
        return UserContext(
            user_id=0,
            role="artist",
            email=artist.email,
            full_name=artist.name,
            permissions=permissions_for_role("artist"),
            artist_id=artist.id,
            is_active=artist.is_active,
        )
    # Admin/manager token (users table)
    try:
        user_id = int(payload["sub"])
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user = (
        db.query(User)
        .options(joinedload(User.artist), joinedload(User.identities))
        .filter(User.id == user_id)
        .first()
    )
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User is inactive or missing")
    return UserContext(
        user_id=user.id,
        role=user.role,
        email=user.email,
        full_name=user.full_name,
        permissions=permissions_for_role(user.role),
        artist_id=user.artist_id,
        is_active=user.is_active,
    )


def get_current_lm_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
) -> UserContext:
    """
    Same as get_current_user but rejects artist portal tokens with 403.
    Use for all LM (label management) routes; only users from the users table are allowed.
    """
    try:
        payload = decode_token(credentials.credentials)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token") from exc
    sub = payload.get("sub")
    if isinstance(sub, str) and sub.startswith("artist:"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=LM_FORBIDDEN_ARTIST_DETAIL,
        )
    try:
        user_id = int(payload["sub"])
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user = (
        db.query(User)
        .options(joinedload(User.artist), joinedload(User.identities))
        .filter(User.id == user_id)
        .first()
    )
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User is inactive or missing")
    return UserContext(
        user_id=user.id,
        role=user.role,
        email=user.email,
        full_name=user.full_name,
        permissions=permissions_for_role(user.role),
        artist_id=user.artist_id,
        is_active=user.is_active,
    )


def require_admin(user: UserContext) -> None:
    if user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin only")


def require_artist(user: UserContext) -> None:
    if user.role != "artist" or not user.artist_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Artist only")
