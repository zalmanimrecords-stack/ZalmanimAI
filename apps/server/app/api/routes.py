import csv
import io
import json
import logging
import os
import uuid
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urlencode

import httpx

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile, status
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import desc, func, or_, text, update
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, joinedload

from app.core.config import settings
from app.db.session import Base, engine, get_db
from app.models import models as models_module  # noqa: F401 - register all tables with Base
from app.models.models import (
    Artist,
    ArtistActivityLog,
    AutomationTask,
    Campaign,
    CatalogTrack,
    HubConnector,
    Release,
    release_artists_table,
    SocialConnection,
    User,
)
from app.schemas.schemas import (
    ArtistActivityLogOut,
    ArtistCreate,
    ArtistDashboard,
    ArtistOut,
    ArtistUpdate,
    CampaignCreate,
    CampaignOut,
    CampaignUpdate,
    CatalogTrackOut,
    EmailRateLimitStatus,
    ScheduleCampaignRequest,
    SendEmailRequest,
    SendEmailResponse,
    SystemSettingsMailTestRequest,
    SystemSettingsMailTestResponse,
    _artist_extra_from_model,
    LoginRequest,
    ReleaseOut,
    ReleaseUpdateArtists,
    SystemSettingsMailUpdate,
    SystemSettingsOut,
    TaskOut,
    TokenResponse,
    UserContext,
)
from app.services.auth import create_access_token, decode_token, hash_password, permissions_for_role, verify_password
from app.services.email_service import (
    get_emails_sent_this_hour,
    is_email_configured,
    send_email as send_email_service,
    send_test_smtp_email,
    test_smtp_connection,
)
from app.services.mail_settings import build_mail_config, get_effective_mail_config_for_api, save_mail_settings
from app.services.campaign_service import (
    cancel_schedule,
    create_campaign as create_campaign_svc,
    delete_campaign,
    get_campaign,
    list_campaigns as list_campaigns_svc,
    set_campaign_scheduled,
    update_campaign as update_campaign_svc,
)

router = APIRouter()
security = HTTPBearer()

_GOOGLE_AUTH_SCOPES = [
    "openid",
    "email",
    "profile",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/gmail.compose",
]

_FACEBOOK_AUTH_SCOPES = ["email", "public_profile"]
_ALLOWED_USER_ROLES = {"admin", "manager", "artist"}


def _oauth_callback_url(request: Request, provider: str) -> str:
    return str(request.url_for("oauth_callback", provider=provider))



def _build_oauth_state(*, provider: str, purpose: str, app_redirect: str, user_id: int | None = None) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)
    payload = {
        "provider": provider,
        "purpose": purpose,
        "app_redirect": app_redirect,
        "user_id": user_id,
        "exp": int(expires_at.timestamp()),
    }
    from jose import jwt

    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)



def _decode_oauth_state(state: str) -> dict:
    from jose import JWTError, jwt

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
        return str(profile.get("sub") or ""), str(profile.get("email") or "").strip(), profile.get("name")
    if provider == "facebook":
        profile = _fetch_facebook_userinfo(access_token)
        return str(profile.get("id") or ""), str(profile.get("email") or "").strip(), profile.get("name")
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Unsupported auth provider")



def _serialize_user(user: User) -> UserOut:
    artist_name = user.artist.name if getattr(user, "artist", None) else None
    identities = [UserIdentityOut.model_validate(identity) for identity in getattr(user, "identities", [])]
    return UserOut(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        permissions=permissions_for_role(user.role),
        artist_id=user.artist_id,
        artist_name=artist_name,
        is_active=user.is_active,
        created_at=user.created_at,
        updated_at=user.updated_at,
        last_login_at=user.last_login_at,
        identities=identities,
    )



def _user_token_response(user: User) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(str(user.id)),
        role=user.role,
        email=user.email,
        full_name=user.full_name,
        permissions=permissions_for_role(user.role),
    )



def _touch_user_login(db: Session, user: User) -> None:
    now = datetime.now(timezone.utc)
    user.last_login_at = now
    db.commit()
    db.refresh(user)



def _validate_user_role(role: str) -> str:
    role_value = (role or "").strip().lower()
    if role_value not in _ALLOWED_USER_ROLES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Unsupported role: {role}")
    return role_value



def _find_or_create_oauth_user(
    db: Session,
    *,
    provider: str,
    provider_subject: str,
    email: str,
    display_name: str | None,
) -> User:
    identity = (
        db.query(UserIdentity)
        .options(joinedload(UserIdentity.user).joinedload(User.artist), joinedload(UserIdentity.user).joinedload(User.identities))
        .filter(UserIdentity.provider == provider, UserIdentity.provider_subject == provider_subject)
        .first()
    )
    if identity:
        user = identity.user
        if not user.is_active:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User is inactive")
        identity.email = email or identity.email
        identity.display_name = display_name or identity.display_name
        identity.last_login_at = datetime.now(timezone.utc)
        if display_name and not user.full_name:
            user.full_name = display_name
        db.commit()
        db.refresh(user)
        return user

    user = (
        db.query(User)
        .options(joinedload(User.artist), joinedload(User.identities))
        .filter(func.lower(User.email) == email.lower())
        .first()
    )
    if user:
        if not user.is_active:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User is inactive")
    else:
        artist = db.query(Artist).filter(func.lower(Artist.email) == email.lower()).first()
        if not artist:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"{provider.title()} account is not allowed in this system yet. Create a matching user first.",
            )
        user = User(
            email=email,
            full_name=display_name,
            password_hash=None,
            role="artist",
            artist_id=artist.id,
            is_active=True,
        )
        db.add(user)
        db.flush()

    identity = UserIdentity(
        user_id=user.id,
        provider=provider,
        provider_subject=provider_subject,
        email=email,
        display_name=display_name,
        last_login_at=datetime.now(timezone.utc),
    )
    db.add(identity)
    if display_name and not user.full_name:
        user.full_name = display_name
    db.commit()
    db.refresh(user)
    return user



def _upsert_google_mail_connection(
    db: Session,
    *,
    email: str,
    access_token: str,
    refresh_token: str | None,
    scopes: list[str],
) -> SocialConnection:
    connection = db.query(SocialConnection).filter(SocialConnection.provider == "google_mail").first()
    if not connection:
        connection = SocialConnection(provider="google_mail", account_label=email, status="active")
        db.add(connection)

    connection.account_label = email
    connection.external_account_id = email
    connection.access_token = access_token
    if refresh_token:
        connection.refresh_token = refresh_token
    connection.scopes_csv = ",".join(scopes)
    connection.status = "active"
    connection.authorized_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(connection)
    return connection



def _gmail_connection_status(db: Session) -> tuple[bool, str]:
    connection = (
        db.query(SocialConnection)
        .filter(SocialConnection.provider == "google_mail", SocialConnection.status == "active")
        .order_by(SocialConnection.authorized_at.desc().nullslast(), SocialConnection.id.desc())
        .first()
    )
    if not connection:
        return False, ""
    return True, (connection.external_account_id or connection.account_label or "")



def _redirect_with_params(base_url: str, **params: str) -> RedirectResponse:
    clean_params = {k: v for k, v in params.items() if v}
    separator = "&" if "?" in base_url else "?"
    url = f"{base_url}{separator}{urlencode(clean_params)}" if clean_params else base_url
    return RedirectResponse(url=url)

@router.on_event("startup")
def init_db() -> None:
    # Ensure all ORM models are loaded so create_all creates every table (including social_connections).
    Base.metadata.create_all(bind=engine)

    # Add artists.extra_json if missing (migration for existing DBs).
    with engine.connect() as conn:
        try:
            from sqlalchemy import inspect as sa_inspect
            insp = sa_inspect(engine)
            if "artists" in insp.get_table_names():
                cols = [c["name"] for c in insp.get_columns("artists")]
                if "extra_json" not in cols:
                    conn.execute(text("ALTER TABLE artists ADD COLUMN extra_json TEXT"))
                    conn.commit()
                if "is_active" not in cols:
                    conn.execute(text("ALTER TABLE artists ADD COLUMN is_active BOOLEAN DEFAULT true NOT NULL"))
                    conn.commit()
            if "social_connections" in insp.get_table_names():
                sc_cols = [c["name"] for c in insp.get_columns("social_connections")]
                if "pkce_code_verifier" not in sc_cols:
                    conn.execute(text("ALTER TABLE social_connections ADD COLUMN pkce_code_verifier VARCHAR(255)"))
                    conn.commit()
                if "one_time_token" not in sc_cols:
                    conn.execute(text("ALTER TABLE social_connections ADD COLUMN one_time_token VARCHAR(255)"))
                    conn.commit()
                if "one_time_expires_at" not in sc_cols:
                    conn.execute(text("ALTER TABLE social_connections ADD COLUMN one_time_expires_at TIMESTAMP WITH TIME ZONE"))
                    conn.commit()
        except Exception as e:
            logging.getLogger(__name__).warning("DB migration (artists/social_connections): %s", e)
            pass
    # Idempotent migration for social_connections (PostgreSQL 9.6+ ADD COLUMN IF NOT EXISTS)
    try:
        with engine.connect() as conn:
            conn.execute(text("ALTER TABLE social_connections ADD COLUMN IF NOT EXISTS pkce_code_verifier VARCHAR(255)"))
            conn.execute(text("ALTER TABLE social_connections ADD COLUMN IF NOT EXISTS one_time_token VARCHAR(255)"))
            conn.execute(text("ALTER TABLE social_connections ADD COLUMN IF NOT EXISTS one_time_expires_at TIMESTAMP WITH TIME ZONE"))
            conn.commit()
    except Exception as e:
        logging.getLogger(__name__).warning("DB migration (social_connections IF NOT EXISTS): %s", e)

    # Seed first admin/artist users for MVP onboarding.
    with Session(engine) as db:
        admin = db.query(User).filter(User.email == "admin@label.local").first()
        if not admin:
            artist = Artist(name="Demo Artist", email="artist@label.local", notes="Seed artist", is_active=True)
            db.add(artist)
            db.flush()

            db.add(
                User(
                    email="admin@label.local",
                    password_hash=hash_password("admin123"),
                    role="admin",
                    artist_id=None,
                )
            )
            db.add(
                User(
                    email="artist@label.local",
                    password_hash=hash_password("artist123"),
                    role="artist",
                    artist_id=artist.id,
                )
            )
            db.commit()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> UserContext:
    try:
        payload = decode_token(credentials.credentials)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token")
    return UserContext(
        user_id=int(payload["sub"]),
        role=str(payload["role"]),
        artist_id=payload.get("artist_id"),
    )


def require_admin(user: UserContext) -> None:
    if user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin only")


def require_artist(user: UserContext) -> None:
    if user.role != "artist" or not user.artist_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Artist only")


@router.post("/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    user = db.query(User).filter(User.email == payload.email).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    token = create_access_token(str(user.id), user.role, user.artist_id)
    return TokenResponse(access_token=token, role=user.role)


@router.get("/auth/google/start")
def start_google_login(request: Request, redirect_uri: str) -> dict:
    state = _build_google_state(purpose="login", app_redirect=redirect_uri)
    return {"auth_url": _build_google_auth_url(request=request, state=state)}


@router.get("/admin/google-mail/start")
def start_google_mail_connect(
    request: Request,
    redirect_uri: str,
    user: UserContext = Depends(get_current_user),
) -> dict:
    require_admin(user)
    state = _build_google_state(purpose="connect_gmail", app_redirect=redirect_uri, user_id=user.user_id)
    return {"auth_url": _build_google_auth_url(request=request, state=state)}


@router.get("/auth/google/callback", name="google_auth_callback")
def google_auth_callback(
    request: Request,
    state: str,
    code: str | None = None,
    error: str | None = None,
    db: Session = Depends(get_db),
) -> RedirectResponse:
    state_payload = _decode_google_state(state)
    app_redirect = state_payload.get("app_redirect") or settings.oauth_success_redirect or "/"
    if error:
        return _redirect_with_params(app_redirect, google_error=error)
    if not code:
        return _redirect_with_params(app_redirect, google_error="missing_code")

    token_payload = _exchange_google_code(request=request, code=code)
    access_token = str(token_payload.get("access_token") or "")
    refresh_token = token_payload.get("refresh_token")
    scope_value = str(token_payload.get("scope") or "")
    scopes = [s for s in scope_value.split(" ") if s]
    profile = _fetch_google_userinfo(access_token)
    email = str(profile.get("email") or "").strip()
    if state_payload.get("purpose") == "connect_gmail":
        _upsert_google_mail_connection(
            db,
            email=email,
            access_token=access_token,
            refresh_token=refresh_token,
            scopes=scopes,
        )
        return _redirect_with_params(app_redirect, gmail_connected="1", gmail_email=email)

    user = _find_or_create_google_user(db, email=email)
    if user.role == "admin":
        _upsert_google_mail_connection(
            db,
            email=email,
            access_token=access_token,
            refresh_token=refresh_token,
            scopes=scopes,
        )
    app_token = create_access_token(str(user.id), user.role, user.artist_id)
    return _redirect_with_params(app_redirect, token=app_token, role=user.role, google_email=email)



@router.get("/artists", response_model=list[ArtistOut])
def list_artists(
    include_inactive: bool = Query(False, description="Include inactive artists"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[ArtistOut]:
    require_admin(user)
    q = db.query(Artist).order_by(Artist.id)
    if not include_inactive:
        q = q.filter(Artist.is_active.is_(True))
    artists = q.offset(offset).limit(limit).all()
    out = []
    for a in artists:
        latest = (
            db.query(Release)
            .filter(or_(Release.artist_id == a.id, Release.artists.any(Artist.id == a.id)))
            .order_by(desc(Release.created_at))
            .first()
        )
        last_release = None
        if latest:
            last_release = {
                "title": latest.title,
                "created_at": latest.created_at.isoformat() if latest.created_at else None,
            }
        out.append(ArtistOut.from_artist(a, last_release=last_release))
    return out


@router.get("/artists/{artist_id}", response_model=ArtistOut)
def get_artist(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistOut:
    require_admin(user)
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    return ArtistOut.from_artist(artist)


@router.post("/artists", response_model=ArtistOut)
def create_artist(
    payload: ArtistCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistOut:
    require_admin(user)
    extra = _artist_extra_from_model(payload)
    artist = Artist(
        name=payload.name,
        email=payload.email,
        notes=payload.notes,
        extra_json=json.dumps(extra) if extra else "{}",
    )
    db.add(artist)
    db.commit()
    db.refresh(artist)
    return ArtistOut.from_artist(artist)


@router.patch("/artists/{artist_id}", response_model=ArtistOut)
def update_artist(
    artist_id: int,
    payload: ArtistUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistOut:
    require_admin(user)
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if payload.name is not None:
        artist.name = payload.name
    if payload.email is not None:
        artist.email = payload.email
    if payload.notes is not None:
        artist.notes = payload.notes
    if payload.is_active is not None:
        artist.is_active = payload.is_active
    extra = _artist_extra_from_model(payload)
    if extra:
        try:
            current = json.loads(artist.extra_json or "{}")
            current.update(extra)
            artist.extra_json = json.dumps(current)
        except (json.JSONDecodeError, TypeError):
            artist.extra_json = json.dumps(extra)
    db.commit()
    db.refresh(artist)
    return ArtistOut.from_artist(artist)


@router.get("/artists/{artist_id}/releases", response_model=list[ReleaseOut])
def list_artist_releases(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[ReleaseOut]:
    require_admin(user)
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    releases = (
        db.query(Release)
        .options(joinedload(Release.artists))
        .filter(or_(Release.artist_id == artist_id, Release.artists.any(Artist.id == artist_id)))
        .order_by(desc(Release.created_at))
        .all()
    )
    return [ReleaseOut.from_release(r) for r in releases]


@router.get("/admin/artists/{artist_id}/activity", response_model=list[ArtistActivityLogOut])
def list_artist_activity(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[ArtistActivityLogOut]:
    """List activity log for an artist (reminder emails, etc.) for the Logs tab."""
    require_admin(user)
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    logs = (
        db.query(ArtistActivityLog)
        .filter(ArtistActivityLog.artist_id == artist_id)
        .order_by(desc(ArtistActivityLog.created_at))
        .all()
    )
    return [
        ArtistActivityLogOut(
            id=log.id,
            activity_type=log.activity_type,
            details=log.details,
            created_at=log.created_at,
        )
        for log in logs
    ]


@router.delete("/artists/{artist_id}")
def delete_artist(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    require_admin(user)
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    try:
        # Unlink any users from this artist so we can delete it
        db.execute(update(User).where(User.artist_id == artist_id).values(artist_id=None))
        # Clear artist_id on campaigns so we can delete the artist
        db.execute(update(Campaign).where(Campaign.artist_id == artist_id).values(artist_id=None))
        # Delete dependent records first (no FK cascade on artist_id)
        db.query(AutomationTask).filter(AutomationTask.artist_id == artist_id).delete(synchronize_session=False)
        db.execute(release_artists_table.delete().where(release_artists_table.c.artist_id == artist_id))
        db.query(Release).filter(Release.artist_id == artist_id).delete(synchronize_session=False)
        db.query(SocialConnection).filter(SocialConnection.artist_id == artist_id).delete(synchronize_session=False)
        db.delete(artist)
        db.commit()
    except SQLAlchemyError as e:
        db.rollback()
        logging.exception("Delete artist %s failed", artist_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Delete failed: {e!s}",
        ) from e
    return {"ok": True}


@router.get("/artist/me/dashboard", response_model=ArtistDashboard)
def artist_dashboard(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistDashboard:
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")

    releases = (
        db.query(Release)
        .options(joinedload(Release.artists))
        .filter(or_(Release.artist_id == artist.id, Release.artists.any(Artist.id == artist.id)))
        .order_by(desc(Release.created_at))
        .all()
    )
    tasks = (
        db.query(AutomationTask)
        .filter(AutomationTask.artist_id == artist.id)
        .order_by(desc(AutomationTask.created_at))
        .all()
    )

    return ArtistDashboard(
        artist=ArtistOut.model_validate(artist),
        releases=[ReleaseOut.from_release(item) for item in releases],
        tasks=[TaskOut.model_validate(item) for item in tasks],
    )


@router.post("/artist/me/releases/upload", response_model=ReleaseOut)
def upload_release(
    title: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> Release:
    require_artist(user)

    os.makedirs(settings.upload_dir, exist_ok=True)
    extension = os.path.splitext(file.filename or "")[1]
    filename = f"{uuid.uuid4().hex}{extension}"
    path = os.path.join(settings.upload_dir, filename)

    with open(path, "wb") as out:
        out.write(file.file.read())

    release = Release(artist_id=user.artist_id, title=title, status="submitted", file_path=path)
    db.add(release)
    db.flush()
    artist = db.get(Artist, user.artist_id)
    if artist:
        release.artists.append(artist)

    db.add(
        AutomationTask(
            artist_id=user.artist_id,
            title=f"Review submission: {title}",
            status="queued",
            details="System queued internal review and release preparation.",
        )
    )

    db.commit()
    db.refresh(release)
    return ReleaseOut.from_release(release)


@router.get("/admin/releases", response_model=list[ReleaseOut])
def list_admin_releases(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[ReleaseOut]:
    """List all releases (admin). Use to assign artists when sync did not match."""
    require_admin(user)
    releases = (
        db.query(Release)
        .options(joinedload(Release.artists))
        .order_by(desc(Release.created_at))
        .offset(offset)
        .limit(limit)
        .all()
    )
    return [ReleaseOut.from_release(r) for r in releases]


# ---- Reports ----
@router.get("/admin/reports/artists-no-tracks-half-year", response_model=list[ArtistOut])
def report_artists_no_tracks_half_year(
    months: int = 6,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[ArtistOut]:
    """
    Artists who have not had any track (catalog_tracks.release_date) in the last N months.
    Uses catalog_tracks joined to releases by release_title; artists linked via release_artists.
    """
    require_admin(user)
    months = max(1, min(24, months))  # clamp 1–24
    cutoff = date.today() - timedelta(days=months * 30)  # approximate month
    # Artist IDs that have at least one catalog track with release_date >= cutoff
    active_subq = (
        db.query(release_artists_table.c.artist_id)
        .select_from(release_artists_table)
        .join(Release, Release.id == release_artists_table.c.release_id)
        .join(CatalogTrack, CatalogTrack.release_title == Release.title)
        .filter(CatalogTrack.release_date.isnot(None), CatalogTrack.release_date >= cutoff)
        .distinct()
    )
    inactive_artists = db.query(Artist).filter(Artist.id.not_in(active_subq)).order_by(Artist.name).all()
    # Last reminder_email sent per artist (for display to avoid flooding)
    last_reminder = (
        db.query(ArtistActivityLog.artist_id, func.max(ArtistActivityLog.created_at).label("last_at"))
        .filter(ArtistActivityLog.activity_type == "reminder_email")
        .group_by(ArtistActivityLog.artist_id)
        .all()
    )
    last_reminder_map = {aid: last_at for aid, last_at in last_reminder}
    return [
        ArtistOut.from_artist(a, last_reminder_sent_at=last_reminder_map.get(a.id))
        for a in inactive_artists
    ]


@router.patch("/admin/releases/{release_id}", response_model=ReleaseOut)
def update_release_artists(
    release_id: int,
    payload: ReleaseUpdateArtists,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ReleaseOut:
    """Set one or more artists for a release (e.g. when sync did not match)."""
    require_admin(user)
    release = db.query(Release).options(joinedload(Release.artists)).filter(Release.id == release_id).first()
    if not release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release not found")
    # Resolve artist ids
    artists = db.query(Artist).filter(Artist.id.in_(payload.artist_ids)).all() if payload.artist_ids else []
    if len(artists) != len(payload.artist_ids):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="One or more artist IDs not found")
    release.artist_id = payload.artist_ids[0] if payload.artist_ids else None
    release.artists = artists
    db.commit()
    db.refresh(release)
    return ReleaseOut.from_release(release)


@router.post("/admin/tasks/run-inactivity-check")
def run_inactivity_check(
    days: int = 90,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    require_admin(user)
    artists = db.query(Artist).all()

    created = 0
    for artist in artists:
        latest_release = (
            db.query(Release)
            .filter(or_(Release.artist_id == artist.id, Release.artists.any(Artist.id == artist.id)))
            .order_by(desc(Release.created_at))
            .first()
        )
        if latest_release is None:
            db.add(
                AutomationTask(
                    artist_id=artist.id,
                    title="Email reminder: no releases yet",
                    status="queued",
                    details=f"Auto-check detected no releases in the last {days} days.",
                )
            )
            created += 1

    db.commit()
    return {"created_tasks": created}


# System settings (mail editable via UI; OAuth read-only from env)
@router.get("/admin/settings", response_model=SystemSettingsOut)
def get_system_settings(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> SystemSettingsOut:
    require_admin(user)
    from app.core.config import settings

    mail = get_effective_mail_config_for_api()
    gmail_connected, gmail_email = _gmail_connection_status(db)
    return SystemSettingsOut(
        smtp_host=mail["smtp_host"],
        smtp_port=mail["smtp_port"],
        smtp_from_email=mail["smtp_from_email"],
        smtp_use_tls=mail["smtp_use_tls"],
        smtp_use_ssl=mail["smtp_use_ssl"],
        smtp_user_configured=mail["smtp_user_configured"],
        emails_per_hour=mail["emails_per_hour"],
        email_configured=is_email_configured(),
        oauth_redirect_base=settings.oauth_redirect_base or "",
        google_oauth_configured=bool(settings.google_client_id and settings.google_client_secret),
        gmail_connected=gmail_connected,
        gmail_connected_email=gmail_email,
        oauth_success_redirect=settings.oauth_success_redirect or "",
    )


@router.patch("/admin/settings/mail", response_model=SystemSettingsOut)
def update_system_settings_mail(
    payload: SystemSettingsMailUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> SystemSettingsOut:
    """Update mail server settings (stored in DB; overrides env)."""
    require_admin(user)
    from app.core.config import settings

    save_mail_settings(
        smtp_host=payload.smtp_host,
        smtp_port=payload.smtp_port,
        smtp_from_email=payload.smtp_from_email,
        smtp_use_tls=payload.smtp_use_tls,
        smtp_use_ssl=payload.smtp_use_ssl,
        smtp_user=payload.smtp_user,
        smtp_password=payload.smtp_password,
        emails_per_hour=payload.emails_per_hour,
    )
    mail = get_effective_mail_config_for_api()
    gmail_connected, gmail_email = _gmail_connection_status(db)
    return SystemSettingsOut(
        smtp_host=mail["smtp_host"],
        smtp_port=mail["smtp_port"],
        smtp_from_email=mail["smtp_from_email"],
        smtp_use_tls=mail["smtp_use_tls"],
        smtp_use_ssl=mail["smtp_use_ssl"],
        smtp_user_configured=mail["smtp_user_configured"],
        emails_per_hour=mail["emails_per_hour"],
        email_configured=is_email_configured(),
        oauth_redirect_base=settings.oauth_redirect_base or "",
        google_oauth_configured=bool(settings.google_client_id and settings.google_client_secret),
        gmail_connected=gmail_connected,
        gmail_connected_email=gmail_email,
        oauth_success_redirect=settings.oauth_success_redirect or "",
    )



@router.post("/admin/settings/mail/test", response_model=SystemSettingsMailTestResponse)
def test_system_settings_mail(
    payload: SystemSettingsMailTestRequest,
    user: UserContext = Depends(get_current_user),
) -> SystemSettingsMailTestResponse:
    """Test SMTP connection or send a test email using unsaved mail settings overrides."""
    require_admin(user)
    cfg = build_mail_config(
        smtp_host=payload.smtp_host,
        smtp_port=payload.smtp_port,
        smtp_from_email=payload.smtp_from_email,
        smtp_use_tls=payload.smtp_use_tls,
        smtp_use_ssl=payload.smtp_use_ssl,
        smtp_user=payload.smtp_user,
        smtp_password=payload.smtp_password,
        emails_per_hour=payload.emails_per_hour,
    )
    if payload.test_email:
        success, message = send_test_smtp_email(cfg, to_email=str(payload.test_email))
    else:
        success, message = test_smtp_connection(cfg)
    return SystemSettingsMailTestResponse(success=success, message=message)

# Email sending with per-hour rate limit (admin only)
@router.get("/admin/email/rate-limit", response_model=EmailRateLimitStatus)
def get_email_rate_limit_status(user: UserContext = Depends(get_current_user)) -> EmailRateLimitStatus:
    require_admin(user)

    sent = get_emails_sent_this_hour()
    mail = get_effective_mail_config_for_api()
    limit = mail["emails_per_hour"]
    remaining = (limit - sent) if limit else None
    return EmailRateLimitStatus(
        configured=is_email_configured(),
        emails_per_hour=limit,
        sent_this_hour=sent,
        remaining_this_hour=remaining,
    )


@router.post("/admin/email/send", response_model=SendEmailResponse)
def send_email(
    payload: SendEmailRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> SendEmailResponse:
    require_admin(user)
    artist = db.query(Artist).filter(Artist.email == payload.to_email).first()
    if artist is not None and not getattr(artist, "is_active", True):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot send email to an inactive artist.",
        )
    success, message = send_email_service(
        to_email=payload.to_email,
        subject=payload.subject,
        body_text=payload.body_text,
        body_html=payload.body_html,
    )
    if not success and "limit" in message.lower():
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
    if success and payload.artist_id is not None:
        artist_exists = db.query(Artist).filter(Artist.id == payload.artist_id).first()
        if artist_exists:
            db.add(
                ArtistActivityLog(
                    artist_id=payload.artist_id,
                    activity_type="reminder_email",
                    details=None,
                )
            )
            db.commit()
    return SendEmailResponse(success=success, message=message)


# Catalog metadata (Proton CSV schema) - list and import
@router.get("/admin/catalog-tracks", response_model=list[CatalogTrackOut])
def list_catalog_tracks(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[CatalogTrackOut]:
    require_admin(user)
    items = db.query(CatalogTrack).order_by(CatalogTrack.id).offset(offset).limit(limit).all()
    return [CatalogTrackOut.model_validate(t) for t in items]


# CSV columns from Proton export: Catalog Number, Release Title, Pre-Order Date, Release Date, UPC, ISRC,
# Original Artists, Original First-Last, Remix Artists, Remix First-Last, Track Title, Mix Title, Duration
_CSV_TO_FIELD = {
    "catalog number": "catalog_number",
    "release title": "release_title",
    "pre-order date": "pre_order_date",
    "release date": "release_date",
    "upc": "upc",
    "isrc": "isrc",
    "original artists": "original_artists",
    "original first-last": "original_first_last",
    "remix artists": "remix_artists",
    "remix first-last": "remix_first_last",
    "track title": "track_title",
    "mix title": "mix_title",
    "duration": "duration",
}

# Max lengths from CatalogTrack model to avoid DB overflow
_CSV_FIELD_MAX_LEN = {
    "catalog_number": 32,
    "release_title": 300,
    "pre_order_date": 20,
    "release_date": 20,
    "upc": 32,
    "isrc": 32,
    "original_artists": 500,
    "original_first_last": 500,
    "remix_artists": 500,
    "remix_first_last": 500,
    "track_title": 300,
    "mix_title": 200,
    "duration": 20,
}

logger = logging.getLogger(__name__)


def _trunc(s: str | None, max_len: int) -> str | None:
    if s is None:
        return None
    s = s.strip() or None
    if s is None:
        return None
    return s[:max_len] if len(s) > max_len else s


def _parse_date(s: str | None) -> date | None:
    """Parse CSV date string (YYYY-MM-DD) to date for DB; invalid/empty returns None."""
    if not s or not (s := s.strip()):
        return None
    s = s[:10]
    try:
        return date.fromisoformat(s)
    except ValueError:
        return None


@router.post("/admin/catalog-tracks/import", response_model=dict)
async def import_catalog_csv(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    require_admin(user)
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Upload a CSV file")
    try:
        raw = await file.read()
    except Exception as e:
        logger.exception("Catalog import: failed to read upload")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not read uploaded file: {e!s}",
        ) from e
    try:
        content = raw.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        logger.warning("Catalog import: invalid encoding: %s", e)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File must be UTF-8 (or UTF-8 with BOM) text. Invalid encoding.",
        ) from e
    reader = csv.DictReader(io.StringIO(content))
    rows = list(reader)
    if not rows:
        return {"imported": 0, "skipped_duplicates": 0, "message": "CSV has no data rows"}
    inserted = 0
    skipped = 0
    try:
        for row in rows:
            # Map CSV headers (case-insensitive, strip) to model fields; truncate to column max length
            data = {}
            for key, value in row.items():
                clean_key = key.strip().strip('"').lower()
                if clean_key in _CSV_TO_FIELD:
                    field = _CSV_TO_FIELD[clean_key]
                    val = (value.strip() if value else None) or None
                    data[field] = _trunc(val, _CSV_FIELD_MAX_LEN[field]) if val else None
            if not data.get("catalog_number") and not data.get("release_title"):
                continue
            catalog_number = (data.get("catalog_number") or "")[:32]
            isrc = data.get("isrc")
            track_title = data.get("track_title")
            mix_title = data.get("mix_title")
            # Skip duplicates: match by (catalog_number, isrc) or by (catalog_number, track_title, mix_title) when isrc empty
            existing = None
            if isrc:
                existing = db.query(CatalogTrack).filter(
                    CatalogTrack.catalog_number == catalog_number,
                    CatalogTrack.isrc == isrc,
                ).first()
            else:
                existing = db.query(CatalogTrack).filter(
                    CatalogTrack.catalog_number == catalog_number,
                    CatalogTrack.track_title == track_title,
                    CatalogTrack.mix_title == mix_title,
                ).first()
            if existing:
                skipped += 1
                continue
            db.add(
                CatalogTrack(
                    catalog_number=catalog_number,
                    release_title=(data.get("release_title") or "")[:300],
                    pre_order_date=_parse_date(data.get("pre_order_date")),
                    release_date=_parse_date(data.get("release_date")),
                    upc=data.get("upc"),
                    isrc=isrc,
                    original_artists=data.get("original_artists"),
                    original_first_last=data.get("original_first_last"),
                    remix_artists=data.get("remix_artists"),
                    remix_first_last=data.get("remix_first_last"),
                    track_title=track_title,
                    mix_title=mix_title,
                    duration=data.get("duration"),
                )
            )
            inserted += 1
        db.commit()
    except SQLAlchemyError as e:
        db.rollback()
        logger.exception("Catalog import: database error")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Database error during import. You can copy this message for support: {e!s}",
        ) from e
    msg = f"Imported {inserted} catalog track(s)."
    if skipped:
        msg += f" Skipped {skipped} duplicate(s)."
    return {"imported": inserted, "skipped_duplicates": skipped, "message": msg}


def _normalize_name(s: str) -> str:
    """Normalize for matching: strip, lower, collapse spaces."""
    if not s:
        return ""
    return " ".join(s.strip().lower().split())


def _artist_match_keys(artist: Artist) -> set[str]:
    """Build set of normalized strings to match catalog artist names against (name, artist_brand, artist_brands, full_name)."""
    keys = set()
    if artist.name:
        keys.add(_normalize_name(artist.name))
    try:
        extra = json.loads(artist.extra_json or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        extra = {}
    for field in ("artist_brand", "full_name"):
        val = extra.get(field)
        if val and isinstance(val, str):
            keys.add(_normalize_name(val))
    for b in extra.get("artist_brands") or []:
        if b and isinstance(b, str):
            keys.add(_normalize_name(b))
    return keys


def _artist_brand(artist: Artist) -> str:
    """Return display brand for an artist: extra_json.artist_brand or first artist_brands or name."""
    try:
        extra = json.loads(artist.extra_json or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        extra = {}
    brand = (extra.get("artist_brand") or "").strip()
    if brand:
        return brand
    brands = extra.get("artist_brands")
    if brands and isinstance(brands, list):
        for b in brands:
            if b and isinstance(b, str) and b.strip():
                return b.strip()
    return (artist.name or "").strip()


@router.post("/admin/releases/sync-from-catalog", response_model=dict)
def sync_releases_from_catalog(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    """
    Match catalog tracks (release_title + original_artists) to artists by name/artist_brand/full_name.
    Create Release rows for each catalog release that matches an artist, skipping duplicates.
    """
    require_admin(user)
    artists = db.query(Artist).all()
    artist_keys: list[tuple[int, set[str]]] = [(a.id, _artist_match_keys(a)) for a in artists]

    # Distinct (release_title, original_artists) from catalog; take first row per release_title
    tracks = db.query(CatalogTrack.release_title, CatalogTrack.original_artists).distinct().all()
    # Dedupe by release_title
    by_title: dict[str, str | None] = {}
    for title, orig in tracks:
        if not title:
            continue
        title = title.strip()
        if title not in by_title:
            by_title[title] = (orig.strip() if orig else None) or None

    created = 0
    skipped = 0
    unmatched = 0

    for release_title, original_artists in by_title.items():
        # Parse artist names from catalog (comma or & separated)
        if not original_artists:
            unmatched += 1
            continue
        parts = []
        for sep in (",", "&", ";"):
            if sep in original_artists:
                parts = [p.strip() for p in original_artists.split(sep) if p.strip()]
                break
        if not parts:
            parts = [original_artists.strip()]
        normalized_parts = {_normalize_name(p) for p in parts if _normalize_name(p)}

        matched_artist_ids: list[int] = [aid for aid, keys in artist_keys if keys & normalized_parts]

        if not matched_artist_ids:
            # Create release without artist so admin can assign later
            existing = db.query(Release).filter(Release.title == release_title).first()
            if existing:
                skipped += 1
            else:
                db.add(
                    Release(
                        artist_id=None,
                        title=release_title,
                        status="from_catalog",
                        file_path=None,
                    )
                )
                created += 1
            unmatched += 1
            continue

        existing = (
            db.query(Release)
            .options(joinedload(Release.artists))
            .filter(Release.title == release_title)
            .first()
        )
        if existing:
            has_artists = existing.artist_id or existing.artists
            if has_artists and (
                (existing.artist_id and existing.artist_id in matched_artist_ids)
                or any(a.id in matched_artist_ids for a in existing.artists)
            ):
                skipped += 1
                continue
            # Existing release with no artists (unmatched placeholder): assign matched artists
            if not has_artists:
                existing.artist_id = matched_artist_ids[0]
                existing.artists = [db.get(Artist, aid) for aid in matched_artist_ids]
                existing.artists = [a for a in existing.artists if a]
                created += 1
                continue

        release = Release(
            artist_id=matched_artist_ids[0],
            title=release_title,
            status="from_catalog",
            file_path=None,
        )
        db.add(release)
        db.flush()
        for aid in matched_artist_ids:
            a = db.get(Artist, aid)
            if a:
                release.artists.append(a)
        created += 1

    db.commit()
    return {
        "created": created,
        "skipped_duplicate": skipped,
        "unmatched": unmatched,
        "message": f"Created {created} release(s), skipped {skipped} duplicate(s), {unmatched} catalog release(s) had no matching artist.",
    }


@router.post("/admin/catalog-tracks/sync-original-artists-from-artists", response_model=dict)
def sync_original_artists_from_artists(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    """
    For each catalog release (by release_title), match to an artist by current original_artists
    (name/artist_brand/full_name). Update catalog_tracks.original_artists to that artist's Brand
    (artist_brand or name) so catalog display matches the Artists table.
    """
    require_admin(user)
    artists = db.query(Artist).all()
    artist_keys: list[tuple[int, set[str]]] = [(a.id, _artist_match_keys(a)) for a in artists]
    artist_id_to_brand: dict[int, str] = {a.id: _artist_brand(a) for a in artists}

    tracks = db.query(CatalogTrack.release_title, CatalogTrack.original_artists).distinct().all()
    by_title: dict[str, str | None] = {}
    for title, orig in tracks:
        if not title:
            continue
        title = title.strip()
        if title not in by_title:
            by_title[title] = (orig.strip() if orig else None) or None

    updated = 0
    unmatched = 0

    for release_title, original_artists in by_title.items():
        if not original_artists:
            unmatched += 1
            continue
        parts = []
        for sep in (",", "&", ";"):
            if sep in original_artists:
                parts = [p.strip() for p in original_artists.split(sep) if p.strip()]
                break
        if not parts:
            parts = [original_artists.strip()]
        normalized_parts = {_normalize_name(p) for p in parts if _normalize_name(p)}

        matched_artist_id: int | None = None
        for artist_id, keys in artist_keys:
            if keys & normalized_parts:
                matched_artist_id = artist_id
                break

        if not matched_artist_id:
            unmatched += 1
            continue

        brand = artist_id_to_brand.get(matched_artist_id) or ""
        n = (
            db.query(CatalogTrack)
            .filter(CatalogTrack.release_title == release_title)
            .update({CatalogTrack.original_artists: brand}, synchronize_session=False)
        )
        updated += n

    db.commit()
    return {
        "updated": updated,
        "unmatched": unmatched,
        "message": f"Updated original_artists to artist Brand on {updated} catalog track(s). {unmatched} release(s) had no matching artist.",
    }


def _slug_for_email(name: str) -> str:
    """Build a safe slug from artist name for placeholder email."""
    s = "".join(c if c.isalnum() or c in " -" else " " for c in (name or "").strip())
    return "-".join(s.lower().split())[:50] or "artist"


@router.post("/admin/catalog-tracks/create-missing-original-artists", response_model=dict)
def create_missing_original_artists(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    """
    For each distinct Original Artist name in the catalog that does not match any
    artist (by name/artist_brand/artist_brands/full_name), create a new artist record
    with that name as brand so they appear in the artists list and can be matched later.
    """
    require_admin(user)
    artists = db.query(Artist).all()
    artist_keys: list[tuple[int, set[str]]] = [(a.id, _artist_match_keys(a)) for a in artists]
    all_match_keys: set[str] = set()
    for _aid, keys in artist_keys:
        all_match_keys |= keys

    existing_emails = {a.email.lower() for a in artists}

    tracks = db.query(CatalogTrack.original_artists).filter(CatalogTrack.original_artists.isnot(None)).distinct().all()
    raw_names: set[str] = set()
    for (orig,) in tracks:
        if not orig or not orig.strip():
            continue
        for sep in (",", "&", ";"):
            if sep in orig:
                for p in orig.split(sep):
                    if p.strip():
                        raw_names.add(p.strip())
                break
        else:
            raw_names.add(orig.strip())

    created = 0
    for raw in sorted(raw_names):
        norm = _normalize_name(raw)
        if not norm or norm in all_match_keys:
            continue
        base_slug = _slug_for_email(raw)
        email = f"original-artist-{base_slug}@label.local"
        idx = 0
        while email.lower() in existing_emails:
            idx += 1
            email = f"original-artist-{base_slug}-{idx}@label.local"
        existing_emails.add(email.lower())
        extra = {"artist_brand": raw, "artist_brands": [raw]}
        db.add(
            Artist(
                name=raw,
                email=email,
                notes="",
                extra_json=json.dumps(extra),
            )
        )
        all_match_keys.add(norm)
        created += 1

    db.commit()
    return {
        "created": created,
        "message": f"Created {created} artist(s) for catalog Original Artists that had no matching Brand.",
    }


@router.post("/admin/artists/merge", response_model=dict)
def merge_artists(
    payload: dict,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    """
    Merge multiple artists into one: add all brands from source artists to the target artist,
    then deactivate source artists (releases/tasks stay on source unless reassigned separately).
    Body: { "target_artist_id": int, "source_artist_ids": [int] }
    """
    require_admin(user)
    target_id = payload.get("target_artist_id")
    source_ids = payload.get("source_artist_ids") or []
    if target_id is None or not isinstance(source_ids, list) or not source_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Body must include target_artist_id and non-empty source_artist_ids",
        )
    target = db.query(Artist).filter(Artist.id == int(target_id)).first()
    if not target:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Target artist not found")
    target_id = target.id
    if target_id in source_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Target cannot be in source_artist_ids",
        )
    try:
        target_extra = json.loads(target.extra_json or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        target_extra = {}
    brands_set: set[str] = set()
    for b in target_extra.get("artist_brands") or []:
        if b and isinstance(b, str) and b.strip():
            brands_set.add(b.strip())
    if (target_extra.get("artist_brand") or "").strip():
        brands_set.add((target_extra.get("artist_brand") or "").strip())
    if (target.name or "").strip():
        brands_set.add((target.name or "").strip())

    merged_count = 0
    for sid in source_ids:
        try:
            aid = int(sid)
        except (TypeError, ValueError):
            continue
        if aid == target_id:
            continue
        source = db.query(Artist).filter(Artist.id == aid).first()
        if not source:
            continue
        try:
            extra = json.loads(source.extra_json or "{}") or {}
        except (json.JSONDecodeError, TypeError):
            extra = {}
        for b in extra.get("artist_brands") or []:
            if b and isinstance(b, str) and b.strip():
                brands_set.add(b.strip())
        if (extra.get("artist_brand") or "").strip():
            brands_set.add((extra.get("artist_brand") or "").strip())
        if (source.name or "").strip():
            brands_set.add((source.name or "").strip())
        source.is_active = False
        merged_count += 1

    target_extra["artist_brands"] = sorted(brands_set)
    if target_extra["artist_brands"]:
        target_extra["artist_brand"] = target_extra["artist_brands"][0]
    target.extra_json = json.dumps(target_extra)
    db.commit()
    return {
        "merged": merged_count,
        "target_artist_id": target_id,
        "brands_count": len(brands_set),
        "message": f"Merged {merged_count} artist(s) into artist {target_id}; target now has {len(brands_set)} brand(s). Source artists deactivated.",
    }


# ---- Social and Connectors routes removed (rebuild from scratch) ----
# Placeholder so next section comment is not orphaned

# ---- Campaigns (unified: social + Mailchimp + WordPress) ----
# (Social/connector routes removed - rebuild from scratch)

@router.get("/admin/campaigns", response_model=list[CampaignOut])
def list_campaigns(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
    status: str | None = Query(None),
    limit: int = Query(100, le=200),
    offset: int = Query(0, ge=0),
) -> list[CampaignOut]:
    require_admin(user)
    campaigns = list_campaigns_svc(db, status=status, limit=limit, offset=offset)
    return [CampaignOut.from_campaign(c) for c in campaigns]


@router.get("/admin/campaigns/{campaign_id}", response_model=CampaignOut)
def get_campaign_route(
    campaign_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> CampaignOut:
    require_admin(user)
    campaign = get_campaign(db, campaign_id)
    if not campaign:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Campaign not found")
    return CampaignOut.from_campaign(campaign)


@router.post("/admin/campaigns", response_model=CampaignOut)
def create_campaign_route(
    payload: CampaignCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> CampaignOut:
    require_admin(user)
    targets = [
        {"channel_type": t.channel_type, "external_id": t.external_id, "channel_payload": t.channel_payload}
        for t in payload.targets
    ]
    campaign = create_campaign_svc(
        db,
        name=payload.name,
        title=payload.title,
        body_text=payload.body_text,
        body_html=payload.body_html,
        media_url=payload.media_url,
        artist_id=payload.artist_id,
        targets=targets,
    )
    return CampaignOut.from_campaign(campaign)


# (Social/connector routes removed - rebuild from scratch)


# Allowed image extensions for campaign media upload
_CAMPAIGN_MEDIA_EXT = {".jpg", ".jpeg", ".png", ".gif", ".webp"}

# Allowed image extensions for campaign media upload
_CAMPAIGN_MEDIA_EXT = {".jpg", ".jpeg", ".png", ".gif", ".webp"}

@router.post("/admin/campaigns/upload-media")
def upload_campaign_media(
    request: Request,
    file: UploadFile = File(...),
    user: UserContext = Depends(get_current_user),
) -> dict:
    """Upload an image for use as campaign media. Returns public URL for the image."""
    require_admin(user)
    ext = (os.path.splitext(file.filename or "")[1] or "").lower()
    if ext not in _CAMPAIGN_MEDIA_EXT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid file type. Allowed: {', '.join(_CAMPAIGN_MEDIA_EXT)}",
        )
    media_dir = os.path.join(settings.upload_dir, "campaign_media")
    os.makedirs(media_dir, exist_ok=True)
    filename = f"{uuid.uuid4().hex}{ext}"
    path = os.path.join(media_dir, filename)
    with open(path, "wb") as out:
        out.write(file.file.read())
    base = str(request.base_url).rstrip("/")
    if base.endswith("/api"):
        pass
    elif not base.endswith("/api/"):
        base = base + "/api"
    url = f"{base}/media/campaigns/{filename}"
    return {"url": url}


@router.get("/media/campaigns/{filename}")
def serve_campaign_media(filename: str):
    """Serve uploaded campaign image. Public so social platforms can fetch the URL."""
    if ".." in filename or "/" in filename or "\\" in filename:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid filename")
    ext = (os.path.splitext(filename)[1] or "").lower()
    if ext not in _CAMPAIGN_MEDIA_EXT:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    path = os.path.join(settings.upload_dir, "campaign_media", filename)
    if not os.path.isfile(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    media_types = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".gif": "image/gif", ".webp": "image/webp"}
    return FileResponse(path, media_type=media_types.get(ext, "application/octet-stream"))


@router.patch("/admin/campaigns/{campaign_id}", response_model=CampaignOut)
def update_campaign_route(
    campaign_id: int,
    payload: CampaignUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> CampaignOut:
    require_admin(user)
    kwargs = payload.model_dump(exclude_unset=True)
    campaign = update_campaign_svc(db, campaign_id, **kwargs)
    if not campaign:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Campaign not found or not editable")
    return CampaignOut.from_campaign(campaign)


@router.delete("/admin/campaigns/{campaign_id}")
def delete_campaign_route(
    campaign_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    require_admin(user)
    if not delete_campaign(db, campaign_id):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Campaign not found or cannot be deleted")
    return {"ok": True}


@router.post("/admin/campaigns/{campaign_id}/schedule", response_model=CampaignOut)
def schedule_campaign_route(
    campaign_id: int,
    payload: ScheduleCampaignRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> CampaignOut:
    require_admin(user)
    campaign = get_campaign(db, campaign_id)
    if not campaign:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Campaign not found")
    if campaign.status != "draft":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only draft campaigns can be scheduled")
    scheduled_at = payload.scheduled_at
    campaign = set_campaign_scheduled(db, campaign_id, scheduled_at)
    if not campaign:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Could not schedule campaign")
    return CampaignOut.from_campaign(campaign)


@router.post("/admin/campaigns/{campaign_id}/cancel", response_model=CampaignOut)
def cancel_campaign_schedule_route(
    campaign_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> CampaignOut:
    require_admin(user)
    campaign = cancel_schedule(db, campaign_id)
    if not campaign:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Campaign not found or not scheduled")
    return CampaignOut.from_campaign(campaign)



