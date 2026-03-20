import csv
import hashlib
import html
import io
import json
import logging
import os
import secrets
import uuid
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urlencode

import httpx

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile, status
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse, Response
from sqlalchemy import desc, func, or_, text, update
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, joinedload

from app.api.deps import (
    LM_FORBIDDEN_ARTIST_DETAIL,
    get_current_user,
    get_current_lm_user,
    require_admin,
    require_artist,
    security,
)
from app.core.config import settings
from app.db.session import Base, engine, get_db
from app.models import models as models_module  # noqa: F401 - register all tables with Base
from app.models.models import (
    Artist,
    ArtistActivityLog,
    ArtistRegistrationToken,
    ArtistMedia,
    AutomationTask,
    Campaign,
    CampaignRequest,
    CatalogTrack,
    DemoConfirmationToken,
    DemoSubmission,
    HubConnector,
    LabelInboxMessage,
    LabelInboxThread,
    MailingList,
    MailingSubscriber,
    PasswordResetToken,
    PendingRelease,
    PendingReleaseComment,
    PendingReleaseToken,
    Release,
    release_artists_table,
    SocialConnection,
    SystemLog,
    User,
    UserIdentity,
)
from app.schemas.schemas import (
    AgentDefinitionOut,
    AgentPlanOut,
    AgentPlanRequest,
    ArtistActivityLogOut,
    ArtistCreate,
    ArtistDashboard,
    ArtistMediaListResponse,
    ArtistMediaOut,
    ArtistOut,
    ArtistSelfUpdate,
    ArtistUpdate,
    CampaignRequestCreate,
    CampaignRequestOut,
    CampaignRequestUpdate,
    LinktreeLink,
    LinktreeOut,
    LinktreeRelease,
    CampaignCreate,
    CampaignOut,
    CampaignUpdate,
    CatalogTrackOut,
    DemoConfirmFormInfo,
    DemoConfirmSubmit,
    DemoSubmissionApproveRequest,
    DemoSubmissionCreate,
    DemoSubmissionOut,
    DemoSubmissionUpdate,
    EmailRateLimitStatus,
    EmailRecipientHistoryOut,
    ScheduleCampaignRequest,
    SendEmailRequest,
    SendEmailResponse,
    SystemSettingsMailTestRequest,
    SystemSettingsMailTestResponse,
    _artist_extra_from_model,
    ForgotPasswordRequest,
    ArtistChangePasswordRequest,
    ArtistLoginRequest,
    ArtistPortalInviteBulkError,
    ArtistPortalInviteBulkResponse,
    ArtistPortalInviteResponse,
    ArtistRegistrationCompleteRequest,
    ArtistRegistrationCompleteResponse,
    ArtistRegistrationFormInfo,
    LoginActivityOut,
    GrooverInviteRequest,
    GrooverInviteResponse,
    ArtistSetPasswordRequest,
    AdminDashboardStatsOut,
    LoginStatsOut,
    LabelInboxMessageOut,
    LabelInboxReply,
    LabelInboxSend,
    LabelInboxThreadDetailOut,
    LabelInboxThreadOut,
    LoginRequest,
    PendingReleaseFormInfo,
    PendingReleaseActionResponse,
    PendingReleaseCommentCreate,
    PendingReleaseCommentOut,
    PendingReleaseDetailOut,
    PendingReleaseImageOptionOut,
    PendingReleaseNotificationSettingsUpdate,
    PendingReleaseOut,
    PendingReleaseReferenceUploadOut,
    PendingReleaseReminderResponse,
    PendingReleaseSelectImageRequest,
    PendingReleaseSubmit,
    ReleaseOut,
    ResetPasswordRequest,
    ReleaseUpdateArtists,
    SystemSettingsMailUpdate,
    SystemLogOut,
    SystemSettingsOut,
    TaskOut,
    TokenResponse,
    UserContext,
    UserCreate,
    UserIdentityOut,
    UserOut,
    UserUpdate,
)
from app.services.auth import create_access_token, hash_password, permissions_for_role, verify_password
from app.services.email_service import (
    get_emails_sent_this_hour,
    is_email_configured,
    send_email as send_email_service,
    send_test_smtp_email,
    test_smtp_connection,
)
from app.services.mail_settings import build_mail_config, get_effective_mail_config_for_api, save_mail_settings
from app.services.system_log import append_system_log
from app.services.agent_supervisor import build_agent_plan, get_agent_registry
from app.services.backup_service import export_database, restore_database
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

_GOOGLE_AUTH_SCOPES = [
    "openid",
    "email",
    "profile",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/gmail.compose",
]


def _artist_portal_url() -> str:
    return (settings.artist_portal_base_url or "").strip() or "https://artists.zalmanim.com"


def _artist_registration_link(raw_token: str) -> str:
    portal_url = _artist_portal_url().rstrip("/")
    return f"{portal_url}/#/artist-registration?token={raw_token}"


def _create_pending_release_for_demo(db: Session, item: DemoSubmission) -> PendingRelease:
    """Create a PendingRelease row for an approved demo so it appears in Pending Release. Idempotent: does nothing if one already exists."""
    existing = db.query(PendingRelease).filter(PendingRelease.demo_submission_id == item.id).first()
    if existing:
        return existing
    fields = _safe_json_dict(item.fields_json)
    release_title = (fields.get("track_name") or "").strip() or "Pending artist confirmation"
    pr = PendingRelease(
        campaign_request_id=None,
        demo_submission_id=item.id,
        artist_id=item.artist_id,
        artist_name=(item.artist_name or "").strip() or "Artist",
        artist_email=(item.email or "").strip().lower() or "unknown@example.com",
        artist_data_json="{}",
        release_title=release_title[:300],
        release_data_json="{}",
        status="pending",
    )
    db.add(pr)
    db.flush()
    return pr


def _generate_temporary_password(length: int = 12) -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@$%*"
    return "".join(secrets.choice(alphabet) for _ in range(length))

_FACEBOOK_AUTH_SCOPES = ["email", "public_profile"]
_ALLOWED_USER_ROLES = {"admin", "manager", "artist"}
_ALLOWED_DEMO_STATUSES = {"demo", "in_review", "approved", "rejected", "pending_release"}
_DEMO_MAILING_LIST_NAME = "Artists Demo Intake"
_ALLOWED_PENDING_RELEASE_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}


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


def _artist_token_response(artist: Artist) -> TokenResponse:
    """Token for artist portal login (artists table credentials). JWT sub is 'artist:{id}'."""
    return TokenResponse(
        access_token=create_access_token(f"artist:{artist.id}"),
        role="artist",
        email=artist.email,
        full_name=artist.name,
        permissions=permissions_for_role("artist"),
    )



def _touch_user_login(db: Session, user: User) -> None:
    now = datetime.now(timezone.utc)
    user.last_login_at = now
    db.commit()
    db.refresh(user)


def _touch_artist_login(db: Session, artist: Artist) -> None:
    now = datetime.now(timezone.utc)
    artist.last_login_at = now
    db.commit()
    db.refresh(artist)


def _ensure_artist_reset_user(db: Session, artist: Artist) -> User | None:
    if not artist.is_active or not artist.password_hash:
        return None

    user = (
        db.query(User)
        .filter(func.lower(User.email) == artist.email.lower())
        .first()
    )
    if user:
        changed = False
        if user.artist_id != artist.id:
            user.artist_id = artist.id
            changed = True
        if user.role != "artist":
            user.role = "artist"
            changed = True
        if not user.is_active:
            user.is_active = True
            changed = True
        if user.password_hash != artist.password_hash:
            user.password_hash = artist.password_hash
            changed = True
        if not user.full_name:
            user.full_name = artist.name
            changed = True
        if changed:
            db.flush()
        return user

    user = User(
        email=artist.email.lower(),
        full_name=artist.name,
        password_hash=artist.password_hash,
        role="artist",
        artist_id=artist.id,
        is_active=True,
    )
    db.add(user)
    db.flush()
    return user



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


def _default_demo_approval_subject(artist_name: str) -> str:
    safe_name = (artist_name or "there").strip()
    return f"Your demo was approved, {safe_name}"


def _default_demo_approval_body(artist_name: str) -> str:
    safe_name = (artist_name or "there").strip()
    return (
        f"Hi {safe_name},\n\n"
        "Thanks for sending your demo.\n\n"
        "We reviewed it and would like to move forward with you. "
        "Please reply to this email so we can continue the next steps.\n\n"
        "Best regards"
    )


def _default_demo_receipt_subject(artist_name: str) -> str:
    safe_name = (artist_name or "there").strip()
    return f"Demo received from {safe_name}"


def _default_demo_receipt_body(item: DemoSubmission) -> str:
    recipient_name = (item.contact_name or item.artist_name or "there").strip()
    lines = [
        f"Hi {recipient_name},",
        "",
        "We received your demo and it will enter treatment soon.",
        "",
        "Submission summary:",
    ]
    for label, value in _build_demo_submission_summary(item):
        lines.append(f"- {label}: {value}")
    lines.extend([
        "",
        "Thanks for sending your music to Zalmanim.",
        "",
        "Best regards,",
        "Zalmanim",
    ])
    return "\n".join(lines)


def _default_demo_rejection_subject(artist_name: str) -> str:
    safe_name = (artist_name or "there").strip()
    return f"Thank you for your demo submission, {safe_name}"


def _default_demo_rejection_body(artist_name: str) -> str:
    portal_url = _artist_portal_url()
    website_url = (settings.zalmanim_website_url or "").strip() or "https://zalmanim.com"
    safe_name = (artist_name or "there").strip()
    return (
        f"Hi {safe_name},\n\n"
        "Thank you for sending us your music. We received it with respect and appreciate you thinking of us.\n\n"
        "After careful consideration, we feel it does not quite fit the musical direction of our labels at this time. "
        "We would be happy to receive more demos from you in the future in the hope they may align with our line.\n\n"
        f"Our website: {website_url}\n"
        f"Artist portal (submit demos): {portal_url}\n\n"
        "Best regards,\nZalmanim"
    )


def _apply_demo_rejection_placeholders(text: str, item: DemoSubmission) -> str:
    portal_url = _artist_portal_url()
    website_url = (settings.zalmanim_website_url or "").strip() or "https://zalmanim.com"
    safe_name = (item.artist_name or "there").strip()
    return (
        text.replace("{artist_name}", safe_name)
        .replace("{artist_portal_url}", portal_url)
        .replace("{zalmanim_website}", website_url)
    )


def _get_demo_approval_subject_and_body(artist_name: str) -> tuple[str, str]:
    """Resolve default demo approval subject and body from settings or built-in defaults. Placeholder: {artist_name}."""
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("demo_approval_subject") or "").strip()
    body = (mail.get("demo_approval_body") or "").strip()
    if not subject:
        subject = _default_demo_approval_subject(artist_name)
    else:
        subject = subject.replace("{artist_name}", (artist_name or "there").strip())
    if not body:
        body = _default_demo_approval_body(artist_name)
    else:
        body = body.replace("{artist_name}", (artist_name or "there").strip())
    return subject, body


def _get_demo_receipt_subject_and_body(item: DemoSubmission) -> tuple[str, str]:
    """Resolve demo receipt subject and body from settings or defaults."""
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("demo_receipt_subject") or "").strip()
    body = (mail.get("demo_receipt_body") or "").strip()
    replacements = {
        "{recipient_name}": (item.contact_name or item.artist_name or "there").strip(),
        "{artist_name}": (item.artist_name or "there").strip(),
        "{contact_name}": (item.contact_name or "").strip(),
        "{email}": (item.email or "").strip(),
        "{phone}": (item.phone or "").strip(),
        "{genre}": (item.genre or "").strip(),
        "{city}": (item.city or "").strip(),
        "{links}": ", ".join(str(link).strip() for link in _safe_json_list(item.links_json) if str(link).strip()),
        "{message}": (item.message or "").strip(),
        "{source}": (item.source or "").strip(),
        "{submission_summary}": "\n".join(
            f"- {label}: {value}" for label, value in _build_demo_submission_summary(item)
        ),
    }
    if not subject:
        subject = _default_demo_receipt_subject(item.artist_name)
    if not body:
        body = _default_demo_receipt_body(item)
    for token, value in replacements.items():
        subject = subject.replace(token, value)
        body = body.replace(token, value)
    return subject, body


def _default_portal_invite_subject() -> str:
    return "Your Zalmanim Artists Portal access"


def _default_portal_invite_body(display_name: str, portal_url: str, username: str, temporary_password: str) -> str:
    return (
        f"Hi {display_name},\n\n"
        "Your access to the Zalmanim Artists Portal is ready.\n\n"
        "Inside the portal you can update your profile, upload media, upload releases, submit demos, "
        "and change your password.\n\n"
        f"Portal link: {portal_url}\n"
        f"Username: {username}\n"
        f"Temporary password: {temporary_password}\n\n"
        "Please sign in and change your password after your first login.\n\n"
        "If you have any questions, reply to this email.\n"
    )


def _get_portal_invite_subject_and_body(
    display_name: str, portal_url: str, username: str, temporary_password: str
) -> tuple[str, str]:
    """Resolve portal invite subject and body from settings or defaults. Placeholders: {display_name}, {portal_url}, {username}, {temporary_password}."""
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("portal_invite_subject") or "").strip()
    body = (mail.get("portal_invite_body") or "").strip()
    if not subject:
        subject = _default_portal_invite_subject()
    else:
        subject = (
            subject.replace("{display_name}", display_name)
            .replace("{portal_url}", portal_url)
            .replace("{username}", username)
            .replace("{temporary_password}", temporary_password)
        )
    if not body:
        body = _default_portal_invite_body(display_name, portal_url, username, temporary_password)
    else:
        body = (
            body.replace("{display_name}", display_name)
            .replace("{portal_url}", portal_url)
            .replace("{username}", username)
            .replace("{temporary_password}", temporary_password)
        )
    return subject, body


def _default_groover_invite_subject() -> str:
    return "Thanks for reaching out on Groover"


def _default_groover_invite_body(display_name: str, registration_url: str, portal_url: str) -> str:
    return (
        f"Hi {display_name},\n\n"
        "I hope you are doing well. I am Simon from Zalmanim Music,\n"
        "and I would like to introduce you to our work.\n\n"
        "We are a music label and an internet magazine that works with electronic music, focusing on underground dance music such as Techno, Psytech, and sometimes some variants of house. "
        "We are also releasing some Ambient and chill out to ease the mind.\n\n"
        "We also work on a new label focused only on Psytech and Prog Trance named SiYu Music.\n\n"
        "We also have an internet magazine at www.zalmanim.com and we promote music on our YouTube channel https://www.youtube.com/channel/UCa24JK3VKaYJwVlQCiSqzqg\n\n"
        "I invite you to listen to our music and be impressed by it. You can\n"
        "find out our label music at the following link:\n"
        "https://soundcloud.com/zalmanim\n\n"
        "We've been in contact over Groover.\n\n"
        "To continue, please complete your artist registration form here:\n"
        f"{registration_url}\n\n"
        "Once you complete the form, you will be able to sign in to our artist portal:\n"
        f"{portal_url}\n\n"
        "So, if you are interested in releasing music with the label, please\n"
        "send me some unreleased music.\n\n"
        "If you are interested in sharing your music on our YouTube channel,\n"
        "please send me some artwork and the music file.\n\n"
        "If you're interested in an interview or short article, please send us a short bio and pictures or any written material, and we will see if it suits both of us.\n\n"
        "Peace,\n"
        "Best regards,\n"
        "Simon Rosenfeld\n"
        "Founder & A&R | Zalmanim & SiYu Rec\n"
        "🌐 www.zalmanim.com\n\n"
        "🎧 Join our SoundCloud promo group:\n"
        "https://influenceplanner.com/invite/Anyone\n\n"
        "💬 Join our WhatsApp artist community:\n"
        "https://chat.whatsapp.com/Bc4EpRLdpIwEV7lAzYzdSy\n"
    )


def _get_groover_invite_subject_and_body(
    display_name: str,
    registration_url: str,
    portal_url: str,
) -> tuple[str, str]:
    """Resolve Groover invite email from settings or defaults."""
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("groover_invite_subject") or "").strip()
    body = (mail.get("groover_invite_body") or "").strip()
    replacements = {
        "{display_name}": display_name,
        "{registration_url}": registration_url,
        "{portal_url}": portal_url,
    }
    if not subject:
        subject = _default_groover_invite_subject()
    if not body:
        body = _default_groover_invite_body(display_name, registration_url, portal_url)
    for token, value in replacements.items():
        subject = subject.replace(token, value)
        body = body.replace(token, value)
    return subject, body


def _build_groover_invite_html(
    *,
    body_text: str,
    registration_url: str,
    portal_url: str,
) -> str:
    escaped = html.escape(body_text)
    registration_prompt = html.escape("To continue, please complete your artist registration form here:")
    portal_prompt = html.escape("Once you complete the form, you will be able to sign in to our artist portal:")
    registration_placeholder = "__GROOVER_REGISTRATION_LINK__"
    portal_placeholder = "__GROOVER_PORTAL_LINK__"

    escaped = escaped.replace(
        registration_prompt,
        '<span style="color:#c62828;font-weight:700;">'
        "To continue, please complete your artist registration form here:"
        "</span>",
    )
    escaped = escaped.replace(
        portal_prompt,
        '<span style="color:#c62828;font-weight:700;">'
        "Once you complete the form, you will be able to sign in to our artist portal:"
        "</span>",
    )
    escaped = escaped.replace(html.escape(registration_url), registration_placeholder)
    escaped = escaped.replace(html.escape(portal_url), portal_placeholder)

    body_html = "<p>" + escaped.replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
    body_html = body_html.replace(
        registration_placeholder,
        f'<a href="{html.escape(registration_url)}" '
        'style="color:#c62828;font-weight:700;text-decoration:underline;">'
        "Complete your artist registration form"
        "</a>",
    )
    body_html = body_html.replace(
        portal_placeholder,
        f'<a href="{html.escape(portal_url)}" style="font-weight:600;text-decoration:underline;">'
        "Sign in to the artist portal"
        "</a>",
    )
    return body_html


def _default_update_profile_invite_subject() -> str:
    return "Update your artist page and see your releases"


def _default_update_profile_invite_body(
    display_name: str,
    portal_url: str,
    username: str,
    temporary_password: str | None,
) -> str:
    password_line = (
        f"Temporary password: {temporary_password}"
        if (temporary_password or "").strip()
        else "Use your existing password."
    )
    return (
        f"Hi {display_name},\n\n"
        "We'd love you to update your artist page and see your releases on the label.\n\n"
        f"Portal: {portal_url}\n"
        f"Username: {username}\n"
        f"{password_line}\n\n"
        "Please sign in, change your password if needed, and update your profile and releases.\n\n"
        "If you have any questions, reply to this email.\n"
    )


def _get_update_profile_invite_subject_and_body(
    display_name: str,
    portal_url: str,
    username: str,
    temporary_password: str | None,
) -> tuple[str, str]:
    """Resolve update-profile invite subject and body from settings or defaults."""
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("update_profile_invite_subject") or "").strip()
    body = (mail.get("update_profile_invite_body") or "").strip()
    password_line = (
        f"Temporary password: {temporary_password}"
        if (temporary_password or "").strip()
        else "Use your existing password."
    )
    replacements = {
        "{display_name}": display_name,
        "{portal_url}": portal_url,
        "{username}": username,
        "{temporary_password}": (temporary_password or "").strip(),
        "{password_line}": password_line,
    }
    if not subject:
        subject = _default_update_profile_invite_subject()
    if not body:
        body = _default_update_profile_invite_body(display_name, portal_url, username, temporary_password)
    for token, value in replacements.items():
        subject = subject.replace(token, value)
        body = body.replace(token, value)
    return subject, body


def _default_password_reset_subject() -> str:
    return "Password reset"


def _default_password_reset_body(reset_link: str, expiry_minutes: int) -> str:
    return (
        f"Use this link to reset your password (valid for {expiry_minutes} minutes):\n\n"
        f"{reset_link}\n\n"
        "If you did not request this, ignore this email."
    )


def _get_password_reset_subject_and_body(reset_link: str, expiry_minutes: int) -> tuple[str, str]:
    """Resolve password-reset subject and body from settings or defaults."""
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("password_reset_subject") or "").strip()
    body = (mail.get("password_reset_body") or "").strip()
    replacements = {
        "{reset_link}": reset_link,
        "{expiry_minutes}": str(expiry_minutes),
    }
    if not subject:
        subject = _default_password_reset_subject()
    if not body:
        body = _default_password_reset_body(reset_link, expiry_minutes)
    for token, value in replacements.items():
        subject = subject.replace(token, value)
        body = body.replace(token, value)
    return subject, body


def _get_demo_rejection_subject_and_body(item: DemoSubmission) -> tuple[str, str]:
    """Resolve rejection email subject and body from settings or defaults; replace placeholders."""
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("demo_rejection_subject") or "").strip()
    body = (mail.get("demo_rejection_body") or "").strip()
    if not subject:
        subject = _default_demo_rejection_subject(item.artist_name)
    else:
        subject = _apply_demo_rejection_placeholders(subject, item)
    if not body:
        body = _default_demo_rejection_body(item.artist_name)
    else:
        body = _apply_demo_rejection_placeholders(body, item)
    return subject, body


def _build_demo_submission_summary(item: DemoSubmission) -> list[tuple[str, str]]:
    fields = _safe_json_dict(item.fields_json)
    links = _safe_json_list(item.links_json)
    submission_links = ", ".join(
        str(link).strip() for link in links if str(link).strip()
    )
    return [
        ("Artist name", item.artist_name),
        ("Contact name", item.contact_name or "-"),
        ("Email", item.email),
        ("Phone", item.phone or "-"),
        ("Genre", item.genre or "-"),
        ("City", item.city or "-"),
        ("Links", submission_links or "-"),
        ("Message", item.message or "-"),
        ("Email consent", "Yes" if item.consent_to_emails else "No"),
        ("Source", item.source or "-"),
    ]


def _build_demo_receipt_subject(artist_name: str) -> str:
    safe_name = (artist_name or "there").strip()
    return f"Demo received from {safe_name}"


def _build_demo_receipt_body(item: DemoSubmission) -> str:
    recipient_name = (item.contact_name or item.artist_name or "there").strip()
    lines = [
        f"Hi {recipient_name},",
        "",
        "We received your demo and it will enter treatment soon.",
        "",
        "Submission summary:",
    ]
    for label, value in _build_demo_submission_summary(item):
        lines.append(f"- {label}: {value}")
    lines.extend([
        "",
        "Thanks for sending your music to Zalmanim.",
        "",
        "Best regards,",
        "Zalmanim",
    ])
    return "\n".join(lines)


def _build_demo_receipt_html(item: DemoSubmission) -> str:
    recipient_name = html.escape((item.contact_name or item.artist_name or "there").strip())
    rows = "\n".join(
        f"<tr><td style='padding:8px 12px;font-weight:600;border:1px solid #e5ddd2;'>{html.escape(label)}</td>"
        f"<td style='padding:8px 12px;border:1px solid #e5ddd2;'>{html.escape(value)}</td></tr>"
        for label, value in _build_demo_submission_summary(item)
    )
    return (
        f"<p>Hi {recipient_name},</p>"
        "<p>We received your demo and it will enter treatment soon.</p>"
        "<p><strong>Submission summary</strong></p>"
        "<table style='border-collapse:collapse;border:1px solid #e5ddd2;'>"
        f"{rows}"
        "</table>"
        "<p>Thanks for sending your music to Zalmanim.</p>"
        "<p>Best regards,<br/>Zalmanim</p>"
    )


def _ensure_demo_mailing_list(db: Session) -> MailingList:
    mailing_list = db.query(MailingList).filter(MailingList.name == _DEMO_MAILING_LIST_NAME).first()
    if mailing_list:
        return mailing_list
    mailing_list = MailingList(
        name=_DEMO_MAILING_LIST_NAME,
        description="Artists who submitted demos and consented to marketing and operational emails.",
        default_language="en",
    )
    db.add(mailing_list)
    db.flush()
    return mailing_list


def _upsert_demo_mailing_subscriber(db: Session, item: DemoSubmission) -> None:
    if not item.consent_to_emails:
        return
    mailing_list = _ensure_demo_mailing_list(db)
    subscriber = (
        db.query(MailingSubscriber)
        .filter(MailingSubscriber.list_id == mailing_list.id, MailingSubscriber.email == item.email)
        .first()
    )
    consent_source = (item.source_site_url or item.source or "demo_submission").strip() or "demo_submission"
    consent_at = item.consent_at or datetime.now(timezone.utc)
    display_name = (item.contact_name or item.artist_name or "").strip() or None
    notes = f"Auto-added from demo submission #{item.id}."
    if subscriber:
        subscriber.full_name = display_name
        subscriber.status = "subscribed"
        subscriber.consent_source = consent_source
        subscriber.consent_at = consent_at
        subscriber.unsubscribed_at = None
        subscriber.notes = notes
        return
    db.add(
        MailingSubscriber(
            list_id=mailing_list.id,
            email=item.email,
            full_name=display_name,
            status="subscribed",
            consent_source=consent_source,
            consent_at=consent_at,
            unsubscribe_token=secrets.token_urlsafe(24),
            notes=notes,
        )
    )


def _normalize_demo_status(value: str | None, *, allow_empty: bool = False) -> str | None:
    raw = (value or "").strip().lower()
    if not raw:
        return None if allow_empty else "demo"
    if raw not in _ALLOWED_DEMO_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported demo status: {value}",
        )
    return raw


def _serialize_demo_submission(item: DemoSubmission) -> DemoSubmissionOut:
    try:
        links = json.loads(item.links_json or "[]") or []
    except (json.JSONDecodeError, TypeError):
        links = []
    try:
        fields = json.loads(item.fields_json or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        fields = {}
    if not isinstance(fields, dict):
        fields = {}
    has_demo_file = bool(fields.get("demo_file_path") and os.path.isfile(fields["demo_file_path"]))
    # Do not expose server path to client
    out_fields = {k: v for k, v in fields.items() if k != "demo_file_path"}
    rejection_subject, rejection_body = _get_demo_rejection_subject_and_body(item)
    return DemoSubmissionOut(
        id=item.id,
        artist_name=item.artist_name,
        email=item.email,
        consent_to_emails=item.consent_to_emails,
        consent_at=item.consent_at,
        contact_name=item.contact_name,
        phone=item.phone,
        genre=item.genre,
        city=item.city,
        message=item.message,
        links=[str(link).strip() for link in links if str(link).strip()],
        fields=out_fields,
        has_demo_file=has_demo_file,
        source=item.source,
        source_site_url=item.source_site_url,
        status=item.status,
        admin_notes=item.admin_notes,
        approval_subject=item.approval_subject,
        approval_body=item.approval_body,
        rejection_subject=rejection_subject,
        rejection_body=rejection_body,
        approval_email_sent_at=item.approval_email_sent_at,
        rejection_email_sent_at=item.rejection_email_sent_at,
        artist_id=item.artist_id,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _validate_demo_ingest_token(request: Request) -> None:
    expected = (settings.demo_submission_token or "").strip()
    if not expected:
        return
    provided = (
        request.headers.get("x-demo-token")
        or request.headers.get("x-labelops-demo-token")
        or ""
    ).strip()
    if provided != expected:
        append_system_log(
            "warning",
            "auth",
            "Demo token rejected",
            details=_request_identity_details(request),
        )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid demo submission token")


def _request_source(request: Request) -> str:
    forwarded_for = (request.headers.get("x-forwarded-for") or "").split(",")[0].strip()
    return forwarded_for or (request.client.host if request.client else "unknown")


def _mask_email(email: str | None) -> str:
    value = (email or "").strip().lower()
    if not value or "@" not in value:
        return "unknown"
    local, domain = value.split("@", 1)
    if len(local) <= 2:
        local_masked = local[:1] + "*"
    else:
        local_masked = local[:2] + "*" * (len(local) - 2)
    return f"{local_masked}@{domain}"


def _request_identity_details(request: Request, email: str | None = None) -> str:
    origin = (request.headers.get("origin") or "").strip() or "-"
    user_agent = (request.headers.get("user-agent") or "").strip()[:180] or "-"
    masked_email = _mask_email(email)
    return f"ip={_request_source(request)} origin={origin} email={masked_email} ua={user_agent}"


def _log_auth_attempt(
    request: Request,
    *,
    event: str,
    email: str | None = None,
    level: str = "info",
) -> None:
    append_system_log(level, "auth", event, details=_request_identity_details(request, email))


def _safe_json_dict(raw: str | None) -> dict:
    try:
        data = json.loads(raw or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        data = {}
    return data if isinstance(data, dict) else {}


def _safe_json_list(raw: str | None) -> list:
    try:
        data = json.loads(raw or "[]") or []
    except (json.JSONDecodeError, TypeError):
        data = []
    return data if isinstance(data, list) else []


def _pending_release_form_link(raw_token: str) -> str:
    portal_url = (_artist_portal_url()).rstrip("/")
    return f"{portal_url}/#/pending-release?token={raw_token}"


def _serialize_pending_release(
    pr: PendingRelease,
    *,
    last_reminder_sent_at: datetime | None = None,
) -> PendingReleaseOut:
    artist_data = _safe_json_dict(pr.artist_data_json)
    release_data = _safe_json_dict(pr.release_data_json)
    return PendingReleaseOut(
        id=pr.id,
        campaign_request_id=pr.campaign_request_id,
        demo_submission_id=getattr(pr, "demo_submission_id", None),
        artist_id=pr.artist_id,
        artist_name=pr.artist_name,
        artist_email=pr.artist_email,
        artist_data=artist_data,
        release_title=pr.release_title,
        release_data=release_data,
        status=pr.status,
        created_at=pr.created_at,
        updated_at=pr.updated_at,
        last_reminder_sent_at=last_reminder_sent_at,
    )


def _pending_release_image_options(release_data: dict) -> list[PendingReleaseImageOptionOut]:
    raw_items = release_data.get("image_options")
    if not isinstance(raw_items, list):
        return []
    out: list[PendingReleaseImageOptionOut] = []
    for item in raw_items:
        if not isinstance(item, dict):
            continue
        image_id = (item.get("id") or "").strip() if isinstance(item.get("id"), str) else ""
        url = (item.get("url") or "").strip() if isinstance(item.get("url"), str) else ""
        if not image_id or not url:
            continue
        created_at = None
        raw_created_at = item.get("created_at")
        if isinstance(raw_created_at, str):
            try:
                created_at = (
                    datetime.fromisoformat(raw_created_at.replace("Z", "+00:00"))
                    if raw_created_at
                    else None
                )
            except ValueError:
                created_at = None
        out.append(
            PendingReleaseImageOptionOut(
                id=image_id,
                url=url,
                filename=(item.get("filename") or "").strip() or None,
                created_at=created_at,
            )
        )
    return out


def _pending_release_selected_image_id(release_data: dict) -> str | None:
    raw = release_data.get("selected_image_id")
    if isinstance(raw, str) and raw.strip():
        return raw.strip()
    return None


def _pending_release_notifications_muted(release_data: dict) -> bool:
    return release_data.get("notifications_muted") is True


def _pending_release_comment_out(comment: PendingReleaseComment) -> PendingReleaseCommentOut:
    return PendingReleaseCommentOut.model_validate(comment)


def _serialize_pending_release_detail(
    pr: PendingRelease,
    *,
    last_reminder_sent_at: datetime | None = None,
) -> PendingReleaseDetailOut:
    base = _serialize_pending_release(pr, last_reminder_sent_at=last_reminder_sent_at)
    release_data = _safe_json_dict(pr.release_data_json)
    comments = [_pending_release_comment_out(item) for item in (pr.comments or [])]
    return PendingReleaseDetailOut(
        **base.model_dump(),
        image_options=_pending_release_image_options(release_data),
        selected_image_id=_pending_release_selected_image_id(release_data),
        notifications_muted=_pending_release_notifications_muted(release_data),
        comments=comments,
    )


def _save_pending_release_data(pr: PendingRelease, release_data: dict) -> None:
    pr.release_data_json = json.dumps(release_data if isinstance(release_data, dict) else {})


def _notify_pending_release_artist(
    pr: PendingRelease,
    *,
    subject: str,
    body_lines: list[str],
) -> None:
    release_data = _safe_json_dict(pr.release_data_json)
    if _pending_release_notifications_muted(release_data):
        return
    to_email = (pr.artist_email or "").strip().lower()
    if not to_email or not is_email_configured():
        return
    portal_url = (_artist_portal_url()).rstrip("/")
    body = "\n".join(
        [
            *body_lines,
            "",
            f"Artist portal: {portal_url}",
            "",
            "You can mute future pending release update emails from the release page in the artist portal.",
            "",
            "Best regards,",
            "Zalmanim",
        ]
    )
    success, message = send_email_service(
        to_email=to_email,
        subject=subject,
        body_text=body,
    )
    if not success:
        logging.getLogger(__name__).warning(
            "Failed to send pending release update email to %s: %s",
            to_email,
            message,
        )


def _resolve_pending_release_from_token(db: Session, row: PendingReleaseToken) -> PendingRelease | None:
    if getattr(row, "pending_release_id", None):
        pr = db.query(PendingRelease).filter(PendingRelease.id == row.pending_release_id).first()
        if pr:
            return pr
    if row.campaign_request_id is not None:
        return db.query(PendingRelease).filter(PendingRelease.campaign_request_id == row.campaign_request_id).first()
    return None


def _get_valid_pending_release_token(db: Session, token: str) -> PendingReleaseToken:
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    row = (
        db.query(PendingReleaseToken)
        .filter(
            PendingReleaseToken.token_hash == token_hash,
            PendingReleaseToken.used_at.is_(None),
            PendingReleaseToken.expires_at > datetime.now(timezone.utc),
        )
        .first()
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or expired token")
    return row


def _get_valid_artist_registration_token(db: Session, token: str) -> ArtistRegistrationToken:
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    row = (
        db.query(ArtistRegistrationToken)
        .filter(
            ArtistRegistrationToken.token_hash == token_hash,
            ArtistRegistrationToken.used_at.is_(None),
            ArtistRegistrationToken.expires_at > datetime.now(timezone.utc),
        )
        .first()
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or expired token")
    return row

@router.on_event("startup")
def init_db() -> None:
    Base.metadata.create_all(bind=engine)

    try:
        with engine.connect() as conn:
            conn.execute(text("ALTER TABLE artists ADD COLUMN IF NOT EXISTS extra_json TEXT"))
            conn.execute(text("ALTER TABLE artists ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true NOT NULL"))
            conn.execute(text("ALTER TABLE artists ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255)"))
            conn.execute(text("ALTER TABLE artists ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE artists ADD COLUMN IF NOT EXISTS last_profile_updated_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE social_connections ADD COLUMN IF NOT EXISTS pkce_code_verifier VARCHAR(255)"))
            conn.execute(text("ALTER TABLE social_connections ADD COLUMN IF NOT EXISTS one_time_token VARCHAR(255)"))
            conn.execute(text("ALTER TABLE social_connections ADD COLUMN IF NOT EXISTS one_time_expires_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS full_name VARCHAR(255)"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true NOT NULL"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL"))
            conn.execute(text("ALTER TABLE demo_submissions ADD COLUMN IF NOT EXISTS consent_to_emails BOOLEAN DEFAULT false NOT NULL"))
            conn.execute(text("ALTER TABLE demo_submissions ADD COLUMN IF NOT EXISTS consent_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE demo_submissions ADD COLUMN IF NOT EXISTS rejection_email_sent_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_rejection_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_rejection_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_approval_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_approval_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_receipt_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_receipt_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS portal_invite_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS portal_invite_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS groover_invite_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS groover_invite_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS email_footer TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS update_profile_invite_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS update_profile_invite_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS password_reset_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS password_reset_body TEXT"))
            conn.execute(text(
                "ALTER TABLE pending_releases ADD COLUMN IF NOT EXISTS demo_submission_id INTEGER "
                "REFERENCES demo_submissions(id) ON DELETE SET NULL"
            ))
            conn.execute(text(
                "ALTER TABLE pending_release_tokens ALTER COLUMN campaign_request_id DROP NOT NULL"
            ))
            conn.execute(text(
                "ALTER TABLE pending_release_tokens ALTER COLUMN artist_id DROP NOT NULL"
            ))
            conn.execute(text(
                "ALTER TABLE pending_release_tokens ADD COLUMN IF NOT EXISTS pending_release_id INTEGER "
                "REFERENCES pending_releases(id) ON DELETE CASCADE"
            ))
            conn.execute(text(
                "ALTER TABLE label_inbox_messages ADD COLUMN IF NOT EXISTS admin_read_at TIMESTAMP WITH TIME ZONE"
            ))
            conn.execute(text(
                "UPDATE mail_settings SET emails_per_hour = 10 WHERE id = 1 AND (emails_per_hour IS NULL OR emails_per_hour = 5)"
            ))
            conn.commit()
    except Exception as e:
        logging.getLogger(__name__).warning("DB migration (auth/users): %s", e)

    with Session(engine) as db:
        admin = db.query(User).filter(User.email == "admin").first()
        legacy_admin = db.query(User).filter(User.email == "admin@label.local").first()
        simon_admin = (
            db.query(User)
            .filter(func.lower(User.email) == "simon@zalmanim.com")
            .first()
        )
        seed_artist_pw = os.environ.get("SEED_ARTIST_PASSWORD", "").strip()
        seed_admin_pw = os.environ.get("SEED_ADMIN_PASSWORD", "").strip()
        seed_simon_pw = os.environ.get("SEED_SIMON_PASSWORD", "").strip()

        artist = db.query(Artist).filter(Artist.email == "artist@label.local").first()
        if not artist:
            artist = Artist(
                name="Demo Artist",
                email="artist@label.local",
                notes="Seed artist",
                is_active=True,
                password_hash=hash_password(seed_artist_pw) if seed_artist_pw else None,
            )
            db.add(artist)
            db.flush()
            if not seed_artist_pw:
                logging.getLogger(__name__).warning("Seed artist created without password; set SEED_ARTIST_PASSWORD in .env or set password in UI")
        elif not artist.password_hash and seed_artist_pw:
            artist.password_hash = hash_password(seed_artist_pw)
        if not admin:
            if legacy_admin:
                legacy_admin.email = "admin"
                legacy_admin.full_name = legacy_admin.full_name or "System Admin"
                if seed_admin_pw:
                    legacy_admin.password_hash = hash_password(seed_admin_pw)
                legacy_admin.role = "admin"
                legacy_admin.artist_id = None
                legacy_admin.is_active = True
            else:
                db.add(
                    User(
                        email="admin",
                        full_name="System Admin",
                        password_hash=hash_password(seed_admin_pw) if seed_admin_pw else None,
                        role="admin",
                        artist_id=None,
                        is_active=True,
                    )
                )
                if not seed_admin_pw:
                    logging.getLogger(__name__).warning("Seed admin created without password; set SEED_ADMIN_PASSWORD in .env or set password in UI")
        else:
            admin.full_name = admin.full_name or "System Admin"
            if seed_admin_pw:
                admin.password_hash = hash_password(seed_admin_pw)
            admin.role = "admin"
            admin.artist_id = None
            admin.is_active = True
        if not simon_admin:
            db.add(
                User(
                    email="simon@zalmanim.com",
                    full_name="Simon",
                    password_hash=hash_password(seed_simon_pw) if seed_simon_pw else None,
                    role="admin",
                    artist_id=None,
                    is_active=True,
                )
            )
            if not seed_simon_pw:
                logging.getLogger(__name__).warning("Seed simon@zalmanim.com created without password; set SEED_SIMON_PASSWORD in .env or set password in UI")
        else:
            simon_admin.email = "simon@zalmanim.com"
            simon_admin.full_name = "Simon"
            if seed_simon_pw:
                simon_admin.password_hash = hash_password(seed_simon_pw)
            simon_admin.role = "admin"
            simon_admin.artist_id = None
            simon_admin.is_active = True
        artist_user = db.query(User).filter(User.email == "artist@label.local").first()
        if not artist_user:
            db.add(
                User(
                    email="artist@label.local",
                    full_name="Demo Artist",
                    password_hash=hash_password(seed_artist_pw) if seed_artist_pw else None,
                    role="artist",
                    artist_id=artist.id,
                    is_active=True,
                )
            )
            if not seed_artist_pw:
                logging.getLogger(__name__).warning("Seed artist user created without password; set SEED_ARTIST_PASSWORD in .env or set password in UI")
        db.commit()


@router.post("/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)) -> TokenResponse:
    """Admin/manager login (users table). For artist portal use POST /public/artist-login."""
    user = (
        db.query(User)
        .options(joinedload(User.artist), joinedload(User.identities))
        .filter(func.lower(User.email) == payload.email.lower())
        .first()
    )
    if not user or not user.is_active or not verify_password(payload.password, user.password_hash):
        _log_auth_attempt(request, event="Admin login failed", email=payload.email, level="warning")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    _touch_user_login(db, user)
    _log_auth_attempt(request, event="Admin login succeeded", email=user.email)
    return _user_token_response(user)


@router.post("/public/artist-login", response_model=TokenResponse)
def artist_login(payload: ArtistLoginRequest, request: Request, db: Session = Depends(get_db)) -> TokenResponse:
    """
    Artist portal login (artists.zalmanim.com). Uses artists table email + password_hash only.
    No users table row is required. Admin must set the artist's password first (admin UI or API).
    """
    artist = (
        db.query(Artist)
        .filter(func.lower(Artist.email) == payload.email.lower().strip())
        .first()
    )
    if not artist:
        _log_auth_attempt(request, event="Artist login failed", email=payload.email, level="warning")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")
    if not artist.is_active:
        _log_auth_attempt(request, event="Artist login blocked: inactive", email=payload.email, level="warning")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Account is inactive")
    if not artist.password_hash:
        _log_auth_attempt(request, event="Artist login blocked: password not set", email=payload.email, level="warning")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Password not set. Contact the label to get portal access.",
        )
    if not verify_password(payload.password, artist.password_hash):
        _log_auth_attempt(request, event="Artist login failed", email=payload.email, level="warning")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")
    _touch_artist_login(db, artist)
    _log_auth_attempt(request, event="Artist login succeeded", email=artist.email)
    return _artist_token_response(artist)


def _password_reset_token_hash(token: str) -> str:
    salt = (settings.jwt_secret or "reset").encode()
    return hashlib.sha256(salt + token.encode()).hexdigest()


_PASSWORD_RESET_EXPIRY_MINUTES = 60


@router.post("/auth/forgot-password")
def forgot_password(
    payload: ForgotPasswordRequest,
    request: Request,
    db: Session = Depends(get_db),
) -> dict:
    """Send password reset email for admin/manager users and artist portal accounts."""
    email = (payload.email or "").strip().lower()
    if not email:
        _log_auth_attempt(request, event="Password reset requested with empty email", level="warning")
        return {"message": "If an account exists with this email, you will receive a reset link shortly."}
    user = (
        db.query(User)
        .filter(func.lower(User.email) == email, User.is_active == True, User.password_hash.isnot(None))
        .first()
    )
    if not user:
        artist = (
            db.query(Artist)
            .filter(func.lower(Artist.email) == email, Artist.is_active == True, Artist.password_hash.isnot(None))
            .first()
        )
        if artist:
            user = _ensure_artist_reset_user(db, artist)
    if not user:
        _log_auth_attempt(request, event="Password reset requested for unknown account", email=email, level="warning")
        return {"message": "If an account exists with this email, you will receive a reset link shortly."}
    raw_token = secrets.token_urlsafe(32)
    token_hash = _password_reset_token_hash(raw_token)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=_PASSWORD_RESET_EXPIRY_MINUTES)
    db.add(PasswordResetToken(user_id=user.id, token_hash=token_hash, expires_at=expires_at))
    db.commit()
    # Use configured client URL; never use request.base_url (API) so the link opens the login app.
    base_url = (settings.password_reset_base_url or "").strip() or "https://lm.zalmanim.com"
    reset_link = f"{base_url.rstrip('/')}?reset_token={raw_token}"
    subject, body_text = _get_password_reset_subject_and_body(reset_link, _PASSWORD_RESET_EXPIRY_MINUTES)
    body_html = (
        "<p>"
        + html.escape(body_text).replace("\n\n", "</p><p>").replace("\n", "<br>")
        + "</p>"
    )
    body_html = body_html.replace(
        html.escape(reset_link),
        f'<a href="{html.escape(reset_link)}">{html.escape(reset_link)}</a>',
    )
    ok, _ = send_email_service(to_email=user.email, subject=subject, body_text=body_text, body_html=body_html)
    if not ok:
        logging.getLogger(__name__).warning("Failed to send password reset email to %s", user.email)
        _log_auth_attempt(request, event="Password reset email send failed", email=user.email, level="warning")
    else:
        _log_auth_attempt(request, event="Password reset email sent", email=user.email)
    return {"message": "If an account exists with this email, you will receive a reset link shortly."}


@router.post("/auth/reset-password")
def reset_password(payload: ResetPasswordRequest, db: Session = Depends(get_db)) -> dict:
    """Set new password using a valid reset token. Invalidates the token."""
    token = (payload.token or "").strip()
    new_password = payload.new_password or ""
    if not token or not new_password:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Token and new password are required")
    if len(new_password) < 6:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 6 characters")
    token_hash = _password_reset_token_hash(token)
    now = datetime.now(timezone.utc)
    row = (
        db.query(PasswordResetToken)
        .filter(PasswordResetToken.token_hash == token_hash, PasswordResetToken.expires_at > now)
        .first()
    )
    if not row:
        append_system_log("warning", "auth", "Password reset rejected", details="reason=invalid_or_expired_token")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired reset link. Request a new one.")
    user = db.query(User).filter(User.id == row.user_id).first()
    if not user or not user.is_active:
        append_system_log("warning", "auth", "Password reset rejected", details="reason=inactive_or_missing_user")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired reset link. Request a new one.")
    user.password_hash = hash_password(new_password)
    if user.role == "artist" and user.artist_id is not None:
        artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
        if artist and artist.is_active:
            artist.password_hash = user.password_hash
    db.delete(row)
    db.query(PasswordResetToken).filter(PasswordResetToken.user_id == user.id).delete()
    db.commit()
    append_system_log("info", "auth", "Password reset succeeded", details=f"email={_mask_email(user.email)}")
    return {"message": "Password has been reset. You can sign in with your new password."}


@router.post("/public/demo-submissions", response_model=DemoSubmissionOut)
def create_demo_submission(
    payload: DemoSubmissionCreate,
    request: Request,
    db: Session = Depends(get_db),
) -> DemoSubmissionOut:
    _validate_demo_ingest_token(request)
    source = (payload.source or "wordpress_demo_form").strip() or "wordpress_demo_form"
    if source == "artists_portal_landing" and not payload.consent_to_emails:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email consent is required before sending a demo.",
        )
    normalized_links = [str(link).strip() for link in payload.links if str(link).strip()]
    default_approval_subj, default_approval_body = _get_demo_approval_subject_and_body(payload.artist_name)
    item = DemoSubmission(
        artist_name=payload.artist_name.strip(),
        email=str(payload.email).strip().lower(),
        consent_to_emails=payload.consent_to_emails,
        consent_at=datetime.now(timezone.utc) if payload.consent_to_emails else None,
        contact_name=(payload.contact_name or "").strip() or None,
        phone=(payload.phone or "").strip() or None,
        genre=(payload.genre or "").strip() or None,
        city=(payload.city or "").strip() or None,
        message=(payload.message or "").strip() or None,
        links_json=json.dumps(normalized_links),
        fields_json=json.dumps(payload.fields or {}),
        source=source,
        source_site_url=(payload.source_site_url or "").strip() or None,
        status="demo",
        approval_subject=default_approval_subj,
        approval_body=default_approval_body,
    )
    db.add(item)
    db.flush()
    _upsert_demo_mailing_subscriber(db, item)
    db.commit()
    db.refresh(item)
    append_system_log(
        "info",
        "auth",
        "Public demo submission created",
        details=_request_identity_details(request, item.email),
    )
    if is_email_configured():
        subject, body_text = _get_demo_receipt_subject_and_body(item)
        body_html = _build_demo_receipt_html(item)
        if (get_effective_mail_config_for_api().get("demo_receipt_body") or "").strip():
            body_html = "<p>" + html.escape(body_text).replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
        ok, message = send_email_service(
            to_email=item.email,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )
        if not ok:
            logging.getLogger(__name__).warning("Failed to send demo receipt email to %s: %s", item.email, message)
    return _serialize_demo_submission(item)


ALLOWED_DEMO_FILE_EXT = (".mp3",)


def _form_bool(value: str | None) -> bool:
    return (value or "").strip().lower() in ("true", "1", "yes", "on")


@router.post("/public/demo-submissions/with-file", response_model=DemoSubmissionOut)
def create_demo_submission_with_file(
    request: Request,
    artist_name: str = Form(...),
    email: str = Form(...),
    consent_to_emails: str = Form("false"),
    contact_name: str | None = Form(None),
    phone: str | None = Form(None),
    genre: str | None = Form(None),
    city: str | None = Form(None),
    message: str | None = Form(None),
    links_json: str = Form("[]"),
    source: str = Form("artists_portal_landing"),
    source_site_url: str | None = Form(None),
    file: UploadFile | None = File(None),
    db: Session = Depends(get_db),
) -> DemoSubmissionOut:
    """Public demo submission with optional MP3 file and/or SoundCloud (or other) links. At least one of file or a link is required. Only MP3 files are accepted."""
    _validate_demo_ingest_token(request)
    if file and file.filename:
        append_system_log(
            "warning",
            "auth",
            "Public demo file upload blocked",
            details=_request_identity_details(request, email),
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Public demo file uploads are disabled. Please sign in as a registered artist to upload demo files.",
        )
    consent = _form_bool(consent_to_emails)
    source = (source or "wordpress_demo_form").strip() or "wordpress_demo_form"
    if source == "artists_portal_landing" and not consent:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email consent is required before sending a demo.",
        )
    try:
        links_list = json.loads(links_json or "[]")
        normalized_links = [str(link).strip() for link in links_list if str(link).strip()]
    except (json.JSONDecodeError, TypeError):
        normalized_links = []
    if not normalized_links:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Please provide a SoundCloud (or other) track link. Public demo file uploads are disabled.",
        )
    fields: dict = {}
    fields["consent_copy"] = "I agree to join the Zalmanim mailing list and receive marketing and operational emails related to my demo submission."
    default_approval_subj, default_approval_body = _get_demo_approval_subject_and_body(artist_name.strip())
    item = DemoSubmission(
        artist_name=artist_name.strip(),
        email=email.strip().lower(),
        consent_to_emails=consent,
        consent_at=datetime.now(timezone.utc) if consent else None,
        contact_name=(contact_name or "").strip() or None,
        phone=(phone or "").strip() or None,
        genre=(genre or "").strip() or None,
        city=(city or "").strip() or None,
        message=(message or "").strip() or None,
        links_json=json.dumps(normalized_links),
        fields_json=json.dumps(fields),
        source=source,
        source_site_url=(source_site_url or "").strip() or None,
        status="demo",
        approval_subject=default_approval_subj,
        approval_body=default_approval_body,
    )
    db.add(item)
    db.flush()
    _upsert_demo_mailing_subscriber(db, item)
    db.commit()
    db.refresh(item)
    append_system_log(
        "info",
        "auth",
        "Public demo submission with file created",
        details=_request_identity_details(request, item.email),
    )
    if is_email_configured():
        subject, body_text = _get_demo_receipt_subject_and_body(item)
        body_html = _build_demo_receipt_html(item)
        if (get_effective_mail_config_for_api().get("demo_receipt_body") or "").strip():
            body_html = "<p>" + html.escape(body_text).replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
        ok, message_out = send_email_service(
            to_email=item.email,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )
        if not ok:
            logging.getLogger(__name__).warning(
                "Failed to send demo receipt email to %s: %s", item.email, message_out
            )
    return _serialize_demo_submission(item)


# Label for each extra link key (for public linktree page)
_LINKTREE_LABELS = {
    "website": "Website",
    "soundcloud": "SoundCloud",
    "facebook": "Facebook",
    "instagram": "Instagram",
    "twitter_1": "Twitter / X",
    "twitter_2": "Twitter / X 2",
    "youtube": "YouTube",
    "tiktok": "TikTok",
    "spotify": "Spotify",
    "apple_music": "Apple Music",
    "linktree": "Linktree",
    "other_1": "Other",
    "other_2": "Other",
    "other_3": "Other",
}


def _linktree_image_url(request: Request, artist_id: int, kind: str) -> str:
    """Build public URL for artist profile image or logo (no auth)."""
    base = str(request.base_url).rstrip("/")
    return f"{base}/public/artist/{artist_id}/{kind}"


@router.get("/public/linktree/{artist_id}", response_model=LinktreeOut)
def public_linktree(
    artist_id: int,
    request: Request,
    db: Session = Depends(get_db),
) -> LinktreeOut:
    """Public linktree-style page data for an artist (no auth). Returns name, links, and optional profile/logo image URLs."""
    artist = db.query(Artist).filter(Artist.id == artist_id, Artist.is_active == True).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    extra = {}
    if getattr(artist, "extra_json", None):
        try:
            extra = json.loads(artist.extra_json) or {}
        except (json.JSONDecodeError, TypeError):
            pass
    name = (artist.name or "").strip() or (extra.get("full_name") or extra.get("artist_brand") or "").strip() or "Artist"
    links = []
    for key, label in _LINKTREE_LABELS.items():
        val = (extra.get(key) or "").strip()
        if val and (val.startswith("http://") or val.startswith("https://")):
            links.append(LinktreeLink(label=label, url=val))
        elif val:
            links.append(LinktreeLink(label=label, url=val if "://" in val else f"https://{val}"))
    profile_image_url = None
    logo_url = None
    pid = extra.get("profile_image_media_id")
    lid = extra.get("logo_media_id")
    media_ids = [x for x in (pid, lid) if isinstance(x, int) and x]
    if media_ids:
        media_list = (
            db.query(ArtistMedia)
            .filter(ArtistMedia.artist_id == artist.id, ArtistMedia.id.in_(media_ids))
            .all()
        )
        for media in media_list:
            if not os.path.isfile(media.stored_path):
                continue
            if media.id == pid:
                profile_image_url = _linktree_image_url(request, artist_id, "profile-image")
            if media.id == lid:
                logo_url = _linktree_image_url(request, artist_id, "logo")
    releases_q = (
        db.query(Release)
        .options(joinedload(Release.artists))
        .filter(or_(Release.artist_id == artist.id, Release.artists.any(Artist.id == artist.id)))
        .order_by(desc(Release.created_at))
        .limit(50)
    )
    releases = [
        LinktreeRelease(title=(r.title or "").strip() or "Untitled", url=None)
        for r in releases_q.all()
    ]
    return LinktreeOut(
        artist_id=artist.id,
        name=name,
        links=links,
        profile_image_url=profile_image_url,
        logo_url=logo_url,
        releases=releases,
    )


@router.get("/public/artist/{artist_id}/profile-image", response_class=FileResponse)
def public_artist_profile_image(
    artist_id: int,
    db: Session = Depends(get_db),
) -> FileResponse:
    """Serve the artist's Linktree profile image (no auth)."""
    artist = db.query(Artist).filter(Artist.id == artist_id, Artist.is_active == True).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    extra = {}
    if getattr(artist, "extra_json", None):
        try:
            extra = json.loads(artist.extra_json) or {}
        except (json.JSONDecodeError, TypeError):
            pass
    pid = extra.get("profile_image_media_id")
    if not isinstance(pid, int) or not pid:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No profile image")
    media = db.query(ArtistMedia).filter(ArtistMedia.id == pid, ArtistMedia.artist_id == artist.id).first()
    if not media or not os.path.isfile(media.stored_path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    return FileResponse(media.stored_path, filename=media.filename, media_type=media.content_type)


@router.get("/public/artist/{artist_id}/logo", response_class=FileResponse)
def public_artist_logo(
    artist_id: int,
    db: Session = Depends(get_db),
) -> FileResponse:
    """Serve the artist's Linktree logo (no auth)."""
    artist = db.query(Artist).filter(Artist.id == artist_id, Artist.is_active == True).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    extra = {}
    if getattr(artist, "extra_json", None):
        try:
            extra = json.loads(artist.extra_json) or {}
        except (json.JSONDecodeError, TypeError):
            pass
    lid = extra.get("logo_media_id")
    if not isinstance(lid, int) or not lid:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No logo")
    media = db.query(ArtistMedia).filter(ArtistMedia.id == lid, ArtistMedia.artist_id == artist.id).first()
    if not media or not os.path.isfile(media.stored_path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    return FileResponse(media.stored_path, filename=media.filename, media_type=media.content_type)


@router.get("/auth/me", response_model=UserOut)
def get_me(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> UserOut:
    current_user = (
        db.query(User)
        .options(joinedload(User.artist), joinedload(User.identities))
        .filter(User.id == user.user_id)
        .first()
    )
    if not current_user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return _serialize_user(current_user)


@router.get("/auth/{provider}/start")
def start_provider_login(provider: str, request: Request, redirect_uri: str) -> dict:
    state = _build_oauth_state(provider=provider, purpose="login", app_redirect=redirect_uri)
    return {"auth_url": _build_provider_auth_url(provider, request=request, state=state)}


@router.get("/admin/google-mail/start")
def start_google_mail_connect(
    request: Request,
    redirect_uri: str,
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    require_admin(user)
    state = _build_oauth_state(provider="google", purpose="connect_gmail", app_redirect=redirect_uri, user_id=user.user_id)
    return {"auth_url": _build_google_auth_url(request=request, state=state)}


@router.get("/auth/{provider}/callback", name="oauth_callback")
def oauth_callback(
    provider: str,
    request: Request,
    state: str,
    code: str | None = None,
    error: str | None = None,
    db: Session = Depends(get_db),
) -> RedirectResponse:
    state_payload = _decode_oauth_state(state)
    app_redirect = state_payload.get("app_redirect") or settings.oauth_success_redirect or "/"
    if error:
        return _redirect_with_params(app_redirect, social_error=error, provider=provider)
    if not code:
        return _redirect_with_params(app_redirect, social_error="missing_code", provider=provider)

    token_payload = _exchange_provider_code(provider, request=request, code=code)
    access_token = str(token_payload.get("access_token") or "")
    refresh_token = token_payload.get("refresh_token")
    scope_value = str(token_payload.get("scope") or "")
    scopes = [s for s in scope_value.replace(",", " ").split(" ") if s]
    provider_subject, email, display_name = _fetch_provider_profile(provider, access_token)

    if state_payload.get("purpose") == "connect_gmail":
        _upsert_google_mail_connection(
            db,
            email=email,
            access_token=access_token,
            refresh_token=refresh_token,
            scopes=scopes,
        )
        return _redirect_with_params(app_redirect, gmail_connected="1", gmail_email=email)

    user = _find_or_create_oauth_user(
        db,
        provider=provider,
        provider_subject=provider_subject,
        email=email,
        display_name=display_name,
    )
    _touch_user_login(db, user)
    if provider == "google" and user.role == "admin":
        _upsert_google_mail_connection(
            db,
            email=email,
            access_token=access_token,
            refresh_token=refresh_token,
            scopes=scopes,
        )
    app_token = create_access_token(str(user.id))
    return _redirect_with_params(
        app_redirect,
        token=app_token,
        role=user.role,
        email=user.email,
        full_name=user.full_name or "",
        provider=provider,
    )


@router.get("/admin/users", response_model=list[UserOut])
def list_users(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[UserOut]:
    require_admin(user)
    users = db.query(User).options(joinedload(User.artist), joinedload(User.identities)).order_by(User.created_at.desc(), User.id.desc()).all()
    return [_serialize_user(item) for item in users]


@router.get("/admin/dashboard/login-stats", response_model=LoginStatsOut)
def get_login_stats(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> LoginStatsOut:
    require_admin(user)
    threshold = datetime.now(timezone.utc) - timedelta(days=30)

    users_logged_in_last_30_days = (
        db.query(User)
        .filter(User.last_login_at.isnot(None), User.last_login_at >= threshold)
        .count()
    )

    artist_keys: set[str] = set()
    portal_artists = db.query(Artist).filter(
        Artist.last_login_at.isnot(None),
        Artist.last_login_at >= threshold,
    )
    for artist in portal_artists:
        artist_keys.add(f"artist:{artist.id}")

    artist_users = db.query(User).filter(
        User.role == "artist",
        User.last_login_at.isnot(None),
        User.last_login_at >= threshold,
    )
    for artist_user in artist_users:
        if artist_user.artist_id is not None:
            artist_keys.add(f"artist:{artist_user.artist_id}")
        else:
            artist_keys.add(f"user-email:{artist_user.email.lower()}")

    recent_logins: list[LoginActivityOut] = []
    for recent_user in (
        db.query(User)
        .filter(User.last_login_at.isnot(None))
        .order_by(User.last_login_at.desc())
        .limit(10)
        .all()
    ):
        if recent_user.last_login_at is None:
            continue
        recent_logins.append(
            LoginActivityOut(
                source="user",
                name=(recent_user.full_name or recent_user.email).strip(),
                email=recent_user.email,
                role=recent_user.role,
                is_active=recent_user.is_active,
                last_login_at=recent_user.last_login_at,
            )
        )

    for recent_artist in (
        db.query(Artist)
        .filter(Artist.last_login_at.isnot(None))
        .order_by(Artist.last_login_at.desc())
        .limit(10)
        .all()
    ):
        if recent_artist.last_login_at is None:
            continue
        recent_logins.append(
            LoginActivityOut(
                source="artist_portal",
                name=(recent_artist.name or recent_artist.email).strip(),
                email=recent_artist.email,
                role="artist",
                is_active=recent_artist.is_active,
                last_login_at=recent_artist.last_login_at,
            )
        )

    recent_logins.sort(key=lambda item: item.last_login_at, reverse=True)

    return LoginStatsOut(
        users_logged_in_last_30_days=users_logged_in_last_30_days,
        artists_logged_in_last_30_days=len(artist_keys),
        recent_logins=recent_logins[:10],
    )


@router.get("/admin/dashboard/stats", response_model=AdminDashboardStatsOut)
def get_admin_dashboard_stats(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> AdminDashboardStatsOut:
    """Return counts for the admin dashboard header: active artists and total releases."""
    require_admin(user)
    artists_count = db.query(Artist).filter(Artist.is_active.is_(True)).count()
    releases_count = db.query(Release).count()
    return AdminDashboardStatsOut(artists_count=artists_count, releases_count=releases_count)


@router.post("/admin/users", response_model=UserOut)
def create_user(
    payload: UserCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> UserOut:
    require_admin(user)
    email = payload.email.lower()
    if db.query(User).filter(func.lower(User.email) == email).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="User email already exists")
    role = _validate_user_role(payload.role)
    if payload.artist_id is not None and not db.query(Artist).filter(Artist.id == payload.artist_id).first():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    user_row = User(
        email=email,
        full_name=(payload.full_name or "").strip() or None,
        password_hash=hash_password(payload.password) if payload.password else None,
        role=role,
        artist_id=payload.artist_id,
        is_active=payload.is_active,
    )
    db.add(user_row)
    db.commit()
    db.refresh(user_row)
    return _serialize_user(user_row)


@router.patch("/admin/users/{target_user_id}", response_model=UserOut)
def update_user(
    target_user_id: int,
    payload: UserUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> UserOut:
    require_admin(user)
    target = db.query(User).options(joinedload(User.artist), joinedload(User.identities)).filter(User.id == target_user_id).first()
    if not target:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    if payload.email is not None:
        new_email = payload.email.lower()
        existing = db.query(User).filter(func.lower(User.email) == new_email, User.id != target_user_id).first()
        if existing:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="User email already exists")
        target.email = new_email
    if payload.full_name is not None:
        target.full_name = payload.full_name.strip() or None
    if payload.password is not None:
        target.password_hash = hash_password(payload.password) if payload.password else None
    if payload.role is not None:
        target.role = _validate_user_role(payload.role)
    if payload.artist_id is not None:
        artist = db.query(Artist).filter(Artist.id == payload.artist_id).first()
        if not artist:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
        target.artist_id = artist.id
    if payload.is_active is not None:
        if target.id == user.user_id and not payload.is_active:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You cannot deactivate your own user")
        target.is_active = payload.is_active
    db.commit()
    db.refresh(target)
    return _serialize_user(target)


def _last_email_sent_map(db: Session, artist_ids: list[int]) -> dict[int, datetime]:
    """Return map artist_id -> max(created_at) for activity types that send email."""
    if not artist_ids:
        return {}
    rows = (
        db.query(ArtistActivityLog.artist_id, func.max(ArtistActivityLog.created_at).label("last_at"))
        .filter(
            ArtistActivityLog.artist_id.in_(artist_ids),
            ArtistActivityLog.activity_type.in_(
                ("portal_invite_email", "update_profile_invite_email", "reminder_email")
            ),
        )
        .group_by(ArtistActivityLog.artist_id)
        .all()
    )
    return {aid: last_at for aid, last_at in rows}


def _artist_search_filter(q, search_term: str, db: Session):
    """Apply server-side search filter for artists (brand, name, email, artist_brands)."""
    pattern = f"%{search_term}%"
    dialect = db.get_bind().dialect.name
    if dialect == "postgresql":
        return q.filter(
            or_(
                Artist.email.ilike(pattern),
                Artist.name.ilike(pattern),
                text("coalesce(extra_json::jsonb->>'artist_brand','') ILIKE :pat").bindparams(pat=pattern),
                text("coalesce(extra_json::jsonb->>'full_name','') ILIKE :pat").bindparams(pat=pattern),
                text(
                    "EXISTS (SELECT 1 FROM jsonb_array_elements_text("
                    "coalesce(extra_json::jsonb->'artist_brands','[]'::jsonb)) AS t WHERE t ILIKE :pat)"
                ).bindparams(pat=pattern),
            )
        )
    # SQLite / other: search name and email only (no JSON operators in all dialects)
    return q.filter(or_(Artist.email.ilike(pattern), Artist.name.ilike(pattern)))


@router.get("/artists", response_model=list[ArtistOut])
def list_artists(
    include_inactive: bool = Query(False, description="Include inactive artists"),
    search: str | None = Query(None, description="Search by brand, name, email, or artist brands"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[ArtistOut]:
    require_admin(user)
    q = db.query(Artist).order_by(Artist.id)
    if not include_inactive:
        q = q.filter(Artist.is_active.is_(True))
    search_term = (search or "").strip()
    if search_term:
        q = _artist_search_filter(q, search_term, db)
    artists = q.offset(offset).limit(limit).all()
    artist_ids = [a.id for a in artists]
    last_email_map = _last_email_sent_map(db, artist_ids)
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
        out.append(
            ArtistOut.from_artist(
                a,
                last_release=last_release,
                last_email_sent_at=last_email_map.get(a.id),
            )
        )
    return out


@router.get("/admin/demo-submissions", response_model=list[DemoSubmissionOut])
def list_demo_submissions(
    status_filter: str | None = Query(None, alias="status"),
    limit: int = Query(100, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[DemoSubmissionOut]:
    require_admin(user)
    q = db.query(DemoSubmission).order_by(desc(DemoSubmission.created_at), desc(DemoSubmission.id))
    normalized_status = _normalize_demo_status(status_filter, allow_empty=True)
    if normalized_status:
        q = q.filter(DemoSubmission.status == normalized_status)
    items = q.offset(offset).limit(limit).all()
    return [_serialize_demo_submission(item) for item in items]


@router.get("/admin/demo-submissions/{submission_id}", response_model=DemoSubmissionOut)
def get_demo_submission(
    submission_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> DemoSubmissionOut:
    require_admin(user)
    item = db.query(DemoSubmission).filter(DemoSubmission.id == submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")
    return _serialize_demo_submission(item)


@router.patch("/admin/demo-submissions/{submission_id}", response_model=DemoSubmissionOut)
def update_demo_submission(
    submission_id: int,
    payload: DemoSubmissionUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> DemoSubmissionOut:
    require_admin(user)
    item = db.query(DemoSubmission).filter(DemoSubmission.id == submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")

    old_status = item.status
    if payload.artist_name is not None:
        item.artist_name = payload.artist_name.strip()
    if payload.email is not None:
        item.email = str(payload.email).strip().lower()
    if payload.consent_to_emails is not None:
        item.consent_to_emails = payload.consent_to_emails
        item.consent_at = datetime.now(timezone.utc) if payload.consent_to_emails else None
    if payload.contact_name is not None:
        item.contact_name = payload.contact_name.strip() or None
    if payload.phone is not None:
        item.phone = payload.phone.strip() or None
    if payload.genre is not None:
        item.genre = payload.genre.strip() or None
    if payload.city is not None:
        item.city = payload.city.strip() or None
    if payload.message is not None:
        item.message = payload.message.strip() or None
    if payload.links is not None:
        item.links_json = json.dumps([str(link).strip() for link in payload.links if str(link).strip()])
    if payload.fields is not None:
        item.fields_json = json.dumps(payload.fields or {})
    if payload.status is not None:
        item.status = _normalize_demo_status(payload.status) or "demo"
    if payload.admin_notes is not None:
        item.admin_notes = payload.admin_notes
    if payload.approval_subject is not None:
        item.approval_subject = payload.approval_subject.strip() or None
    if payload.approval_body is not None:
        item.approval_body = payload.approval_body
    if payload.artist_id is not None:
        item.artist_id = payload.artist_id

    # When status changes to rejected, send rejection email once (if not already sent).
    if item.status == "rejected" and old_status != "rejected" and item.rejection_email_sent_at is None:
        default_rejection_subject, default_rejection_body = _get_demo_rejection_subject_and_body(item)
        rejection_subject = default_rejection_subject
        rejection_body = default_rejection_body
        if payload.rejection_subject is not None:
            rejection_subject = payload.rejection_subject.strip() or default_rejection_subject
            rejection_subject = _apply_demo_rejection_placeholders(rejection_subject, item)
        if payload.rejection_body is not None:
            rejection_body = payload.rejection_body.strip() or default_rejection_body
            rejection_body = _apply_demo_rejection_placeholders(rejection_body, item)
        should_send_rejection_email = payload.send_rejection_email
        if should_send_rejection_email is None:
            should_send_rejection_email = True
        if should_send_rejection_email and is_email_configured():
            success, message = send_email_service(
                to_email=item.email,
                subject=rejection_subject,
                body_text=rejection_body,
            )
            if success:
                item.rejection_email_sent_at = datetime.now(timezone.utc)
            else:
                if "limit" in message.lower():
                    raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)
        # If email not configured, still allow marking as rejected; no email sent.

    if item.consent_to_emails:
        _upsert_demo_mailing_subscriber(db, item)
    db.commit()
    db.refresh(item)
    return _serialize_demo_submission(item)


@router.get("/admin/demo-submissions/{submission_id}/download", response_model=None)
def admin_download_demo_file(
    submission_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> FileResponse | Response:
    """Stream or download the attached MP3 for a demo submission (admin only)."""
    require_admin(user)
    item = db.query(DemoSubmission).filter(DemoSubmission.id == submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")
    try:
        fields = json.loads(item.fields_json or "{}")
        path = fields.get("demo_file_path")
    except (json.JSONDecodeError, TypeError):
        path = None
    if not path or not os.path.isfile(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No file attached")
    return FileResponse(path, filename=os.path.basename(path), media_type="audio/mpeg")


@router.delete("/admin/demo-submissions/{submission_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_demo_submission(
    submission_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> None:
    """Delete a demo submission. Optionally removes the attached file from disk."""
    require_admin(user)
    item = db.query(DemoSubmission).filter(DemoSubmission.id == submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")
    try:
        fields = json.loads(item.fields_json or "{}")
        path = fields.get("demo_file_path")
    except (json.JSONDecodeError, TypeError):
        path = None
    db.delete(item)
    db.commit()
    if path and os.path.isfile(path):
        try:
            os.remove(path)
        except OSError:
            pass


@router.post("/admin/demo-submissions/{submission_id}/approve", response_model=DemoSubmissionOut)
def approve_demo_submission(
    submission_id: int,
    payload: DemoSubmissionApproveRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> DemoSubmissionOut:
    require_admin(user)
    item = db.query(DemoSubmission).filter(DemoSubmission.id == submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")

    if payload.approval_subject is not None:
        item.approval_subject = payload.approval_subject.strip() or None
    if payload.approval_body is not None:
        item.approval_body = payload.approval_body
    if not item.approval_subject or not item.approval_body:
        default_subj, default_body = _get_demo_approval_subject_and_body(item.artist_name)
        if not item.approval_subject:
            item.approval_subject = default_subj
        if not item.approval_body:
            item.approval_body = default_body

    if payload.create_artist and item.artist_id is None:
        artist = db.query(Artist).filter(func.lower(Artist.email) == item.email.lower()).first()
        if artist is None:
            demo_extra = {
                "artist_brand": item.artist_name,
                "full_name": item.contact_name,
                "comments": item.message,
                "demo_submission_id": item.id,
                "demo_status": "approved",
                "demo_links": _safe_json_list(item.links_json),
                **_safe_json_dict(item.fields_json),
            }
            artist = Artist(
                name=item.artist_name,
                email=item.email,
                notes="Created from approved demo submission.",
                is_active=True,
                extra_json=json.dumps(demo_extra),
            )
            db.add(artist)
            db.flush()
        item.artist_id = artist.id

    # Create one-time token for artist to confirm details (form link in approval email).
    demo_confirm_form_link: str | None = None
    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    portal_url = (_artist_portal_url()).rstrip("/")
    # Use hash URL so the link works when the server only serves index.html at / (no SPA fallback).
    demo_confirm_form_link = f"{portal_url}/#/demo-confirm?token={raw_token}"
    expires_at = datetime.now(timezone.utc) + timedelta(days=30)
    demo_confirm_token_row = DemoConfirmationToken(
        demo_submission_id=item.id,
        token_hash=token_hash,
        expires_at=expires_at,
    )
    db.add(demo_confirm_token_row)
    db.flush()

    if payload.send_email:
        body_text = (item.approval_body or "").strip()
        if body_text:
            body_text += "\n\n"
        body_text += (
            "Please confirm your details and complete any missing fields here:\n"
            f"{demo_confirm_form_link}\n\n"
            "Once you submit the form, your track will move to PENDING RELEASE until we release it."
        )
        success, message = send_email_service(
            to_email=item.email,
            subject=item.approval_subject,
            body_text=body_text,
        )
        if not success:
            if "limit" in message.lower():
                raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)
        item.approval_email_sent_at = datetime.now(timezone.utc)
        if item.artist_id is not None:
            db.add(
                ArtistActivityLog(
                    artist_id=item.artist_id,
                    activity_type="demo_approval_email",
                    details=f"Demo submission #{item.id}",
                )
            )

    item.status = "approved"
    _create_pending_release_for_demo(db, item)
    db.commit()
    db.refresh(item)
    return _serialize_demo_submission(item)


@router.get("/artists/{artist_id}", response_model=ArtistOut)
def get_artist(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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


@router.patch("/admin/artists/{artist_id}/set-password")
def admin_set_artist_password(
    artist_id: int,
    payload: ArtistSetPasswordRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    """Set or reset an artist's portal password (artists table). Artist can then log in at artist portal."""
    require_admin(user)
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if not payload.password or len(payload.password) < 6:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 6 characters")
    artist.password_hash = hash_password(payload.password)
    db.commit()
    return {"ok": True, "message": "Password set. Artist can sign in at the artist portal."}


@router.post("/admin/artists/{artist_id}/send-portal-invite", response_model=ArtistPortalInviteResponse)
def admin_send_artist_portal_invite(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ArtistPortalInviteResponse:
    """Generate a temporary artist portal password and email portal login instructions."""
    require_admin(user)
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if not artist.is_active:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist is inactive")
    username = (artist.email or "").strip().lower()
    if not username:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist email is required")

    extra = _artist_extra_from_model(artist)
    display_name = (
        str(extra.get("full_name") or "").strip()
        or str(extra.get("artist_brand") or "").strip()
        or (artist.name or "").strip()
        or username
    )
    portal_url = _artist_portal_url()
    temporary_password = _generate_temporary_password()
    subject, body_text = _get_portal_invite_subject_and_body(
        display_name, portal_url, username, temporary_password
    )
    # Build HTML from plain body: escape and turn paragraphs into <p>, newlines into <br>
    body_html = "<p>" + html.escape(body_text).replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
    # Make portal URL clickable if it appears as plain text
    body_html = body_html.replace(
        html.escape(portal_url),
        f'<a href="{html.escape(portal_url)}">{html.escape(portal_url)}</a>',
    )

    artist.password_hash = hash_password(temporary_password)
    success, message = send_email_service(
        to_email=username,
        subject=subject,
        body_text=body_text,
        body_html=body_html,
    )
    if not success:
        db.rollback()
        if "limit" in message.lower():
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)

    db.add(
        ArtistActivityLog(
            artist_id=artist.id,
            activity_type="portal_invite_email",
            details=f"Portal invite sent to {username}",
        )
    )
    db.commit()
    return ArtistPortalInviteResponse(
        message="Artist portal invitation sent.",
        portal_url=portal_url,
        username=username,
    )


@router.post("/admin/artists/send-groover-invite", response_model=GrooverInviteResponse)
def admin_send_groover_invite(
    payload: GrooverInviteRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> GrooverInviteResponse:
    """Create or reuse an artist and send a Groover follow-up email with registration form link."""
    require_admin(user)
    email = (payload.email or "").strip().lower()
    if not email:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email is required")

    artist = db.query(Artist).filter(func.lower(Artist.email) == email).first()
    created_artist = False
    base_name = (
        (payload.artist_name or "").strip()
        or (payload.full_name or "").strip()
        or email.split("@")[0]
    )
    if not artist:
        extra = {
            "artist_brand": (payload.artist_name or "").strip() or base_name,
            "full_name": (payload.full_name or "").strip(),
            "source_row": "groover",
        }
        artist = Artist(
            name=base_name[:120],
            email=email,
            notes=(payload.notes or "").strip(),
            extra_json=json.dumps({k: v for k, v in extra.items() if v}),
        )
        db.add(artist)
        db.flush()
        created_artist = True
    else:
        extra = _artist_extra_from_model(artist)
        changed = False
        artist_brand = (payload.artist_name or "").strip()
        full_name = (payload.full_name or "").strip()
        if artist_brand and not str(extra.get("artist_brand") or "").strip():
            extra["artist_brand"] = artist_brand
            changed = True
        if full_name and not str(extra.get("full_name") or "").strip():
            extra["full_name"] = full_name
            changed = True
        if "source_row" not in extra:
            extra["source_row"] = "groover"
            changed = True
        if changed:
            artist.extra_json = json.dumps(extra)
        if (payload.notes or "").strip():
            notes_prefix = (artist.notes or "").strip()
            groover_note = (payload.notes or "").strip()
            if groover_note not in notes_prefix:
                artist.notes = f"{notes_prefix}\n\n{groover_note}".strip()

    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    expires_at = datetime.now(timezone.utc) + timedelta(days=14)
    token_row = ArtistRegistrationToken(
        artist_id=artist.id,
        token_hash=token_hash,
        email=email,
        source="groover",
        expires_at=expires_at,
    )
    db.add(token_row)

    extra = _artist_extra_from_model(artist)
    display_name = (
        (payload.full_name or "").strip()
        or str(extra.get("full_name") or "").strip()
        or (payload.artist_name or "").strip()
        or str(extra.get("artist_brand") or "").strip()
        or (artist.name or "").strip()
        or email
    )
    portal_url = _artist_portal_url()
    registration_url = _artist_registration_link(raw_token)
    subject, body_text = _get_groover_invite_subject_and_body(display_name, registration_url, portal_url)
    body_html = _build_groover_invite_html(
        body_text=body_text,
        registration_url=registration_url,
        portal_url=portal_url,
    )

    success, message = send_email_service(
        to_email=email,
        subject=subject,
        body_text=body_text,
        body_html=body_html,
    )
    if not success:
        db.rollback()
        if "limit" in message.lower():
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)

    db.add(
        ArtistActivityLog(
            artist_id=artist.id,
            activity_type="groover_invite_email",
            details=f"Groover invite sent to {email}",
        )
    )
    db.commit()
    return GrooverInviteResponse(
        message="Groover invite sent.",
        artist_id=artist.id,
        email=email,
        registration_url=registration_url,
        created_artist=created_artist,
    )


@router.post("/admin/artists/send-portal-invite-all", response_model=ArtistPortalInviteBulkResponse)
def admin_send_portal_invite_all(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ArtistPortalInviteBulkResponse:
    """Send portal access email to all active artists that have an email address."""
    require_admin(user)
    artists = (
        db.query(Artist)
        .filter(Artist.is_active.is_(True))
        .filter(Artist.email.isnot(None), Artist.email != "")
        .order_by(Artist.id)
        .all()
    )
    sent = 0
    errors: list[dict] = []
    for artist in artists:
        username = (artist.email or "").strip().lower()
        if not username:
            continue
        extra = _artist_extra_from_model(artist)
        display_name = (
            str(extra.get("full_name") or "").strip()
            or str(extra.get("artist_brand") or "").strip()
            or (artist.name or "").strip()
            or username
        )
        portal_url = _artist_portal_url()
        temporary_password = _generate_temporary_password()
        subject, body_text = _get_portal_invite_subject_and_body(
            display_name, portal_url, username, temporary_password
        )
        body_html = "<p>" + html.escape(body_text).replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
        body_html = body_html.replace(
            html.escape(portal_url),
            f'<a href="{html.escape(portal_url)}">{html.escape(portal_url)}</a>',
        )
        artist.password_hash = hash_password(temporary_password)
        success, message = send_email_service(
            to_email=username,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )
        if not success:
            errors.append({"artist_id": artist.id, "email": username, "detail": message})
            db.rollback()
            continue
        db.add(
            ArtistActivityLog(
                artist_id=artist.id,
                activity_type="portal_invite_email",
                details=f"Portal invite sent to {username}",
            )
        )
        db.commit()
        sent += 1
    return ArtistPortalInviteBulkResponse(
        sent=sent,
        failed=len(errors),
        errors=[ArtistPortalInviteBulkError(**e) for e in errors],
    )


@router.post("/admin/artists/{artist_id}/send-update-profile-invite", response_model=ArtistPortalInviteResponse)
def admin_send_artist_update_profile_invite(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ArtistPortalInviteResponse:
    """Email artist inviting them to update their portal page and see their releases (no password change unless not set)."""
    require_admin(user)
    artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if not artist.is_active:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist is inactive")
    username = (artist.email or "").strip().lower()
    if not username:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist email is required")

    extra = _artist_extra_from_model(artist)
    display_name = (
        str(extra.get("full_name") or "").strip()
        or str(extra.get("artist_brand") or "").strip()
        or (artist.name or "").strip()
        or username
    )
    portal_url = _artist_portal_url()
    temporary_password: str | None = None
    if not artist.password_hash:
        temporary_password = _generate_temporary_password()
        artist.password_hash = hash_password(temporary_password)
    subject, body_text = _get_update_profile_invite_subject_and_body(
        display_name,
        portal_url,
        username,
        temporary_password,
    )
    body_html = "<p>" + html.escape(body_text).replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
    body_html = body_html.replace(
        html.escape(portal_url),
        f'<a href="{html.escape(portal_url)}">{html.escape(portal_url)}</a>',
    )
    success, message = send_email_service(
        to_email=username,
        subject=subject,
        body_text=body_text,
        body_html=body_html,
    )
    if not success:
        db.rollback()
        if "limit" in message.lower():
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)
    db.add(
        ArtistActivityLog(
            artist_id=artist.id,
            activity_type="update_profile_invite_email",
            details=f"Update profile invite sent to {username}",
        )
    )
    db.commit()
    return ArtistPortalInviteResponse(
        message="Update profile invitation sent.",
        portal_url=portal_url,
        username=username,
    )


@router.get("/artists/{artist_id}/releases", response_model=list[ReleaseOut])
def list_artist_releases(
    artist_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    pending_releases = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.artist_id == artist.id, PendingRelease.status != "archived")
        .order_by(desc(PendingRelease.created_at))
        .all()
    )

    return ArtistDashboard(
        artist=ArtistOut.from_artist(artist),
        releases=[ReleaseOut.from_release(item) for item in releases],
        tasks=[TaskOut.model_validate(item) for item in tasks],
        pending_releases=[_serialize_pending_release_detail(item) for item in pending_releases],
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


@router.get("/artist/me", response_model=ArtistOut)
def artist_get_me(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistOut:
    """Get current artist profile (artist role only)."""
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    return ArtistOut.from_artist(artist)


@router.patch("/artist/me", response_model=ArtistOut)
def artist_patch_me(
    payload: ArtistSelfUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistOut:
    """Update current artist profile (artist role only; name, notes, extra fields)."""
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if payload.name is not None:
        artist.name = payload.name
    if payload.notes is not None:
        artist.notes = payload.notes
    if payload.profile_image_media_id is not None:
        media = db.query(ArtistMedia).filter(
            ArtistMedia.id == payload.profile_image_media_id,
            ArtistMedia.artist_id == user.artist_id,
        ).first()
        if not media:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Profile image: file not found or not yours")
    if payload.logo_media_id is not None:
        media = db.query(ArtistMedia).filter(
            ArtistMedia.id == payload.logo_media_id,
            ArtistMedia.artist_id == user.artist_id,
        ).first()
        if not media:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Logo: file not found or not yours")
    extra = _artist_extra_from_model(payload)
    if extra:
        try:
            current = json.loads(artist.extra_json or "{}")
            current.update(extra)
            artist.extra_json = json.dumps(current)
        except (json.JSONDecodeError, TypeError):
            artist.extra_json = json.dumps(extra)
    artist.last_profile_updated_at = datetime.now(timezone.utc)
    db.add(
        ArtistActivityLog(
            artist_id=artist.id,
            activity_type="profile_updated",
            details="Artist updated their portal profile",
        )
    )
    db.commit()
    db.refresh(artist)
    return ArtistOut.from_artist(artist)


@router.patch("/artist/me/password")
def artist_change_password(
    payload: ArtistChangePasswordRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    """Change current artist's portal password (must know current password)."""
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if not artist.password_hash:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password not set. Contact the label.")
    if not verify_password(payload.current_password, artist.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Current password is incorrect")
    if not payload.new_password or len(payload.new_password) < 6:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="New password must be at least 6 characters")
    artist.password_hash = hash_password(payload.new_password)
    db.commit()
    return {"ok": True, "message": "Password updated."}


@router.get("/artist/me/demos", response_model=list[DemoSubmissionOut])
def artist_list_my_demos(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[DemoSubmissionOut]:
    """List demo submissions for the current artist."""
    require_artist(user)
    items = (
        db.query(DemoSubmission)
        .filter(DemoSubmission.artist_id == user.artist_id)
        .order_by(desc(DemoSubmission.created_at))
        .all()
    )
    return [_serialize_demo_submission(item) for item in items]


@router.post("/artist/me/demos", response_model=DemoSubmissionOut)
def artist_submit_demo(
    track_name: str = Form(""),
    musical_style: str = Form(""),
    message: str = Form(""),
    file: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> DemoSubmissionOut:
    """Submit a demo from the artist portal (track name, musical style, optional message + optional file)."""
    require_artist(user)
    track_name_clean = track_name.strip()
    musical_style_clean = musical_style.strip()
    if not track_name_clean:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Track name is required")
    if not musical_style_clean:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Musical style is required")

    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    email = user.email or artist.email

    demo_file_path: str | None = None
    if file and file.filename:
        demo_uploads_dir = os.path.join(settings.upload_dir, "demo_uploads")
        os.makedirs(demo_uploads_dir, exist_ok=True)
        ext = os.path.splitext(file.filename)[1]
        stored_name = f"{uuid.uuid4().hex}{ext}"
        path = os.path.join(demo_uploads_dir, stored_name)
        with open(path, "wb") as out:
            out.write(file.file.read())
        demo_file_path = path

    fields = {"track_name": track_name_clean, "musical_style": musical_style_clean}
    if demo_file_path:
        fields["demo_file_path"] = demo_file_path
    item = DemoSubmission(
        artist_name=artist.name,
        email=email,
        consent_to_emails=False,
        consent_at=None,
        message=message.strip() or None,
        links_json="[]",
        fields_json=json.dumps(fields),
        source="artist_portal",
        source_site_url=None,
        status="demo",
        artist_id=artist.id,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return _serialize_demo_submission(item)


@router.get("/artist/me/demos/{demo_id}/download", response_model=None)
def artist_download_demo_file(
    demo_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> FileResponse | Response:
    """Download the attached file for a demo submission (only own demos)."""
    require_artist(user)
    item = (
        db.query(DemoSubmission)
        .filter(DemoSubmission.id == demo_id, DemoSubmission.artist_id == user.artist_id)
        .first()
    )
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo not found")
    try:
        fields = json.loads(item.fields_json or "{}")
        path = fields.get("demo_file_path")
    except (json.JSONDecodeError, TypeError):
        path = None
    if not path or not os.path.isfile(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No file attached")
    return FileResponse(path, filename=os.path.basename(path))


ARTIST_MEDIA_QUOTA_BYTES = 50 * 1024 * 1024  # 50 MiB per artist


def _artist_media_dir() -> str:
    return os.path.join(settings.upload_dir, "artist_media")


def _artist_media_used_bytes(db: Session, artist_id: int) -> int:
    r = db.query(func.coalesce(func.sum(ArtistMedia.size_bytes), 0)).filter(
        ArtistMedia.artist_id == artist_id
    ).scalar()
    return int(r) if r is not None else 0


@router.get("/artist/me/media", response_model=ArtistMediaListResponse)
def artist_list_my_media(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistMediaListResponse:
    """List current artist's media folder files and quota."""
    require_artist(user)
    items = (
        db.query(ArtistMedia)
        .filter(ArtistMedia.artist_id == user.artist_id)
        .order_by(desc(ArtistMedia.created_at))
        .all()
    )
    used = _artist_media_used_bytes(db, user.artist_id)
    return ArtistMediaListResponse(
        items=[
            ArtistMediaOut(
                id=m.id,
                artist_id=m.artist_id,
                filename=m.filename,
                content_type=m.content_type,
                size_bytes=m.size_bytes,
                created_at=m.created_at,
            )
            for m in items
        ],
        used_bytes=used,
        quota_bytes=ARTIST_MEDIA_QUOTA_BYTES,
    )


@router.post("/artist/me/media", response_model=ArtistMediaOut)
def artist_upload_media(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> ArtistMediaOut:
    """Upload a file to the artist's media folder (50MB quota per artist)."""
    require_artist(user)
    if not file.filename or not file.filename.strip():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Filename required")
    content = file.file.read()
    size = len(content)
    used = _artist_media_used_bytes(db, user.artist_id)
    if used + size > ARTIST_MEDIA_QUOTA_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Media quota exceeded. Used {used // (1024*1024)}MB of 50MB. Free { (ARTIST_MEDIA_QUOTA_BYTES - used) // (1024*1024) }MB.",
        )
    artist_media_root = _artist_media_dir()
    per_artist_dir = os.path.join(artist_media_root, str(user.artist_id))
    os.makedirs(per_artist_dir, exist_ok=True)
    safe_name = os.path.basename(file.filename)
    stored_name = f"{uuid.uuid4().hex}_{safe_name}"
    path = os.path.join(per_artist_dir, stored_name)
    content_type = file.content_type
    with open(path, "wb") as out:
        out.write(content)
    media = ArtistMedia(
        artist_id=user.artist_id,
        filename=safe_name,
        stored_path=path,
        content_type=content_type,
        size_bytes=size,
    )
    db.add(media)
    db.commit()
    db.refresh(media)
    return ArtistMediaOut(
        id=media.id,
        artist_id=media.artist_id,
        filename=media.filename,
        content_type=media.content_type,
        size_bytes=media.size_bytes,
        created_at=media.created_at,
    )


@router.get("/artist/me/media/{media_id}", response_model=None)
def artist_download_media(
    media_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> FileResponse:
    """Download a file from the artist's media folder."""
    require_artist(user)
    media = (
        db.query(ArtistMedia)
        .filter(ArtistMedia.id == media_id, ArtistMedia.artist_id == user.artist_id)
        .first()
    )
    if not media or not os.path.isfile(media.stored_path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    return FileResponse(media.stored_path, filename=media.filename, media_type=media.content_type)


@router.delete("/artist/me/media/{media_id}")
def artist_delete_media(
    media_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> dict:
    """Delete a file from the artist's media folder."""
    require_artist(user)
    media = (
        db.query(ArtistMedia)
        .filter(ArtistMedia.id == media_id, ArtistMedia.artist_id == user.artist_id)
        .first()
    )
    if not media:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    if os.path.isfile(media.stored_path):
        try:
            os.remove(media.stored_path)
        except OSError:
            pass
    db.delete(media)
    db.commit()
    return {"ok": True}


@router.post("/artist/me/campaign-requests", response_model=CampaignRequestOut)
def artist_create_campaign_request(
    payload: CampaignRequestCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> CampaignRequestOut:
    """Artist requests a campaign for a release from the label."""
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    release_title = None
    if payload.release_id:
        release = db.query(Release).filter(
            Release.id == payload.release_id,
            or_(Release.artist_id == user.artist_id, Release.artists.any(Artist.id == user.artist_id)),
        ).first()
        if not release:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release not found")
        release_title = release.title
    req = CampaignRequest(
        artist_id=user.artist_id,
        release_id=payload.release_id,
        message=(payload.message or "").strip() or None,
        status="pending",
    )
    db.add(req)
    db.commit()
    db.refresh(req)
    return _campaign_request_out(req, artist.name, release_title)


@router.get("/artist/me/campaign-requests", response_model=list[CampaignRequestOut])
def artist_list_my_campaign_requests(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[CampaignRequestOut]:
    """List current artist's campaign requests."""
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        return []
    items = (
        db.query(CampaignRequest)
        .filter(CampaignRequest.artist_id == user.artist_id)
        .order_by(desc(CampaignRequest.created_at))
        .all()
    )
    return [_campaign_request_out(r, artist.name, r.release.title if r.release else None) for r in items]


def _campaign_request_out(r: CampaignRequest, artist_name: str, release_title: str | None) -> CampaignRequestOut:
    return CampaignRequestOut(
        id=r.id,
        artist_id=r.artist_id,
        artist_name=artist_name,
        release_id=r.release_id,
        release_title=release_title,
        message=r.message,
        status=r.status,
        admin_notes=r.admin_notes,
        created_at=r.created_at,
        updated_at=r.updated_at,
    )


def _label_inbox_message_out(m: LabelInboxMessage) -> LabelInboxMessageOut:
    return LabelInboxMessageOut(
        id=m.id,
        sender=m.sender,
        body=m.body,
        created_at=m.created_at,
        admin_read_at=m.admin_read_at,
        reply_email_sent_at=m.reply_email_sent_at,
    )


def _label_inbox_unread_count(messages: list[LabelInboxMessage]) -> int:
    return sum(1 for m in messages if m.sender == "artist" and m.admin_read_at is None)


def _label_inbox_thread_out(
    thread: LabelInboxThread,
    artist: Artist,
    last_message_preview: str,
    last_message_at: datetime,
    message_count: int,
    has_label_reply: bool,
    unread_count: int,
) -> LabelInboxThreadOut:
    return LabelInboxThreadOut(
        id=thread.id,
        artist_id=thread.artist_id,
        artist_name=artist.name or "",
        artist_email=artist.email or "",
        last_message_preview=last_message_preview,
        last_message_at=last_message_at,
        created_at=thread.created_at,
        updated_at=thread.updated_at,
        message_count=message_count,
        has_label_reply=has_label_reply,
        unread_count=unread_count,
    )


def _label_inbox_thread_detail_out(thread: LabelInboxThread, artist: Artist, messages: list[LabelInboxMessage]) -> LabelInboxThreadDetailOut:
    has_label_reply = any(m.sender == "label" for m in messages)
    unread_count = _label_inbox_unread_count(messages)
    return LabelInboxThreadDetailOut(
        id=thread.id,
        artist_id=thread.artist_id,
        artist_name=artist.name or "",
        artist_email=artist.email or "",
        created_at=thread.created_at,
        updated_at=thread.updated_at,
        message_count=len(messages),
        has_label_reply=has_label_reply,
        unread_count=unread_count,
        messages=[_label_inbox_message_out(m) for m in messages],
    )


def _get_or_create_latest_label_inbox_thread(db: Session, artist_id: int) -> LabelInboxThread:
    thread = (
        db.query(LabelInboxThread)
        .filter(LabelInboxThread.artist_id == artist_id)
        .order_by(desc(LabelInboxThread.updated_at), desc(LabelInboxThread.id))
        .first()
    )
    if thread:
        return thread
    thread = LabelInboxThread(artist_id=artist_id)
    db.add(thread)
    db.flush()
    return thread


def _mark_admin_thread_as_read(
    db: Session,
    *,
    thread: LabelInboxThread,
    read_at: datetime | None = None,
) -> bool:
    timestamp = read_at or datetime.now(timezone.utc)
    unread_messages = [
        message
        for message in (thread.messages or [])
        if message.sender == "artist" and message.admin_read_at is None
    ]
    if not unread_messages:
        return False
    for message in unread_messages:
        message.admin_read_at = timestamp
    return True


def _create_pending_release_inbox_message(
    db: Session,
    *,
    pending_release: PendingRelease,
    message_prefix: str,
) -> None:
    if pending_release.artist_id is None:
        return
    thread = _get_or_create_latest_label_inbox_thread(db, pending_release.artist_id)
    release_title = (pending_release.release_title or "").strip() or "Untitled"
    message_body = (
        f"{message_prefix}\n\n"
        f"Release: {release_title}\n"
        f"Artist: {(pending_release.artist_name or '').strip() or 'Artist'}\n"
        f"Email: {(pending_release.artist_email or '').strip().lower()}"
    )
    db.add(
        LabelInboxMessage(
            thread_id=thread.id,
            sender="artist",
            body=message_body,
            admin_read_at=None,
        )
    )
    thread.updated_at = datetime.now(timezone.utc)


@router.post("/artist/me/inbox", response_model=LabelInboxThreadDetailOut)
def artist_send_inbox_message(
    payload: LabelInboxSend,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> LabelInboxThreadDetailOut:
    """Artist sends a message to the label. Creates a new thread and first message."""
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    body = (payload.body or "").strip()
    if not body:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Message body is required")
    thread = LabelInboxThread(artist_id=artist.id)
    db.add(thread)
    db.flush()
    msg = LabelInboxMessage(
        thread_id=thread.id,
        sender="artist",
        body=body,
        admin_read_at=None,
    )
    db.add(msg)
    db.commit()
    db.refresh(thread)
    db.refresh(msg)
    messages = [msg]
    return _label_inbox_thread_detail_out(thread, artist, messages)


@router.get("/artist/me/inbox", response_model=list[LabelInboxThreadOut])
def artist_list_my_inbox(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> list[LabelInboxThreadOut]:
    """List current artist's inbox threads."""
    require_artist(user)
    artist = db.query(Artist).filter(Artist.id == user.artist_id).first()
    if not artist:
        return []
    threads = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.messages))
        .filter(LabelInboxThread.artist_id == user.artist_id)
        .order_by(desc(LabelInboxThread.updated_at))
        .all()
    )
    out = []
    for thread in threads:
        msgs = thread.messages or []
        if not msgs:
            continue
        last = msgs[-1]
        preview = (last.body or "")[:120].strip()
        if len(last.body or "") > 120:
            preview += "..."
        has_label = any(m.sender == "label" for m in msgs)
        out.append(
            _label_inbox_thread_out(
                thread,
                artist,
                preview,
                last.created_at,
                len(msgs),
                has_label,
                _label_inbox_unread_count(msgs),
            )
        )
    return out


@router.get("/artist/me/inbox/threads/{thread_id}", response_model=LabelInboxThreadDetailOut)
def artist_get_inbox_thread(
    thread_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> LabelInboxThreadDetailOut:
    """Get one thread and its messages (artist can only see own threads)."""
    require_artist(user)
    thread = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.messages), joinedload(LabelInboxThread.artist))
        .filter(LabelInboxThread.id == thread_id, LabelInboxThread.artist_id == user.artist_id)
        .first()
    )
    if not thread:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    artist = thread.artist
    messages = sorted(thread.messages or [], key=lambda m: m.created_at)
    return _label_inbox_thread_detail_out(thread, artist, messages)


@router.get("/admin/campaign-requests", response_model=list[CampaignRequestOut])
def admin_list_campaign_requests(
    status_filter: str | None = Query(None, description="pending | approved | rejected"),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[CampaignRequestOut]:
    """List all artist campaign requests for the label."""
    require_admin(user)
    q = db.query(CampaignRequest).order_by(desc(CampaignRequest.created_at))
    if status_filter:
        q = q.filter(CampaignRequest.status == status_filter)
    items = q.all()
    out = []
    for r in items:
        artist = db.query(Artist).filter(Artist.id == r.artist_id).first()
        release_title = r.release.title if r.release else None
        out.append(_campaign_request_out(r, artist.name if artist else "", release_title))
    return out


def _create_pending_release_token_and_send_approval_email(
    db: Session,
    req: CampaignRequest,
    artist: Artist,
    release_title: str | None,
) -> None:
    """Create a one-time token and email the artist with the pending-release form link."""
    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    form_link = _pending_release_form_link(raw_token)
    expires_at = datetime.now(timezone.utc) + timedelta(days=30)
    token_row = PendingReleaseToken(
        token_hash=token_hash,
        campaign_request_id=req.id,
        pending_release_id=None,
        artist_id=req.artist_id,
        expires_at=expires_at,
    )
    db.add(token_row)
    db.flush()

    artist_name = (artist.name or "").strip() or "there"
    subject = f"Your track was approved – next steps, {artist_name}"
    body = (
        f"Hi {artist_name},\n\n"
        "Thank you! We're happy to move forward and release the track you sent.\n\n"
        "Please fill in the form below with your full artist details and the track/release details "
        "so we can proceed:\n\n"
        f"{form_link}\n\n"
        "Best regards,\nZalmanim"
    )
    if release_title:
        body = (
            f"Hi {artist_name},\n\n"
            f"Thank you! We're happy to move forward and release \"{release_title}\".\n\n"
            "Please fill in the form below with your full artist details and the track/release details "
            "so we can proceed:\n\n"
            f"{form_link}\n\n"
            "Best regards,\nZalmanim"
        )
    if is_email_configured():
        success, message = send_email_service(
            to_email=artist.email,
            subject=subject,
            body_text=body,
        )
        if not success:
            logging.getLogger(__name__).warning(
                "Failed to send track-approved email to %s: %s", artist.email, message
            )


def _create_pending_release_reminder_token(
    db: Session,
    *,
    pending_release: PendingRelease,
    artist: Artist | None,
    expires_in_days: int,
) -> tuple[str, datetime]:
    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    expires_at = datetime.now(timezone.utc) + timedelta(days=expires_in_days)
    token_row = PendingReleaseToken(
        token_hash=token_hash,
        campaign_request_id=pending_release.campaign_request_id,
        pending_release_id=pending_release.id,
        artist_id=artist.id if artist else pending_release.artist_id,
        expires_at=expires_at,
    )
    db.add(token_row)
    db.flush()
    return _pending_release_form_link(raw_token), expires_at


@router.patch("/admin/campaign-requests/{request_id}", response_model=CampaignRequestOut)
def admin_update_campaign_request(
    request_id: int,
    payload: CampaignRequestUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> CampaignRequestOut:
    """Update campaign request status (approve/reject) and notes. On approve, sends artist an email with form link."""
    require_admin(user)
    req = db.query(CampaignRequest).options(
        joinedload(CampaignRequest.artist),
        joinedload(CampaignRequest.release),
    ).filter(CampaignRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Campaign request not found")
    old_status = req.status
    if payload.status is not None:
        req.status = payload.status
    if payload.admin_notes is not None:
        req.admin_notes = payload.admin_notes

    if req.status == "approved" and old_status != "approved":
        artist = req.artist or db.query(Artist).filter(Artist.id == req.artist_id).first()
        if artist:
            release_title = req.release.title if req.release else None
            _create_pending_release_token_and_send_approval_email(db, req, artist, release_title)

    db.commit()
    db.refresh(req)
    artist = db.query(Artist).filter(Artist.id == req.artist_id).first()
    release_title = req.release.title if req.release else None
    return _campaign_request_out(req, artist.name if artist else "", release_title)


@router.get("/public/pending-release-form", response_model=PendingReleaseFormInfo)
def public_pending_release_form_validate(
    token: str = Query(..., description="One-time token from approval email"),
    db: Session = Depends(get_db),
) -> PendingReleaseFormInfo:
    """Validate token and return artist/release names for the pending-release form (no auth)."""
    row = _get_valid_pending_release_token(db, token)
    artist = db.query(Artist).filter(Artist.id == row.artist_id).first()
    pending_release = _resolve_pending_release_from_token(db, row)
    release_title = None
    if row.campaign_request_id:
        cr = db.query(CampaignRequest).filter(CampaignRequest.id == row.campaign_request_id).first()
        if cr and cr.release_id:
            rel = db.query(Release).filter(Release.id == cr.release_id).first()
            if rel:
                release_title = rel.title
    if pending_release and pending_release.release_title:
        release_title = pending_release.release_title
    return PendingReleaseFormInfo(
        artist_name=(pending_release.artist_name if pending_release else None) or (artist.name if artist else "Artist"),
        artist_email=(pending_release.artist_email if pending_release else None) or (artist.email if artist else ""),
        artist_data=_safe_json_dict(pending_release.artist_data_json) if pending_release else {},
        release_title=release_title or "Your release",
        release_data=_safe_json_dict(pending_release.release_data_json) if pending_release else {},
        expires_at=row.expires_at,
    )


@router.post("/public/pending-release-submit", response_model=PendingReleaseOut)
def public_pending_release_submit(
    payload: PendingReleaseSubmit,
    db: Session = Depends(get_db),
) -> PendingReleaseOut:
    """Submit artist + track details using the token (no auth). Updates existing pending release when available."""
    row = _get_valid_pending_release_token(db, payload.token)
    pr = _resolve_pending_release_from_token(db, row)
    if pr is None:
        pr = PendingRelease(
            campaign_request_id=row.campaign_request_id,
            artist_id=row.artist_id,
            artist_name="Artist",
            artist_email="",
            artist_data_json="{}",
            release_title="Untitled",
            release_data_json="{}",
            status="pending",
        )
        db.add(pr)
        db.flush()
        if getattr(row, "pending_release_id", None) is None:
            row.pending_release_id = pr.id
    pr.artist_name = (payload.artist_name or "").strip() or "Artist"
    pr.artist_email = payload.artist_email.strip().lower()
    pr.artist_data_json = json.dumps(payload.artist_data if isinstance(payload.artist_data, dict) else {})
    pr.release_title = (payload.release_title or "").strip() or "Untitled"
    pr.release_data_json = json.dumps(payload.release_data if isinstance(payload.release_data, dict) else {})
    pr.status = "pending"
    _create_pending_release_inbox_message(
        db,
        pending_release=pr,
        message_prefix="Pending Release form submitted by the artist.",
    )
    db.commit()
    db.refresh(pr)
    return _serialize_pending_release(pr)


@router.post("/public/pending-release-reference-image", response_model=PendingReleaseReferenceUploadOut)
def public_upload_pending_release_reference_image(
    request: Request,
    token: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
) -> PendingReleaseReferenceUploadOut:
    """Upload a cover reference image using a valid pending-release token."""
    _get_valid_pending_release_token(db, token)
    filename = (file.filename or "").strip()
    ext = os.path.splitext(filename)[1].lower()
    if ext not in _ALLOWED_PENDING_RELEASE_IMAGE_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only image files are allowed (jpg, jpeg, png, gif, webp).",
        )
    reference_dir = os.path.join(settings.upload_dir, "pending_release_references")
    os.makedirs(reference_dir, exist_ok=True)
    stored_name = f"{uuid.uuid4().hex}{ext}"
    path = os.path.join(reference_dir, stored_name)
    with open(path, "wb") as out:
        out.write(file.file.read())
    return PendingReleaseReferenceUploadOut(
        url=str(request.url_for("public_pending_release_reference_image_file", filename=stored_name)),
        filename=filename or stored_name,
    )


@router.get(
    "/public/pending-release-reference-image/{filename}",
    response_class=FileResponse,
    name="public_pending_release_reference_image_file",
)
def public_pending_release_reference_image_file(filename: str) -> FileResponse:
    path = os.path.join(settings.upload_dir, "pending_release_references", filename)
    if not os.path.isfile(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")
    media_types = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".gif": "image/gif",
        ".webp": "image/webp",
    }
    return FileResponse(path, media_type=media_types.get(os.path.splitext(filename)[1].lower(), "application/octet-stream"))


@router.get(
    "/public/pending-release-label-image/{filename}",
    response_class=FileResponse,
    name="public_pending_release_label_image_file",
)
def public_pending_release_label_image_file(filename: str) -> FileResponse:
    path = os.path.join(settings.upload_dir, "pending_release_label_images", filename)
    if not os.path.isfile(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image not found")
    media_types = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".gif": "image/gif",
        ".webp": "image/webp",
    }
    return FileResponse(path, media_type=media_types.get(os.path.splitext(filename)[1].lower(), "application/octet-stream"))


@router.get("/admin/inbox", response_model=list[LabelInboxThreadOut])
def admin_list_inbox(
    artist_id: int | None = Query(None, description="Filter by artist id"),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[LabelInboxThreadOut]:
    """List all label inbox threads (artist messages to label)."""
    require_admin(user)
    q = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.artist), joinedload(LabelInboxThread.messages))
        .order_by(desc(LabelInboxThread.updated_at))
        .offset(offset)
        .limit(limit)
    )
    if artist_id is not None:
        q = q.filter(LabelInboxThread.artist_id == artist_id)
    threads = q.all()
    out = []
    for thread in threads:
        artist = thread.artist
        if not artist:
            continue
        msgs = thread.messages or []
        if not msgs:
            continue
        last = msgs[-1]
        preview = (last.body or "")[:120].strip()
        if len(last.body or "") > 120:
            preview += "..."
        has_label = any(m.sender == "label" for m in msgs)
        out.append(
            _label_inbox_thread_out(
                thread,
                artist,
                preview,
                last.created_at,
                len(msgs),
                has_label,
                _label_inbox_unread_count(msgs),
            )
        )
    return out


@router.get("/admin/inbox/threads/{thread_id}", response_model=LabelInboxThreadDetailOut)
def admin_get_inbox_thread(
    thread_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> LabelInboxThreadDetailOut:
    """Get one inbox thread with messages (admin)."""
    require_admin(user)
    thread = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.messages), joinedload(LabelInboxThread.artist))
        .filter(LabelInboxThread.id == thread_id)
        .first()
    )
    if not thread:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    artist = thread.artist
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if _mark_admin_thread_as_read(db, thread=thread):
        db.commit()
        db.refresh(thread)
    messages = sorted(thread.messages or [], key=lambda m: m.created_at)
    return _label_inbox_thread_detail_out(thread, artist, messages)


@router.post("/admin/inbox/threads/{thread_id}/reply", response_model=LabelInboxThreadDetailOut)
def admin_reply_inbox_thread(
    thread_id: int,
    payload: LabelInboxReply,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> LabelInboxThreadDetailOut:
    """Reply to a thread; saves message and sends email to artist."""
    require_admin(user)
    thread = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.messages), joinedload(LabelInboxThread.artist))
        .filter(LabelInboxThread.id == thread_id)
        .first()
    )
    if not thread:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    artist = thread.artist
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    body = (payload.body or "").strip()
    if not body:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Reply body is required")
    now = datetime.now(timezone.utc)
    _mark_admin_thread_as_read(db, thread=thread, read_at=now)
    reply_msg = LabelInboxMessage(
        thread_id=thread.id,
        sender="label",
        body=body,
        admin_read_at=now,
    )
    db.add(reply_msg)
    db.flush()
    if is_email_configured():
        label_name = "Zalmanim"  # could come from settings later
        subject = f"Re: Your message to {label_name}"
        email_body = (
            f"The label has replied to your message.\n\n"
            "---\n\n"
            f"{body}\n\n"
            "---\n\nBest regards,\n" + label_name
        )
        success, msg = send_email_service(
            to_email=artist.email,
            subject=subject,
            body_text=email_body,
        )
        if success:
            reply_msg.reply_email_sent_at = now
        else:
            logging.getLogger(__name__).warning(
                "Failed to send inbox reply email to %s: %s", artist.email, msg
            )
    thread.updated_at = now
    db.commit()
    db.refresh(thread)
    db.refresh(reply_msg)
    thread = (
        db.query(LabelInboxThread)
        .options(joinedload(LabelInboxThread.messages), joinedload(LabelInboxThread.artist))
        .filter(LabelInboxThread.id == thread_id)
        .first()
    )
    artist = thread.artist if thread else None
    if not thread or not artist:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Thread not found after reply")
    messages = sorted(thread.messages or [], key=lambda m: m.created_at)
    return _label_inbox_thread_detail_out(thread, artist, messages)


@router.delete("/admin/inbox/threads/{thread_id}")
def admin_delete_inbox_thread(
    thread_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    """Delete an inbox thread and all of its messages."""
    require_admin(user)
    thread = db.query(LabelInboxThread).filter(LabelInboxThread.id == thread_id).first()
    if not thread:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    db.delete(thread)
    db.commit()
    return {"ok": True}


@router.get("/artist/me/pending-releases/{pending_release_id}", response_model=PendingReleaseDetailOut)
def artist_get_pending_release_detail(
    pending_release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> PendingReleaseDetailOut:
    require_artist(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(
            PendingRelease.id == pending_release_id,
            PendingRelease.artist_id == user.artist_id,
        )
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    return _serialize_pending_release_detail(pending_release)


@router.post("/artist/me/pending-releases/{pending_release_id}/comments", response_model=PendingReleaseDetailOut)
def artist_add_pending_release_comment(
    pending_release_id: int,
    payload: PendingReleaseCommentCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> PendingReleaseDetailOut:
    require_artist(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(
            PendingRelease.id == pending_release_id,
            PendingRelease.artist_id == user.artist_id,
        )
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    body = (payload.body or "").strip()
    if not body:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Comment body is required")
    db.add(PendingReleaseComment(pending_release_id=pending_release.id, sender="artist", body=body))
    db.commit()
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Pending release not found after comment")
    return _serialize_pending_release_detail(pending_release)


@router.post("/artist/me/pending-releases/{pending_release_id}/select-image", response_model=PendingReleaseDetailOut)
def artist_select_pending_release_image(
    pending_release_id: int,
    payload: PendingReleaseSelectImageRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> PendingReleaseDetailOut:
    require_artist(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(
            PendingRelease.id == pending_release_id,
            PendingRelease.artist_id == user.artist_id,
        )
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    release_data = _safe_json_dict(pending_release.release_data_json)
    image_ids = {item.id for item in _pending_release_image_options(release_data)}
    if payload.image_id not in image_ids:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Image option not found")
    release_data["selected_image_id"] = payload.image_id
    _save_pending_release_data(pending_release, release_data)
    db.commit()
    db.refresh(pending_release)
    return _serialize_pending_release_detail(pending_release)


@router.patch("/artist/me/pending-releases/{pending_release_id}/notifications", response_model=PendingReleaseDetailOut)
def artist_update_pending_release_notification_settings(
    pending_release_id: int,
    payload: PendingReleaseNotificationSettingsUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_user),
) -> PendingReleaseDetailOut:
    require_artist(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(
            PendingRelease.id == pending_release_id,
            PendingRelease.artist_id == user.artist_id,
        )
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    release_data = _safe_json_dict(pending_release.release_data_json)
    release_data["notifications_muted"] = payload.notifications_muted
    _save_pending_release_data(pending_release, release_data)
    db.commit()
    db.refresh(pending_release)
    return _serialize_pending_release_detail(pending_release)


@router.get("/admin/pending-releases", response_model=list[PendingReleaseDetailOut])
def admin_list_pending_releases(
    status_filter: str | None = Query(None, description="pending | processed | archived"),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
 ) -> list[PendingReleaseDetailOut]:
    """List pending-for-release items (tracks with full details submitted, waiting for treatment)."""
    require_admin(user)
    # Backfill: ensure every approved demo has a PendingRelease (fixes demos approved before we created PendingRelease on approve).
    existing_demo_ids = {
        r[0]
        for r in db.query(PendingRelease.demo_submission_id)
        .filter(PendingRelease.demo_submission_id.isnot(None))
        .all()
    }
    approved_without_pr = [
        d for d in db.query(DemoSubmission).filter(DemoSubmission.status == "approved").all()
        if d.id not in existing_demo_ids
    ]
    for item in approved_without_pr:
        _create_pending_release_for_demo(db, item)
    if approved_without_pr:
        db.commit()
    q = db.query(PendingRelease).options(joinedload(PendingRelease.comments))
    if status_filter in ("pending", "processed", "archived"):
        q = q.filter(PendingRelease.status == status_filter)
    else:
        q = q.filter(PendingRelease.status != "archived")
    q = q.order_by(desc(PendingRelease.created_at)).offset(offset).limit(limit)
    items = q.all()
    reminder_rows = (
        db.query(ArtistActivityLog.artist_id, func.max(ArtistActivityLog.created_at))
        .filter(ArtistActivityLog.activity_type == "pending_release_reminder_email")
        .group_by(ArtistActivityLog.artist_id)
        .all()
    )
    last_reminder_map = {artist_id: created_at for artist_id, created_at in reminder_rows}
    out = []
    for pr in items:
        out.append(_serialize_pending_release_detail(pr, last_reminder_sent_at=last_reminder_map.get(pr.artist_id)))
    return out


@router.get("/admin/pending-releases/{pending_release_id}", response_model=PendingReleaseDetailOut)
def admin_get_pending_release_detail(
    pending_release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseDetailOut:
    require_admin(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    return _serialize_pending_release_detail(pending_release)


@router.post("/admin/pending-releases/{pending_release_id}/comments", response_model=PendingReleaseDetailOut)
def admin_add_pending_release_comment(
    pending_release_id: int,
    payload: PendingReleaseCommentCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseDetailOut:
    require_admin(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    body = (payload.body or "").strip()
    if not body:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Comment body is required")
    db.add(PendingReleaseComment(pending_release_id=pending_release.id, sender="label", body=body))
    db.commit()
    db.refresh(pending_release)
    _notify_pending_release_artist(
        pending_release,
        subject=f'Update on your release "{pending_release.release_title}"',
        body_lines=[
            "The label added a new update to your pending release page.",
            "",
            body,
        ],
    )
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Pending release not found after comment")
    return _serialize_pending_release_detail(pending_release)


@router.post("/admin/pending-releases/{pending_release_id}/images", response_model=PendingReleaseDetailOut)
def admin_upload_pending_release_image(
    request: Request,
    pending_release_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseDetailOut:
    require_admin(user)
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    filename = (file.filename or "").strip()
    ext = os.path.splitext(filename)[1].lower()
    if ext not in _ALLOWED_PENDING_RELEASE_IMAGE_EXTENSIONS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only image files are allowed.")
    image_dir = os.path.join(settings.upload_dir, "pending_release_label_images")
    os.makedirs(image_dir, exist_ok=True)
    stored_name = f"{uuid.uuid4().hex}{ext}"
    path = os.path.join(image_dir, stored_name)
    with open(path, "wb") as out:
        out.write(file.file.read())
    release_data = _safe_json_dict(pending_release.release_data_json)
    image_options = release_data.get("image_options")
    if not isinstance(image_options, list):
        image_options = []
    image_options.append(
        {
            "id": uuid.uuid4().hex,
            "url": str(request.url_for("public_pending_release_label_image_file", filename=stored_name)),
            "filename": filename or stored_name,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
    )
    release_data["image_options"] = image_options
    if not release_data.get("selected_image_id") and image_options:
        release_data["selected_image_id"] = image_options[0]["id"]
    _save_pending_release_data(pending_release, release_data)
    db.commit()
    db.refresh(pending_release)
    _notify_pending_release_artist(
        pending_release,
        subject=f'New image option for "{pending_release.release_title}"',
        body_lines=[
            "The label uploaded a new image option for your release.",
            "Open the pending release page in the artist portal to review and choose the image you want.",
        ],
    )
    return _serialize_pending_release_detail(pending_release)


@router.post("/admin/pending-releases/{pending_release_id}/archive", response_model=PendingReleaseActionResponse)
def admin_archive_pending_release(
    pending_release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseActionResponse:
    require_admin(user)
    pending_release = db.query(PendingRelease).filter(PendingRelease.id == pending_release_id).first()
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    pending_release.status = "archived"
    db.add(pending_release)
    db.commit()
    return PendingReleaseActionResponse(success=True, message="Pending release archived")


@router.delete("/admin/pending-releases/{pending_release_id}", response_model=PendingReleaseActionResponse)
def admin_delete_pending_release(
    pending_release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseActionResponse:
    require_admin(user)
    pending_release = db.query(PendingRelease).filter(PendingRelease.id == pending_release_id).first()
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    db.delete(pending_release)
    db.commit()
    return PendingReleaseActionResponse(success=True, message="Pending release deleted")


@router.post("/admin/pending-releases/{pending_release_id}/send-reminder", response_model=PendingReleaseReminderResponse)
def admin_send_pending_release_reminder(
    pending_release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> PendingReleaseReminderResponse:
    """Send a reminder email with a one-week link so the artist can complete or update release details."""
    require_admin(user)
    pending_release = db.query(PendingRelease).filter(PendingRelease.id == pending_release_id).first()
    if not pending_release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pending release not found")
    artist = None
    if pending_release.artist_id is not None:
        artist = db.query(Artist).filter(Artist.id == pending_release.artist_id).first()
    to_email = (pending_release.artist_email or (artist.email if artist else "") or "").strip().lower()
    if not to_email:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist email is missing for this pending release")
    form_link, expires_at = _create_pending_release_reminder_token(
        db,
        pending_release=pending_release,
        artist=artist,
        expires_in_days=7,
    )
    artist_name = (pending_release.artist_name or (artist.name if artist else "") or "").strip() or "there"
    release_title = (pending_release.release_title or "").strip() or "your release"
    expires_label = expires_at.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    subject = f"Reminder: please complete the details for \"{release_title}\""
    body = (
        f"Hi {artist_name},\n\n"
        f"We still need a few details to complete your approved release \"{release_title}\".\n\n"
        "Please update the release details here:\n"
        f"{form_link}\n\n"
        f"This link is valid until {expires_label}.\n\n"
        "You can add the WAV download link, confirm whether mastering is needed, add a cover reference image, "
        "update the musical style, and send any marketing/story notes for the release.\n\n"
        "If mastering is needed, please make sure the files have 6 dB headroom.\n\n"
        "Best regards,\nZalmanim"
    )
    success, message = send_email_service(
        to_email=to_email,
        subject=subject,
        body_text=body,
    )
    if not success:
        db.rollback()
        if "limit" in message.lower():
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)
    if pending_release.artist_id is not None:
        db.add(
            ArtistActivityLog(
                artist_id=pending_release.artist_id,
                activity_type="pending_release_reminder_email",
                details=f"pending_release_id={pending_release.id}",
            )
        )
    
    db.commit()
    return PendingReleaseReminderResponse(
        success=True,
        message="Completion email sent",
        expires_at=expires_at,
    )


@router.get("/public/demo-confirm-form", response_model=DemoConfirmFormInfo)
def public_demo_confirm_form_validate(
    token: str = Query(..., description="One-time token from demo approval email"),
    db: Session = Depends(get_db),
) -> DemoConfirmFormInfo:
    """Validate token and return prefilled form data from the demo submission (no auth)."""
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    row = (
        db.query(DemoConfirmationToken)
        .filter(
            DemoConfirmationToken.token_hash == token_hash,
            DemoConfirmationToken.used_at.is_(None),
            DemoConfirmationToken.expires_at > datetime.now(timezone.utc),
        )
        .first()
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or expired token")
    item = db.query(DemoSubmission).filter(DemoSubmission.id == row.demo_submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")
    links = _safe_json_list(item.links_json)
    return DemoConfirmFormInfo(
        artist_name=item.artist_name or "",
        contact_name=item.contact_name,
        email=item.email or "",
        phone=item.phone,
        genre=item.genre,
        city=item.city,
        message=item.message,
        links=[str(link).strip() for link in links if str(link).strip()],
        release_title="Your release",
    )


@router.post("/public/demo-confirm-submit", response_model=PendingReleaseOut)
def public_demo_confirm_submit(
    payload: DemoConfirmSubmit,
    db: Session = Depends(get_db),
) -> PendingReleaseOut:
    """Submit confirmed details; creates PendingRelease, sets demo status to pending_release."""
    token_hash = hashlib.sha256(payload.token.encode()).hexdigest()
    row = (
        db.query(DemoConfirmationToken)
        .filter(
            DemoConfirmationToken.token_hash == token_hash,
            DemoConfirmationToken.used_at.is_(None),
            DemoConfirmationToken.expires_at > datetime.now(timezone.utc),
        )
        .first()
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or expired token")
    item = db.query(DemoSubmission).filter(DemoSubmission.id == row.demo_submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")
    if item.status == "pending_release":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This demo was already confirmed and is in PENDING RELEASE.",
        )
    row.used_at = datetime.now(timezone.utc)
    artist_id = item.artist_id
    artist_name = (payload.artist_name or "").strip() or "Artist"
    artist_email = payload.artist_email.strip().lower()
    release_title = (payload.release_title or "").strip() or "Untitled"
    artist_data_json = json.dumps(payload.artist_data if isinstance(payload.artist_data, dict) else {})
    release_data_json = json.dumps(payload.release_data if isinstance(payload.release_data, dict) else {})

    # Update existing PendingRelease created on approve, or create one for legacy approved demos
    pr = db.query(PendingRelease).filter(PendingRelease.demo_submission_id == item.id).first()
    if pr:
        pr.artist_id = artist_id
        pr.artist_name = artist_name
        pr.artist_email = artist_email
        pr.artist_data_json = artist_data_json
        pr.release_title = release_title[:300]
        pr.release_data_json = release_data_json
        pr.status = "pending"
    else:
        pr = PendingRelease(
            campaign_request_id=None,
            demo_submission_id=item.id,
            artist_id=artist_id,
            artist_name=artist_name,
            artist_email=artist_email,
            artist_data_json=artist_data_json,
            release_title=release_title[:300],
            release_data_json=release_data_json,
            status="pending",
        )
        db.add(pr)
    _create_pending_release_inbox_message(
        db,
        pending_release=pr,
        message_prefix="Pending Release details were completed from the demo approval form.",
    )
    item.status = "pending_release"
    db.commit()
    db.refresh(pr)
    artist_data = json.loads(pr.artist_data_json or "{}") if isinstance(pr.artist_data_json, str) else {}
    release_data = json.loads(pr.release_data_json or "{}") if isinstance(pr.release_data_json, str) else {}
    return PendingReleaseOut(
        id=pr.id,
        campaign_request_id=pr.campaign_request_id,
        demo_submission_id=pr.demo_submission_id,
        artist_id=pr.artist_id,
        artist_name=pr.artist_name,
        artist_email=pr.artist_email,
        artist_data=artist_data,
        release_title=pr.release_title,
        release_data=release_data,
        status=pr.status,
        created_at=pr.created_at,
        updated_at=pr.updated_at,
    )


@router.get("/public/artist-registration", response_model=ArtistRegistrationFormInfo)
def public_artist_registration_info(
    token: str = Query(..., description="One-time token from Groover invite email"),
    db: Session = Depends(get_db),
) -> ArtistRegistrationFormInfo:
    """Validate registration token and return prefilled artist info."""
    row = _get_valid_artist_registration_token(db, token)
    artist = db.query(Artist).filter(Artist.id == row.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    extra = _artist_extra_from_model(artist)
    return ArtistRegistrationFormInfo(
        artist_id=artist.id,
        email=row.email,
        artist_name=str(extra.get("artist_brand") or artist.name or "").strip(),
        full_name=str(extra.get("full_name") or "").strip(),
        notes=(artist.notes or "").strip(),
        expires_at=row.expires_at,
    )


@router.post("/public/artist-registration", response_model=ArtistRegistrationCompleteResponse)
def public_artist_registration_submit(
    payload: ArtistRegistrationCompleteRequest,
    db: Session = Depends(get_db),
) -> ArtistRegistrationCompleteResponse:
    """Complete artist registration from email invite and enable portal sign-in."""
    row = _get_valid_artist_registration_token(db, payload.token)
    artist = db.query(Artist).filter(Artist.id == row.artist_id).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    if not payload.artist_name.strip():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Artist name is required")
    if not payload.password or len(payload.password) < 6:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 6 characters")

    artist.name = payload.artist_name.strip()[:120]
    artist.notes = (payload.notes or "").strip()
    current = _artist_extra_from_model(artist)
    current.update(
        {
            "artist_brand": payload.artist_name.strip(),
            "full_name": (payload.full_name or "").strip(),
            "website": (payload.website or "").strip(),
            "soundcloud": (payload.soundcloud or "").strip(),
            "instagram": (payload.instagram or "").strip(),
            "spotify": (payload.spotify or "").strip(),
            "apple_music": (payload.apple_music or "").strip(),
            "youtube": (payload.youtube or "").strip(),
            "tiktok": (payload.tiktok or "").strip(),
            "facebook": (payload.facebook or "").strip(),
            "linktree": (payload.linktree or "").strip(),
            "source_row": current.get("source_row") or "groover",
        }
    )
    artist.extra_json = json.dumps({k: v for k, v in current.items() if v not in (None, "")})
    artist.password_hash = hash_password(payload.password)
    artist.last_profile_updated_at = datetime.now(timezone.utc)
    row.used_at = datetime.now(timezone.utc)
    db.add(
        ArtistActivityLog(
            artist_id=artist.id,
            activity_type="groover_registration_completed",
            details=f"Registration completed for {artist.email}",
        )
    )
    db.commit()
    return ArtistRegistrationCompleteResponse(
        message="Registration completed. You can now sign in to the artist portal.",
        portal_url=_artist_portal_url(),
    )


@router.get("/admin/releases", response_model=list[ReleaseOut])
def list_admin_releases(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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


@router.get("/admin/reports/artists-signed-in", response_model=list[ArtistOut])
def report_artists_signed_in(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[ArtistOut]:
    """Artists who have already signed in to the artist portal."""
    require_admin(user)
    artists = (
        db.query(Artist)
        .filter(Artist.last_login_at.isnot(None))
        .order_by(desc(Artist.last_login_at), Artist.name)
        .all()
    )
    return [ArtistOut.from_artist(artist) for artist in artists]


@router.patch("/admin/releases/{release_id}", response_model=ReleaseOut)
def update_release_artists(
    release_id: int,
    payload: ReleaseUpdateArtists,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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


# Database browser (Settings > DB) - admin only
def _db_row_to_dict(row) -> dict:
    """Convert a result row to a JSON-serializable dict (dates to isoformat).
    Supports both Row (row._mapping) and RowMapping from result.mappings()."""
    mapping = getattr(row, "_mapping", row)
    out = {}
    for k, v in mapping.items():
        if hasattr(v, "isoformat"):
            out[k] = v.isoformat()
        elif v is None or isinstance(v, (str, int, float, bool)):
            out[k] = v
        else:
            out[k] = str(v)
    # Redact password-like columns
    for key in list(out.keys()):
        if "password" in key.lower() or "secret" in key.lower() or "token" in key.lower():
            if out[key] is not None and str(out[key]).strip():
                out[key] = "***"
    return out


@router.get("/admin/db/tables")
def list_db_tables(
    user: UserContext = Depends(get_current_lm_user),
) -> list[dict]:
    """List database table names for admin Settings > DB."""
    require_admin(user)
    return [{"name": name} for name in sorted(Base.metadata.tables.keys())]


@router.get("/admin/db/tables/{table_name}")
def get_db_table_content(
    table_name: str,
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    """Return rows from a table (admin only). Whitelisted table names only."""
    require_admin(user)
    if table_name not in Base.metadata.tables:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Table not found")
    with engine.connect() as conn:
        # Table name is whitelisted; use bound params for limit/offset
        result = conn.execute(
            text(f'SELECT * FROM "{table_name}" LIMIT :lim OFFSET :off'),
            {"lim": limit, "off": offset},
        )
        rows = [_db_row_to_dict(row) for row in result.mappings()]
        result_count = conn.execute(
            text(f'SELECT COUNT(*) FROM "{table_name}"'),
        ).scalar()
    return {"rows": rows, "total_count": result_count, "limit": limit, "offset": offset}


# System logs (Settings > Logs)
@router.get("/admin/logs", response_model=list[SystemLogOut])
def list_system_logs(
    limit: int = Query(200, ge=1, le=500),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[SystemLogOut]:
    """List recent system and mail logs for admin Settings > Logs."""
    require_admin(user)
    rows = (
        db.query(SystemLog)
        .order_by(desc(SystemLog.id))
        .limit(limit)
        .all()
    )
    return [SystemLogOut.model_validate(r) for r in rows]


# System settings (mail editable via UI; OAuth read-only from env)
@router.get("/admin/settings", response_model=SystemSettingsOut)
def get_system_settings(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
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
        email_footer=mail.get("email_footer", "") or "",
        demo_rejection_subject=mail.get("demo_rejection_subject", "") or "",
        demo_rejection_body=mail.get("demo_rejection_body", "") or "",
        demo_approval_subject=mail.get("demo_approval_subject", "") or "",
        demo_approval_body=mail.get("demo_approval_body", "") or "",
        demo_receipt_subject=mail.get("demo_receipt_subject", "") or "",
        demo_receipt_body=mail.get("demo_receipt_body", "") or "",
        portal_invite_subject=mail.get("portal_invite_subject", "") or "",
        portal_invite_body=mail.get("portal_invite_body", "") or "",
        groover_invite_subject=mail.get("groover_invite_subject", "") or "",
        groover_invite_body=mail.get("groover_invite_body", "") or "",
        update_profile_invite_subject=mail.get("update_profile_invite_subject", "") or "",
        update_profile_invite_body=mail.get("update_profile_invite_body", "") or "",
        password_reset_subject=mail.get("password_reset_subject", "") or "",
        password_reset_body=mail.get("password_reset_body", "") or "",
        oauth_redirect_base=settings.oauth_redirect_base or "",
        google_oauth_configured=bool(settings.google_client_id and settings.google_client_secret),
        gmail_connected=gmail_connected,
        gmail_connected_email=gmail_email,
        oauth_success_redirect=settings.oauth_success_redirect or "",
        artist_portal_base_url=_artist_portal_url(),
    )


@router.patch("/admin/settings/mail", response_model=SystemSettingsOut)
def update_system_settings_mail(
    payload: SystemSettingsMailUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
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
        email_footer=payload.email_footer,
        demo_rejection_subject=payload.demo_rejection_subject,
        demo_rejection_body=payload.demo_rejection_body,
        demo_approval_subject=payload.demo_approval_subject,
        demo_approval_body=payload.demo_approval_body,
        demo_receipt_subject=payload.demo_receipt_subject,
        demo_receipt_body=payload.demo_receipt_body,
        portal_invite_subject=payload.portal_invite_subject,
        portal_invite_body=payload.portal_invite_body,
        groover_invite_subject=payload.groover_invite_subject,
        groover_invite_body=payload.groover_invite_body,
        update_profile_invite_subject=payload.update_profile_invite_subject,
        update_profile_invite_body=payload.update_profile_invite_body,
        password_reset_subject=payload.password_reset_subject,
        password_reset_body=payload.password_reset_body,
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
        email_footer=mail.get("email_footer", "") or "",
        demo_rejection_subject=mail.get("demo_rejection_subject", "") or "",
        demo_rejection_body=mail.get("demo_rejection_body", "") or "",
        demo_approval_subject=mail.get("demo_approval_subject", "") or "",
        demo_approval_body=mail.get("demo_approval_body", "") or "",
        demo_receipt_subject=mail.get("demo_receipt_subject", "") or "",
        demo_receipt_body=mail.get("demo_receipt_body", "") or "",
        portal_invite_subject=mail.get("portal_invite_subject", "") or "",
        portal_invite_body=mail.get("portal_invite_body", "") or "",
        groover_invite_subject=mail.get("groover_invite_subject", "") or "",
        groover_invite_body=mail.get("groover_invite_body", "") or "",
        update_profile_invite_subject=mail.get("update_profile_invite_subject", "") or "",
        update_profile_invite_body=mail.get("update_profile_invite_body", "") or "",
        password_reset_subject=mail.get("password_reset_subject", "") or "",
        password_reset_body=mail.get("password_reset_body", "") or "",
        oauth_redirect_base=settings.oauth_redirect_base or "",
        google_oauth_configured=bool(settings.google_client_id and settings.google_client_secret),
        gmail_connected=gmail_connected,
        gmail_connected_email=gmail_email,
        oauth_success_redirect=settings.oauth_success_redirect or "",
        artist_portal_base_url=_artist_portal_url(),
    )



@router.post("/admin/settings/mail/test", response_model=SystemSettingsMailTestResponse)
def test_system_settings_mail(
    payload: SystemSettingsMailTestRequest,
    user: UserContext = Depends(get_current_lm_user),
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


@router.get("/admin/email/history", response_model=EmailRecipientHistoryOut)
def get_email_recipient_history(
    email: str = Query(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> EmailRecipientHistoryOut:
    """Return whether the system already sent email to this recipient."""
    require_admin(user)
    email_value = (email or "").strip().lower()
    if not email_value or "@" not in email_value:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A valid email is required",
        )

    message_prefix = f"email sent to {email_value}"
    rows = (
        db.query(SystemLog)
        .filter(
            SystemLog.category == "mail",
            SystemLog.level == "info",
            func.lower(SystemLog.message).like(f"{message_prefix}%"),
        )
        .order_by(SystemLog.created_at.desc(), SystemLog.id.desc())
        .all()
    )
    latest = rows[0] if rows else None
    return EmailRecipientHistoryOut(
        email=email_value,
        has_sent_before=bool(rows),
        send_count=len(rows),
        last_sent_at=latest.created_at if latest else None,
        last_subject=((latest.details or "").strip() or None) if latest else None,
    )


@router.post("/admin/email/send", response_model=SendEmailResponse)
def send_email(
    payload: SendEmailRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
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
    user: UserContext = Depends(get_current_lm_user),
) -> CampaignOut:
    require_admin(user)
    campaign = cancel_schedule(db, campaign_id)
    if not campaign:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Campaign not found or not scheduled")
    return CampaignOut.from_campaign(campaign)











@router.get("/admin/agents/registry", response_model=list[AgentDefinitionOut])
def get_agent_registry_route(user: UserContext = Depends(get_current_user)) -> list[AgentDefinitionOut]:
    require_admin(user)
    plan = build_agent_plan("system overview", max_agents=6)
    return [AgentDefinitionOut.model_validate(agent) for agent in plan["agents"]]


@router.post("/admin/agents/plan", response_model=AgentPlanOut)
def plan_agent_delegation(
    payload: AgentPlanRequest,
    user: UserContext = Depends(get_current_lm_user),
) -> AgentPlanOut:
    require_admin(user)
    plan = build_agent_plan(payload.text, max_agents=payload.max_agents)
    return AgentPlanOut.model_validate(plan)


# --- Backup / Restore (admin only) ---


@router.get("/admin/backup")
def download_backup(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
):
    """Export all DB data as a JSON backup file. Use on another system to restore via POST /admin/restore."""
    require_admin(user)
    data = export_database(db)
    payload = json.dumps(data, ensure_ascii=False, indent=2)
    filename = f"labelops-backup-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}.json"
    return Response(
        content=payload,
        media_type="application/json",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.post("/admin/restore", response_model=dict)
def upload_restore(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    """Replace all DB data with the uploaded backup file (from GET /admin/backup). Use with caution."""
    require_admin(user)
    if not file.filename or not file.filename.lower().endswith(".json"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Upload a JSON backup file")
    try:
        body = file.file.read()
        data = json.loads(body.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid JSON: {e}") from e
    try:
        restore_database(db, data)
    except ValueError as e:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    except SQLAlchemyError as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Restore failed: {e}",
        ) from e
    return {"message": "Restore completed successfully."}



