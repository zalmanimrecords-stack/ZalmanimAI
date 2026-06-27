import csv
import hashlib
import html
import io
import json
import logging
import os
import re
import secrets
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Any
from urllib.parse import parse_qsl, unquote, urlencode, urlparse, urlunparse

import httpx
from PIL import Image, ImageOps

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Query, Request, UploadFile, status
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse, Response
from sqlalchemy import desc, func, or_, text, update
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session, joinedload

from app.api.deps import (
    LM_FORBIDDEN_ARTIST_DETAIL,
    get_current_user,
    get_current_lm_user,
    require_admin,
    require_artist,
    security,
)
from app.api.campaign_routes import router as campaign_router
from app.api.campaign_request_routes import router as campaign_request_router
from app.api.inbox_routes import _create_pending_release_inbox_message, router as inbox_router
from app.api.pending_release_routes import router as pending_release_router
from app.api.release_routes import router as release_router
from app.api.catalog_routes import router as catalog_router
from app.api.settings_routes import router as settings_router
from app.api.artist_portal_routes import router as artist_portal_router
from app.api.artist_routes import router as artist_router
from app.api.demo_helpers import _log_auth_attempt
from app.api.demo_routes import router as demo_router
from app.api.public_routes import router as public_router
from app.api.mail_templates import (
    _apply_demo_rejection_placeholders,
    _artist_portal_url,
    _build_demo_receipt_body,
    _build_demo_receipt_html,
    _build_demo_receipt_subject,
    _build_demo_submission_summary,
    _build_groover_invite_html,
    _default_demo_approval_body,
    _default_demo_approval_subject,
    _default_demo_receipt_body,
    _default_demo_receipt_subject,
    _default_demo_rejection_body,
    _default_demo_rejection_subject,
    _default_groover_invite_body,
    _default_groover_invite_subject,
    _default_portal_invite_body,
    _default_portal_invite_subject,
    _default_password_reset_body,
    _default_password_reset_subject,
    _default_update_profile_invite_body,
    _default_update_profile_invite_subject,
    _ensure_demo_mailing_list,
    _get_demo_approval_subject_and_body,
    _get_demo_receipt_subject_and_body,
    _get_demo_rejection_subject_and_body,
    _get_groover_invite_subject_and_body,
    _get_portal_invite_subject_and_body,
    _get_password_reset_subject_and_body,
    _get_update_profile_invite_subject_and_body,
    _safe_json_dict,
    _safe_json_list,
    _upsert_demo_mailing_subscriber,
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
    MailingList,
    MailingSubscriber,
    PasswordResetToken,
    PendingRelease,
    PendingReleaseComment,
    PendingReleaseToken,
    Release,
    ReleaseLinkCandidate,
    ReleaseLinkScanRun,
    release_artists_table,
    migrate_legacy_social_connection_tokens,
    SocialConnection,
    SystemLog,
    User,
    UserIdentity,
)
from app.api.oauth_helpers import (
    _GOOGLE_AUTH_SCOPES,
    _build_facebook_auth_url,
    _build_google_auth_url,
    _build_oauth_state,
    _build_provider_auth_url,
    _decode_oauth_state,
    _exchange_facebook_code,
    _exchange_google_code,
    _exchange_provider_code,
    _fetch_facebook_userinfo,
    _fetch_google_userinfo,
    _fetch_provider_profile,
    _oauth_callback_url,
    _origin_from_url,
    _redirect_with_fragment_params,
    _redirect_with_params,
    _sanitize_redirect_target,
)
from app.api.pending_release_helpers import (
    _get_valid_artist_registration_token,
    _get_valid_pending_release_token,
    _normalize_public_image_url_path_for_match,
    _notify_pending_release_artist,
    _pending_release_comment_out,
    _pending_release_form_link,
    _pending_release_image_options,
    _pending_release_notifications_muted,
    _pending_release_selected_image_id,
    _pending_release_upload_path_from_public_url,
    _resolve_pending_release_from_token,
    _save_pending_release_data,
    _serialize_pending_release,
    _serialize_pending_release_detail,
)
from app.api.upload_helpers import (
    _bytes_to_jpg_3000_square,
    _pending_release_label_image_base_name,
    _read_upload_bytes,
    _sanitize_filename_component,
    _unique_filename,
)
from app.services import auth_rate_limit
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
    LinktreeLink,
    LinktreeOut,
    LinktreeRelease,
    CatalogTrackOut,
    DemoConfirmFormInfo,
    DemoConfirmSubmit,
    DemoSubmissionApproveRequest,
    DemoSubmissionCreate,
    DemoSubmissionOut,
    DemoSubmissionUpdate,
    EmailRateLimitStatus,
    EmailRecipientHistoryOut,
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
    PendingReleaseRemoveStoredImageBody,
    PendingReleaseReminderResponse,
    PendingReleaseSelectImageRequest,
    PendingReleaseSubmit,
    ReleaseLinkCandidateOut,
    ReleaseLinkCandidateReviewResponse,
    ReleaseMinisiteSendRequest,
    ReleaseMinisiteUpdateRequest,
    ReleaseLinkScanRequest,
    ReleaseLinkScanResponse,
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
    smtp_config_for_admin_test,
    test_smtp_connection,
)
from app.services.mail_settings import build_mail_config, get_effective_mail_config_for_api, save_mail_settings
from app.services.release_link_discovery import (
    SUPPORTED_RELEASE_LINK_PLATFORMS,
    approve_release_link_candidate,
    best_release_link,
    candidate_artwork_url,
    download_release_cover_after_approve,
    ensure_periodic_release_link_scan_runs,
    parse_platform_links,
    process_release_link_scan_run,
    queue_release_link_scan,
    refresh_release_cover_artwork,
    reject_release_link_candidate,
)
from app.services.system_log import append_system_log
from app.services.agent_supervisor import build_agent_plan, get_agent_registry
from app.services.backup_service import export_database, restore_database

router = APIRouter()


def _client_ip_from_request(request: Request) -> str:
    forwarded_for = (request.headers.get("x-forwarded-for") or "").strip()
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    return (request.client.host if request.client else "") or "unknown"


def _touch_user_login(db: Session, user: User) -> None:
    user.last_login_at = datetime.now(timezone.utc)
    db.commit()


def _user_token_response(user: User) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(str(user.id)),
        role=user.role,
        email=user.email,
        full_name=user.full_name,
        permissions=permissions_for_role(user.role),
    )


def _serialize_user(user: User) -> UserOut:
    artist = getattr(user, "artist", None)
    identities = [UserIdentityOut.model_validate(i) for i in (user.identities or [])]
    return UserOut(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        permissions=permissions_for_role(user.role),
        artist_id=getattr(artist, "id", None),
        artist_name=getattr(artist, "brand", None) or getattr(artist, "full_name", None),
        is_active=bool(user.is_active),
        created_at=getattr(user, "created_at", None),
        updated_at=getattr(user, "updated_at", None),
        last_login_at=getattr(user, "last_login_at", None),
        identities=identities,
    )


_VALID_USER_ROLES = ("admin", "manager", "artist")


def _validate_user_role(role: str | None) -> str:
    normalized = (role or "").strip().lower()
    if normalized not in _VALID_USER_ROLES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid role '{role}'. Must be one of: {', '.join(_VALID_USER_ROLES)}.",
        )
    return normalized


def _touch_artist_login(db: Session, artist) -> None:
    artist.last_login_at = datetime.now(timezone.utc)
    db.commit()


def _artist_token_response(artist) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(f"artist:{artist.id}"),
        role="artist",
        email=artist.email,
        full_name=getattr(artist, "full_name", None) or getattr(artist, "brand", None),
        permissions=permissions_for_role("artist"),
    )


def _ensure_artist_reset_user(db: Session, artist) -> User | None:
    # Artists log in via the artists table directly; password reset for artists is
    # handled by setting artist.password_hash, not by creating a shadow User row.
    # Returning None here makes the reset flow fall back to "no account" behavior,
    # which surfaces the standard 'reset link sent if account exists' response.
    return None


def _find_or_create_oauth_user(
    db: Session,
    provider: str,
    provider_subject: str,
    email: str | None,
    display_name: str | None,
) -> User:
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail=f"OAuth login via {provider} is not configured on this deployment.",
    )


def _upsert_google_mail_connection(
    db: Session,
    *,
    email: str | None,
    access_token: str | None,
    refresh_token: str | None,
    scopes: list[str] | None,
) -> None:
    # Gmail SMTP integration is not configured on this deployment; no-op.
    return None
router.include_router(campaign_router)
router.include_router(campaign_request_router)
router.include_router(inbox_router)
router.include_router(pending_release_router)
router.include_router(release_router)
router.include_router(catalog_router)
router.include_router(settings_router)
router.include_router(demo_router)
router.include_router(artist_router)
router.include_router(artist_portal_router)
router.include_router(public_router)


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
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_host VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_port INTEGER"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_from_email VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_use_tls BOOLEAN"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_use_ssl BOOLEAN"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_user VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_password VARCHAR(255)"))
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
            # Incoming email ingestion: external mail surfaced in the label inbox.
            conn.execute(text("ALTER TABLE label_inbox_threads ALTER COLUMN artist_id DROP NOT NULL"))
            conn.execute(text("ALTER TABLE label_inbox_threads ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'portal' NOT NULL"))
            conn.execute(text("ALTER TABLE label_inbox_threads ADD COLUMN IF NOT EXISTS external_from VARCHAR(320)"))
            conn.execute(text("ALTER TABLE label_inbox_threads ADD COLUMN IF NOT EXISTS subject VARCHAR(500)"))
            conn.execute(text("ALTER TABLE label_inbox_messages ADD COLUMN IF NOT EXISTS external_message_id VARCHAR(255)"))
            conn.execute(text("ALTER TABLE label_inbox_messages ADD COLUMN IF NOT EXISTS external_from VARCHAR(320)"))
            conn.execute(text("ALTER TABLE label_inbox_messages ADD COLUMN IF NOT EXISTS external_subject VARCHAR(500)"))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_label_inbox_messages_external_message_id ON label_inbox_messages (external_message_id)"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS platform_links_json TEXT DEFAULT '{}'"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS cover_image_path VARCHAR(500)"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS cover_image_source_url VARCHAR(1000)"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS cover_image_updated_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS minisite_slug VARCHAR(160)"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS minisite_is_public BOOLEAN DEFAULT false NOT NULL"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS minisite_json TEXT DEFAULT '{}'"))
            conn.execute(text(
                "UPDATE mail_settings SET emails_per_hour = 10 WHERE id = 1 AND (emails_per_hour IS NULL OR emails_per_hour = 5)"
            ))
            conn.commit()
    except Exception as e:
        logging.getLogger(__name__).warning("DB migration (auth/users): %s", e)

    try:
        with Session(engine) as db:
            migrated_connections = migrate_legacy_social_connection_tokens(db)
        if migrated_connections:
            append_system_log(
                "info",
                "system",
                "Encrypted legacy social tokens",
                details=f"Migrated {migrated_connections} social connection rows to encrypted token storage.",
            )
    except Exception as e:
        logging.getLogger(__name__).warning("DB migration (social token encryption): %s", e)

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
    email = (payload.email or "").strip().lower()
    client_ip = _client_ip_from_request(request)
    allowed, retry_after = auth_rate_limit.check_login_allowed(email=email, client_ip=client_ip)
    if not allowed:
        _log_auth_attempt(request, event="Admin login rate limited", email=email, level="warning")
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Too many login attempts. Try again in about {retry_after or 1} seconds.",
        )
    user = (
        db.query(User)
        .options(joinedload(User.artist), joinedload(User.identities))
        .filter(func.lower(User.email) == email)
        .first()
    )
    if not user or not user.is_active or not verify_password(payload.password, user.password_hash):
        auth_rate_limit.register_failed_login(email=email, client_ip=client_ip)
        _log_auth_attempt(request, event="Admin login failed", email=email, level="warning")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    auth_rate_limit.clear_login_failures(email=email, client_ip=client_ip)
    _touch_user_login(db, user)
    _log_auth_attempt(request, event="Admin login succeeded", email=user.email)
    return _user_token_response(user)


@router.post("/public/artist-login", response_model=TokenResponse)
def artist_login(payload: ArtistLoginRequest, request: Request, db: Session = Depends(get_db)) -> TokenResponse:
    """
    Artist portal login (artists.zalmanim.com). Uses artists table email + password_hash only.
    No users table row is required. Admin must set the artist's password first (admin UI or API).
    """
    email = (payload.email or "").strip().lower()
    client_ip = _client_ip_from_request(request)
    allowed, retry_after = auth_rate_limit.check_login_allowed(email=email, client_ip=client_ip)
    if not allowed:
        _log_auth_attempt(request, event="Artist login rate limited", email=email, level="warning")
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Too many login attempts. Try again in about {retry_after or 1} seconds.",
        )
    artist = (
        db.query(Artist)
        .filter(func.lower(Artist.email) == email)
        .first()
    )
    if not artist:
        auth_rate_limit.register_failed_login(email=email, client_ip=client_ip)
        _log_auth_attempt(request, event="Artist login failed", email=email, level="warning")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")
    if not artist.is_active:
        _log_auth_attempt(request, event="Artist login blocked: inactive", email=email, level="warning")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Account is inactive")
    if not artist.password_hash:
        _log_auth_attempt(request, event="Artist login blocked: password not set", email=email, level="warning")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Password not set. Contact the label to get portal access.",
        )
    if not verify_password(payload.password, artist.password_hash):
        auth_rate_limit.register_failed_login(email=email, client_ip=client_ip)
        _log_auth_attempt(request, event="Artist login failed", email=email, level="warning")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")
    auth_rate_limit.clear_login_failures(email=email, client_ip=client_ip)
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
    if len(new_password) < 12:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 12 characters")
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
    safe_redirect = _sanitize_redirect_target(redirect_uri)
    state = _build_oauth_state(provider=provider, purpose="login", app_redirect=safe_redirect)
    return {"auth_url": _build_provider_auth_url(provider, request=request, state=state)}


@router.get("/admin/google-mail/start")
def start_google_mail_connect(
    request: Request,
    redirect_uri: str,
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    require_admin(user)
    safe_redirect = _sanitize_redirect_target(redirect_uri)
    state = _build_oauth_state(provider="google", purpose="connect_gmail", app_redirect=safe_redirect, user_id=user.user_id)
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
    app_redirect = _sanitize_redirect_target(
        state_payload.get("app_redirect") or settings.oauth_success_redirect or settings.admin_app_base_url or "/"
    )
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
    return _redirect_with_fragment_params(
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


def _login_stats_threshold(days: int = 30) -> datetime:
    return datetime.now(timezone.utc) - timedelta(days=days)


def _users_logged_in_since(db: Session, threshold: datetime) -> int:
    return (
        db.query(User)
        .filter(User.last_login_at.isnot(None), User.last_login_at >= threshold)
        .count()
    )


def _artist_activity_keys_since(db: Session, threshold: datetime) -> set[str]:
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

    return artist_keys


def _recent_user_logins(db: Session, limit: int = 10) -> list[LoginActivityOut]:
    out: list[LoginActivityOut] = []
    rows = (
        db.query(User)
        .filter(User.last_login_at.isnot(None))
        .order_by(User.last_login_at.desc())
        .limit(limit)
        .all()
    )
    for recent_user in rows:
        if recent_user.last_login_at is None:
            continue
        out.append(
            LoginActivityOut(
                source="user",
                name=(recent_user.full_name or recent_user.email).strip(),
                email=recent_user.email,
                role=recent_user.role,
                is_active=recent_user.is_active,
                last_login_at=recent_user.last_login_at,
            )
        )
    return out


def _recent_artist_portal_logins(db: Session, limit: int = 10) -> list[LoginActivityOut]:
    out: list[LoginActivityOut] = []
    rows = (
        db.query(Artist)
        .filter(Artist.last_login_at.isnot(None))
        .order_by(Artist.last_login_at.desc())
        .limit(limit)
        .all()
    )
    for recent_artist in rows:
        if recent_artist.last_login_at is None:
            continue
        out.append(
            LoginActivityOut(
                source="artist_portal",
                name=(recent_artist.name or recent_artist.email).strip(),
                email=recent_artist.email,
                role="artist",
                is_active=recent_artist.is_active,
                last_login_at=recent_artist.last_login_at,
            )
        )
    return out


def _combined_recent_logins(db: Session, limit: int = 10) -> list[LoginActivityOut]:
    recent_logins = _recent_user_logins(db, limit=limit) + _recent_artist_portal_logins(db, limit=limit)
    recent_logins.sort(key=lambda item: item.last_login_at, reverse=True)
    return recent_logins[:limit]


@router.get("/admin/dashboard/login-stats", response_model=LoginStatsOut)
def get_login_stats(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> LoginStatsOut:
    require_admin(user)
    threshold = _login_stats_threshold(days=30)
    users_logged_in_last_30_days = _users_logged_in_since(db, threshold)
    artist_keys = _artist_activity_keys_since(db, threshold)
    recent_logins = _combined_recent_logins(db, limit=10)

    return LoginStatsOut(
        users_logged_in_last_30_days=users_logged_in_last_30_days,
        artists_logged_in_last_30_days=len(artist_keys),
        recent_logins=recent_logins,
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
        body = file.file.read(MAX_RESTORE_BYTES + 1)
        if len(body) > MAX_RESTORE_BYTES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Restore file is too large. Maximum allowed size is {_format_byte_limit(MAX_RESTORE_BYTES)}.",
            )
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



