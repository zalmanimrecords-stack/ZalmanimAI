import json
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, EmailStr


class LoginRequest(BaseModel):
    email: str  # plain str so seed emails like admin@label.local are accepted
    password: str


class ArtistLoginRequest(BaseModel):
    """Artist portal login: email + password from artists table (not users)."""
    email: str
    password: str


class ArtistSetPasswordRequest(BaseModel):
    """Admin sets an artist's portal password."""
    password: str


class ArtistPortalInviteResponse(BaseModel):
    message: str
    portal_url: str
    username: str


class ArtistPortalInviteBulkError(BaseModel):
    artist_id: int
    email: str
    detail: str


class ArtistPortalInviteBulkResponse(BaseModel):
    sent: int
    failed: int
    errors: list[ArtistPortalInviteBulkError] = []


class ArtistChangePasswordRequest(BaseModel):
    """Artist changes own password (current + new)."""
    current_password: str
    new_password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str
    email: str
    full_name: str | None = None
    permissions: list[str] = []


class ForgotPasswordRequest(BaseModel):
    email: str


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str


class UserContext(BaseModel):
    user_id: int
    role: str
    email: str
    full_name: str | None = None
    permissions: list[str] = []
    artist_id: int | None = None
    is_active: bool = True


class UserIdentityOut(BaseModel):
    id: int
    provider: str
    provider_subject: str
    email: str | None
    display_name: str | None
    created_at: datetime
    last_login_at: datetime | None

    class Config:
        from_attributes = True


class UserOut(BaseModel):
    id: int
    email: str
    full_name: str | None = None
    role: str
    permissions: list[str] = []
    artist_id: int | None = None
    artist_name: str | None = None
    is_active: bool = True
    created_at: datetime | None = None
    updated_at: datetime | None = None
    last_login_at: datetime | None = None
    identities: list[UserIdentityOut] = []


class UserCreate(BaseModel):
    email: EmailStr
    full_name: str | None = None
    password: str | None = None
    role: str
    artist_id: int | None = None
    is_active: bool = True


class UserUpdate(BaseModel):
    email: EmailStr | None = None
    full_name: str | None = None
    password: str | None = None
    role: str | None = None
    artist_id: int | None = None
    is_active: bool | None = None

# Artist fields match reports/artists_from_release_management_raw.csv
class ArtistCreate(BaseModel):
    name: str  # display name (artist_brand or full_name)
    email: EmailStr
    notes: str = ""
    is_active: bool = True
    # Optional CSV-style fields; stored in extra_json
    artist_brand: str | None = None
    artist_brands: list[str] | None = None  # Multiple brands (e.g. merged artists); used for matching
    full_name: str | None = None
    website: str | None = None
    soundcloud: str | None = None
    facebook: str | None = None
    twitter_1: str | None = None
    twitter_2: str | None = None
    youtube: str | None = None
    tiktok: str | None = None
    instagram: str | None = None
    spotify: str | None = None
    other_1: str | None = None
    other_2: str | None = None
    other_3: str | None = None
    comments: str | None = None
    apple_music: str | None = None
    address: str | None = None
    source_row: str | None = None
    linktree: str | None = None  # Linktree or single-link page URL


class ArtistUpdate(BaseModel):
    name: str | None = None
    email: EmailStr | None = None
    notes: str | None = None
    is_active: bool | None = None
    artist_brand: str | None = None
    artist_brands: list[str] | None = None
    full_name: str | None = None
    website: str | None = None
    soundcloud: str | None = None
    facebook: str | None = None
    twitter_1: str | None = None
    twitter_2: str | None = None
    youtube: str | None = None
    tiktok: str | None = None
    instagram: str | None = None
    spotify: str | None = None
    other_1: str | None = None
    other_2: str | None = None
    other_3: str | None = None
    comments: str | None = None
    apple_music: str | None = None
    address: str | None = None
    source_row: str | None = None
    linktree: str | None = None


class ArtistSelfUpdate(BaseModel):
    """Fields an artist can update for their own profile (no email, no is_active)."""
    name: str | None = None
    notes: str | None = None
    artist_brand: str | None = None
    artist_brands: list[str] | None = None
    full_name: str | None = None
    website: str | None = None
    soundcloud: str | None = None
    facebook: str | None = None
    twitter_1: str | None = None
    twitter_2: str | None = None
    youtube: str | None = None
    tiktok: str | None = None
    instagram: str | None = None
    spotify: str | None = None
    other_1: str | None = None
    other_2: str | None = None
    other_3: str | None = None
    comments: str | None = None
    apple_music: str | None = None
    address: str | None = None
    source_row: str | None = None
    linktree: str | None = None
    profile_image_media_id: int | None = None  # Artist media ID for Linktree profile image
    logo_media_id: int | None = None  # Artist media ID for Linktree logo


class ArtistMediaOut(BaseModel):
    id: int
    artist_id: int
    filename: str
    content_type: str | None
    size_bytes: int
    created_at: datetime

    class Config:
        from_attributes = True


class ArtistMediaListResponse(BaseModel):
    """List of artist media with quota (50MB per artist)."""
    items: list[ArtistMediaOut]
    used_bytes: int
    quota_bytes: int = 52_428_800  # 50 MiB


class LinktreeLink(BaseModel):
    label: str
    url: str


class LinktreeRelease(BaseModel):
    """One release for public linktree page."""
    title: str
    url: str | None = None  # Optional link to stream/buy


class LinktreeOut(BaseModel):
    """Public linktree page data for an artist."""
    artist_id: int
    name: str
    links: list[LinktreeLink]
    profile_image_url: str | None = None  # Public URL to profile image (if set)
    logo_url: str | None = None  # Public URL to logo image (if set)
    releases: list[LinktreeRelease] = []  # Artist's releases (title, optional url)


class ArtistDemoSubmitRequest(BaseModel):
    """Artist portal: submit a demo (message; file is uploaded via multipart)."""
    message: str | None = None


def _artist_extra_from_model(m: BaseModel) -> dict:
    # ORM Artist: extra fields live in extra_json, not as attributes (no artist.artist_brand)
    if hasattr(m, "extra_json") and m.extra_json is not None:
        try:
            raw = m.extra_json
            data = json.loads(raw) if isinstance(raw, str) else dict(raw)
            if isinstance(data, dict):
                out = {k: v for k, v in data.items() if v is not None}
                brands = out.get("artist_brands")
                if brands is not None and isinstance(brands, list):
                    out["artist_brands"] = [b for b in brands if isinstance(b, str) and b.strip()]
                return out
        except (json.JSONDecodeError, TypeError):
            pass
    keys = (
        "artist_brand", "full_name", "website", "soundcloud", "facebook",
        "twitter_1", "twitter_2", "youtube", "tiktok", "instagram", "spotify",
        "other_1", "other_2", "other_3", "comments", "apple_music", "address", "source_row",
        "linktree", "profile_image_media_id", "logo_media_id",
    )
    out = {
        k: getattr(m, k)
        for k in keys
        if hasattr(m, k) and getattr(m, k) is not None
    }
    brands = getattr(m, "artist_brands", None)
    if brands is not None and isinstance(brands, list):
        out["artist_brands"] = [b for b in brands if isinstance(b, str) and b.strip()]
    return out


class ArtistOut(BaseModel):
    id: int
    name: str
    email: str  # str so seed emails like artist@label.local serialize
    notes: str
    is_active: bool = True
    extra: dict = {}  # CSV-style fields (artist_brand, full_name, website, ...)
    last_release: dict | None = None  # {"title": str, "created_at": str} for list display
    last_reminder_sent_at: datetime | None = None  # When last reminder email was sent (reports)
    last_email_sent_at: datetime | None = None  # When last system email was sent (portal invite, update profile, reminder)
    last_login_at: datetime | None = None
    last_profile_updated_at: datetime | None = None  # When artist last updated their portal profile

    class Config:
        from_attributes = True

    @classmethod
    def from_artist(
        cls,
        artist,
        *,
        last_release: dict | None = None,
        last_reminder_sent_at: datetime | None = None,
        last_email_sent_at: datetime | None = None,
    ) -> "ArtistOut":
        """Build ArtistOut from ORM Artist (extra from extra_json). Optionally include last_release, last_reminder_sent_at, last_email_sent_at."""
        extra = {}
        if getattr(artist, "extra_json", None):
            try:
                extra = json.loads(artist.extra_json) or {}
            except (json.JSONDecodeError, TypeError):
                pass
        return cls(
            id=artist.id,
            name=artist.name,
            email=artist.email,
            notes=artist.notes or "",
            is_active=getattr(artist, "is_active", True),
            extra=extra,
            last_release=last_release,
            last_reminder_sent_at=last_reminder_sent_at,
            last_email_sent_at=last_email_sent_at,
            last_login_at=getattr(artist, "last_login_at", None),
            last_profile_updated_at=getattr(artist, "last_profile_updated_at", None),
        )


class LoginActivityOut(BaseModel):
    source: str  # user | artist_portal
    name: str
    email: str
    role: str
    is_active: bool
    last_login_at: datetime


class LoginStatsOut(BaseModel):
    users_logged_in_last_30_days: int
    artists_logged_in_last_30_days: int
    recent_logins: list[LoginActivityOut] = []


class AdminDashboardStatsOut(BaseModel):
    """Counts for the admin dashboard header: active artists and total releases."""
    artists_count: int
    releases_count: int


class ReleaseOut(BaseModel):
    id: int
    artist_id: int | None  # Primary/first artist (backward compat)
    artist_ids: list[int] = []  # All artists linked to this release (one or more)
    artist_names: list[str] = []  # Display names for linked artists
    title: str
    status: str
    file_path: str | None
    cover_image_url: str | None = None
    cover_image_source_url: str | None = None
    minisite_slug: str | None = None
    minisite_is_public: bool = False
    minisite_theme: str | None = None
    minisite_preview_url: str | None = None
    minisite_public_url: str | None = None
    minisite: dict = {}
    platform_links: dict[str, str] = {}
    pending_link_candidates_count: int = 0
    last_link_scan_at: datetime | None = None
    created_at: datetime

    class Config:
        from_attributes = True

    @classmethod
    def from_release(cls, release) -> "ReleaseOut":
        """Build ReleaseOut from ORM Release; artist_ids from release.artists or fallback to [artist_id]."""
        artist_ids = [a.id for a in release.artists] if getattr(release, "artists", None) else []
        artist_names = [a.name for a in release.artists] if getattr(release, "artists", None) else []
        if not artist_ids and getattr(release, "artist_id", None):
            artist_ids = [release.artist_id]
        if not artist_names and getattr(release, "artist", None):
            artist_names = [release.artist.name]
        platform_links: dict[str, str] = {}
        minisite_data: dict[str, object] = {}
        raw_links = getattr(release, "platform_links_json", None)
        if raw_links:
            try:
                data = json.loads(raw_links) or {}
                if isinstance(data, dict):
                    platform_links = {
                        str(key): str(value).strip()
                        for key, value in data.items()
                        if str(key).strip() and str(value).strip()
                    }
            except (json.JSONDecodeError, TypeError):
                platform_links = {}
        raw_minisite = getattr(release, "minisite_json", None)
        if raw_minisite:
            try:
                data = json.loads(raw_minisite) or {}
                if isinstance(data, dict):
                    minisite_data = data
            except (json.JSONDecodeError, TypeError):
                minisite_data = {}
        pending_count = 0
        for candidate in getattr(release, "link_candidates", []) or []:
            if getattr(candidate, "status", "") == "pending_review":
                pending_count += 1
        last_scan_at = None
        for run in getattr(release, "link_scan_runs", []) or []:
            completed_at = getattr(run, "completed_at", None)
            created_at = getattr(run, "created_at", None)
            candidate_time = completed_at or created_at
            if candidate_time is not None and (last_scan_at is None or candidate_time > last_scan_at):
                last_scan_at = candidate_time
        return cls(
            id=release.id,
            artist_id=release.artist_id,
            artist_ids=artist_ids,
            artist_names=artist_names,
            title=release.title,
            status=release.status,
            file_path=release.file_path,
            cover_image_url=f"/api/public/releases/{release.id}/cover-image" if getattr(release, "cover_image_path", None) else None,
            cover_image_source_url=getattr(release, "cover_image_source_url", None),
            minisite_slug=getattr(release, "minisite_slug", None),
            minisite_is_public=bool(getattr(release, "minisite_is_public", False)),
            minisite_theme=str(minisite_data.get("theme") or "").strip() or None,
            minisite_preview_url=(
                f"/api/public/release-sites/{release.minisite_slug}?preview_token={str(minisite_data.get('preview_token') or '').strip()}"
                if getattr(release, "minisite_slug", None) and str(minisite_data.get("preview_token") or "").strip()
                else None
            ),
            minisite_public_url=(
                f"/api/public/release-sites/{release.minisite_slug}"
                if getattr(release, "minisite_slug", None) and bool(getattr(release, "minisite_is_public", False))
                else None
            ),
            minisite={
                "theme": str(minisite_data.get("theme") or "").strip(),
                "description": str(minisite_data.get("description") or "").strip(),
                "download_url": str(minisite_data.get("download_url") or "").strip(),
                "gallery_urls": minisite_data.get("gallery_urls") if isinstance(minisite_data.get("gallery_urls"), list) else [],
            },
            platform_links=platform_links,
            pending_link_candidates_count=pending_count,
            last_link_scan_at=last_scan_at,
            created_at=release.created_at,
        )


class ReleaseUpdateArtists(BaseModel):
    """Set one or more artists for a release (e.g. when sync did not match)."""
    artist_ids: list[int]


class ReleaseLinkCandidateOut(BaseModel):
    id: int
    release_id: int
    platform: str
    url: str
    match_title: str | None = None
    match_artist: str | None = None
    confidence: float
    status: str
    source_type: str
    raw_payload: dict = {}
    discovered_at: datetime
    reviewed_at: datetime | None = None

    class Config:
        from_attributes = True

    @classmethod
    def from_candidate(cls, candidate) -> "ReleaseLinkCandidateOut":
        raw_payload = {}
        try:
            data = json.loads(getattr(candidate, "raw_payload_json", "{}") or "{}") or {}
            if isinstance(data, dict):
                raw_payload = data
        except (json.JSONDecodeError, TypeError):
            raw_payload = {}
        return cls(
            id=candidate.id,
            release_id=candidate.release_id,
            platform=candidate.platform,
            url=candidate.url,
            match_title=candidate.match_title,
            match_artist=candidate.match_artist,
            confidence=float(candidate.confidence or 0.0),
            status=candidate.status,
            source_type=candidate.source_type,
            raw_payload=raw_payload,
            discovered_at=candidate.discovered_at,
            reviewed_at=candidate.reviewed_at,
        )


class ReleaseLinkScanRequest(BaseModel):
    release_ids: list[int]
    platforms: list[str] | None = None


class ReleaseLinkScanResponse(BaseModel):
    queued_runs: int
    release_ids: list[int]
    message: str


class ReleaseLinkCandidateReviewResponse(BaseModel):
    release: ReleaseOut
    candidate: ReleaseLinkCandidateOut


class ReleaseMinisiteUpdateRequest(BaseModel):
    theme: str | None = None
    is_public: bool | None = None
    description: str | None = None
    download_url: str | None = None
    gallery_urls: list[str] | None = None


class ReleaseMinisiteSendRequest(BaseModel):
    message: str | None = None


# Catalog metadata (Proton CSV export schema) - one row per track
class CatalogTrackOut(BaseModel):
    id: int
    catalog_number: str
    release_title: str
    pre_order_date: date | None
    release_date: date | None
    upc: str | None
    isrc: str | None
    original_artists: str | None
    original_first_last: str | None
    remix_artists: str | None
    remix_first_last: str | None
    track_title: str | None
    mix_title: str | None
    duration: str | None
    created_at: datetime

    class Config:
        from_attributes = True


class TaskOut(BaseModel):
    id: int
    artist_id: int
    title: str
    status: str
    details: str
    created_at: datetime

    class Config:
        from_attributes = True


class ArtistDashboard(BaseModel):
    artist: ArtistOut
    releases: list[ReleaseOut]
    tasks: list[TaskOut]
    pending_releases: list["PendingReleaseDetailOut"] = []


class SocialProviderOut(BaseModel):
    key: str
    title: str
    scopes: list[str]
    auth_url: str
    configured: bool


class SocialConnectStartRequest(BaseModel):
    provider: str
    account_label: str
    artist_id: int | None = None
    browser_flow: bool = True  # Use browser-only OAuth (no server API call to provider)


class SocialConnectStartResponse(BaseModel):
    connection_id: int
    provider: str
    auth_url: str
    state: str
    one_time_token: str | None = None  # For browser flow: open connect_page_url with ?token=
    connect_page_url: str | None = None  # For browser flow: open this URL in browser first


class SocialProviderConfigOut(BaseModel):
    """Public config for browser-side token exchange (no client_secret)."""
    token_url: str
    client_id: str
    redirect_uri: str


class SocialConnectCompleteRequest(BaseModel):
    state: str
    access_token: str
    refresh_token: str | None = None
    token_type: str | None = None
    expires_in: int | None = None


class SocialConnectionOut(BaseModel):
    id: int
    provider: str
    account_label: str
    artist_id: int | None
    status: str
    scopes: list[str]
    authorized_at: datetime | None
    created_at: datetime

    class Config:
        from_attributes = True


class SocialCallbackResponse(BaseModel):
    connection_id: int
    status: str


class PublishPostRequest(BaseModel):
    connection_id: int
    text: str


class PublishPostResponse(BaseModel):
    task_id: int
    connection_id: int
    status: str


# Advanced connectors hub (Mailchimp, WordPress Codex, etc.)
class HubConnectorTypeOut(BaseModel):
    key: str
    title: str
    description: str
    config_fields: list[dict]  # e.g. [{"name": "api_key", "label": "API Key", "type": "password"}]


class HubConnectorOut(BaseModel):
    id: int
    connector_type: str
    account_label: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


class HubConnectorCreate(BaseModel):
    connector_type: str
    account_label: str
    config: dict  # type-specific: mailchimp {api_key}, wordpress_codex {rest_base_url, client_key, client_secret}


class HubConnectorDetailOut(BaseModel):
    id: int
    connector_type: str
    account_label: str
    status: str
    created_at: datetime
    config: dict


class HubConnectorUpdate(BaseModel):
    account_label: str | None = None
    config: dict | None = None
    status: str | None = None


# Email sending (admin) with rate limit
class SendEmailRequest(BaseModel):
    to_email: EmailStr
    subject: str
    body_text: str
    body_html: str | None = None
    artist_id: int | None = None  # When set and send succeeds, log reminder_email for this artist


class SendEmailResponse(BaseModel):
    success: bool
    message: str


class EmailRateLimitStatus(BaseModel):
    configured: bool
    emails_per_hour: int
    sent_this_hour: int
    remaining_this_hour: int | None  # None when emails_per_hour is 0 (no limit)


class EmailRecipientHistoryOut(BaseModel):
    email: str
    has_sent_before: bool
    send_count: int = 0
    last_sent_at: datetime | None = None
    last_subject: str | None = None


class ArtistActivityLogOut(BaseModel):
    id: int
    activity_type: str
    details: str | None
    created_at: datetime


class SystemLogOut(BaseModel):
    id: int
    level: str
    category: str
    message: str
    details: str | None
    created_at: datetime

    class Config:
        from_attributes = True


class DemoSubmissionCreate(BaseModel):
    artist_name: str
    email: EmailStr
    consent_to_emails: bool = False
    contact_name: str | None = None
    phone: str | None = None
    genre: str | None = None
    city: str | None = None
    message: str | None = None
    links: list[str] = []
    fields: dict = {}
    source: str = "wordpress_demo_form"
    source_site_url: str | None = None


class DemoSubmissionUpdate(BaseModel):
    artist_name: str | None = None
    email: EmailStr | None = None
    consent_to_emails: bool | None = None
    contact_name: str | None = None
    phone: str | None = None
    genre: str | None = None
    city: str | None = None
    message: str | None = None
    links: list[str] | None = None
    fields: dict | None = None
    status: str | None = None
    admin_notes: str | None = None
    approval_subject: str | None = None
    approval_body: str | None = None
    rejection_subject: str | None = None
    rejection_body: str | None = None
    send_rejection_email: bool | None = None
    artist_id: int | None = None


class DemoSubmissionApproveRequest(BaseModel):
    approval_subject: str | None = None
    approval_body: str | None = None
    create_artist: bool = True  # Ignored: an Artist is always created or linked by email on approve.
    send_email: bool = True


class DemoSubmissionOut(BaseModel):
    id: int
    artist_name: str
    email: str
    consent_to_emails: bool
    consent_at: datetime | None
    contact_name: str | None
    phone: str | None
    genre: str | None
    city: str | None
    message: str | None
    links: list[str] = []
    fields: dict = {}
    has_demo_file: bool = False
    source: str
    source_site_url: str | None
    status: str
    admin_notes: str | None
    approval_subject: str | None
    approval_body: str | None
    rejection_subject: str | None
    rejection_body: str | None
    approval_email_sent_at: datetime | None
    rejection_email_sent_at: datetime | None
    artist_id: int | None
    created_at: datetime
    updated_at: datetime | None


# Artist campaign requests (artist asks label for a release campaign)
class CampaignRequestCreate(BaseModel):
    """Artist portal: request a campaign for a release."""
    release_id: int | None = None
    message: str | None = None


class CampaignRequestUpdate(BaseModel):
    """Admin: update status/notes of a campaign request."""
    status: str | None = None  # approved | rejected
    admin_notes: str | None = None


class CampaignRequestOut(BaseModel):
    id: int
    artist_id: int
    artist_name: str = ""
    release_id: int | None
    release_title: str | None = None
    message: str | None
    status: str
    admin_notes: str | None
    created_at: datetime
    updated_at: datetime | None

    class Config:
        from_attributes = True


# Pending for release (artist filled form after track approved)
class PendingReleaseFormInfo(BaseModel):
    """Public: info returned when validating a pending-release form token."""
    artist_name: str
    artist_email: str = ""
    artist_data: dict = {}
    release_title: str
    release_data: dict = {}
    expires_at: datetime | None = None


# Demo confirmation (artist confirms/complete details after demo approved)
class DemoConfirmFormInfo(BaseModel):
    """Public: prefilled form data when artist opens demo confirmation link."""
    artist_name: str
    contact_name: str | None = None
    email: str
    phone: str | None = None
    genre: str | None = None
    city: str | None = None
    message: str | None = None
    links: list[str] = []
    release_title: str = "Your release"


class DemoConfirmSubmit(BaseModel):
    """Public: submit confirmed details; creates PendingRelease and sets demo status to pending_release."""
    token: str
    artist_name: str
    artist_email: EmailStr
    artist_data: dict = {}
    release_title: str
    release_data: dict = {}


class PendingReleaseSubmit(BaseModel):
    """Public: submit artist + track details after track approval."""
    token: str
    artist_name: str
    artist_email: EmailStr
    artist_data: dict = {}  # Same keys as Artist extra (artist_brand, full_name, website, ...)
    release_title: str
    release_data: dict = {}  # catalog_number, release_date, track_title, etc.


class PendingReleaseOut(BaseModel):
    """Admin: one row in Pending for release tab."""
    id: int
    campaign_request_id: int | None
    demo_submission_id: int | None = None
    artist_id: int | None
    artist_name: str
    artist_email: str
    artist_data: dict = {}
    release_title: str
    release_data: dict = {}
    status: str
    created_at: datetime
    updated_at: datetime | None
    last_reminder_sent_at: datetime | None = None


class PendingReleaseImageOptionOut(BaseModel):
    id: str
    url: str
    filename: str | None = None
    created_at: datetime | None = None


class PendingReleaseCommentOut(BaseModel):
    id: int
    sender: str
    body: str
    created_at: datetime

    class Config:
        from_attributes = True


class PendingReleaseDetailOut(PendingReleaseOut):
    image_options: list[PendingReleaseImageOptionOut] = []
    selected_image_id: str | None = None
    notifications_muted: bool = False
    comments: list[PendingReleaseCommentOut] = []


class PendingReleaseCommentCreate(BaseModel):
    body: str


class PendingReleaseSelectImageRequest(BaseModel):
    image_id: str


class PendingReleaseNotificationSettingsUpdate(BaseModel):
    notifications_muted: bool


class PendingReleaseActionResponse(BaseModel):
    success: bool
    message: str


class PendingReleaseReminderResponse(BaseModel):
    success: bool
    message: str
    expires_at: datetime


class PendingReleaseReferenceUploadOut(BaseModel):
    url: str
    filename: str


class PendingReleaseRemoveStoredImageBody(BaseModel):
    """Remove a label-uploaded option or artist reference image stored on this server (by public URL)."""

    url: str


# Label inbox (artist messages to label; admin replies by email)
class LabelInboxSend(BaseModel):
    """Artist: send a message to the label."""
    body: str


class LabelInboxMessageOut(BaseModel):
    id: int
    sender: str  # 'artist' | 'label'
    body: str
    created_at: datetime
    admin_read_at: datetime | None = None
    reply_email_sent_at: datetime | None = None


class LabelInboxThreadOut(BaseModel):
    """List item for inbox threads."""
    id: int
    artist_id: int
    artist_name: str
    artist_email: str
    last_message_preview: str
    last_message_at: datetime
    created_at: datetime
    updated_at: datetime | None
    message_count: int
    has_label_reply: bool
    unread_count: int = 0


class LabelInboxThreadDetailOut(BaseModel):
    """Thread with full messages (for thread view)."""
    id: int
    artist_id: int
    artist_name: str
    artist_email: str
    created_at: datetime
    updated_at: datetime | None
    message_count: int
    has_label_reply: bool
    unread_count: int = 0
    messages: list[LabelInboxMessageOut]


class LabelInboxReply(BaseModel):
    """Admin: reply to a thread (sends email to artist)."""
    body: str


# Campaigns (unified: social + Mailchimp + WordPress)
class CampaignTargetIn(BaseModel):
    channel_type: str  # social | mailchimp | wordpress
    external_id: str  # connection or connector id
    channel_payload: dict = {}  # list_id for mailchimp, post_type/status for wordpress


class CampaignCreate(BaseModel):
    name: str
    title: str
    body_text: str = ""
    body_html: str | None = None
    media_url: str | None = None
    artist_id: int | None = None
    targets: list[CampaignTargetIn] = []


class CampaignUpdate(BaseModel):
    name: str | None = None
    title: str | None = None
    body_text: str | None = None
    body_html: str | None = None
    media_url: str | None = None
    artist_id: int | None = None
    targets: list[CampaignTargetIn] | None = None


class CampaignTargetOut(BaseModel):
    id: int
    campaign_id: int
    channel_type: str
    external_id: str
    channel_payload: dict = {}

    class Config:
        from_attributes = True

    @classmethod
    def from_target(cls, target) -> "CampaignTargetOut":
        payload = {}
        if getattr(target, "channel_payload", None):
            try:
                payload = json.loads(target.channel_payload) if isinstance(target.channel_payload, str) else (target.channel_payload or {})
            except (json.JSONDecodeError, TypeError):
                pass
        return cls(
            id=target.id,
            campaign_id=target.campaign_id,
            channel_type=target.channel_type,
            external_id=target.external_id,
            channel_payload=payload,
        )


class CampaignDeliveryOut(BaseModel):
    id: int
    campaign_id: int
    target_id: int
    channel_type: str
    status: str
    external_id: str | None
    error_message: str | None
    created_at: datetime

    class Config:
        from_attributes = True


class CampaignOut(BaseModel):
    id: int
    artist_id: int | None
    name: str
    title: str
    body_text: str
    body_html: str | None
    media_url: str | None
    status: str
    scheduled_at: datetime | None
    sent_at: datetime | None
    created_at: datetime
    updated_at: datetime
    targets: list[CampaignTargetOut] = []
    deliveries: list[CampaignDeliveryOut] = []

    class Config:
        from_attributes = True

    @classmethod
    def from_campaign(cls, campaign) -> "CampaignOut":
        targets = [CampaignTargetOut.from_target(t) for t in getattr(campaign, "targets", [])]
        deliveries = [CampaignDeliveryOut.model_validate(d) for d in getattr(campaign, "deliveries", [])]
        return cls(
            id=campaign.id,
            artist_id=campaign.artist_id,
            name=campaign.name,
            title=campaign.title,
            body_text=campaign.body_text or "",
            body_html=campaign.body_html,
            media_url=campaign.media_url,
            status=campaign.status,
            scheduled_at=campaign.scheduled_at,
            sent_at=campaign.sent_at,
            created_at=campaign.created_at,
            updated_at=campaign.updated_at,
            targets=targets,
            deliveries=deliveries,
        )



class MailingListCreate(BaseModel):
    name: str
    description: str = ""
    from_name: str | None = None
    reply_to_email: EmailStr | None = None
    company_name: str | None = None
    physical_address: str | None = None
    default_language: str = "en"


class MailingListUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    from_name: str | None = None
    reply_to_email: EmailStr | None = None
    company_name: str | None = None
    physical_address: str | None = None
    default_language: str | None = None


class MailingListOut(BaseModel):
    id: int
    name: str
    description: str
    from_name: str | None
    reply_to_email: str | None
    company_name: str | None
    physical_address: str | None
    default_language: str
    subscribed_count: int = 0
    unsubscribed_count: int = 0
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class MailingSubscriberCreate(BaseModel):
    email: EmailStr
    full_name: str | None = None
    status: str = "subscribed"
    consent_source: str | None = None
    consent_at: datetime | None = None
    notes: str | None = None


class MailingSubscriberUpdate(BaseModel):
    email: EmailStr | None = None
    full_name: str | None = None
    status: str | None = None
    consent_source: str | None = None
    consent_at: datetime | None = None
    notes: str | None = None


class MailingSubscriberOut(BaseModel):
    id: int
    list_id: int
    email: str
    full_name: str | None
    status: str
    consent_source: str | None
    consent_at: datetime | None
    unsubscribed_at: datetime | None
    notes: str | None
    unsubscribe_url: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

class ScheduleCampaignRequest(BaseModel):
    scheduled_at: datetime | None = None  # None = send now


class SystemSettingsOut(BaseModel):
    """Read-only view of server config for admin UI. Secrets are never returned."""
    # SMTP
    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587
    smtp_from_email: str = ""
    smtp_use_tls: bool = True
    smtp_use_ssl: bool = False
    smtp_user_configured: bool = False  # True if smtp_user is set (password not exposed)
    smtp_backup_host: str = ""
    smtp_backup_port: int = 587
    smtp_backup_from_email: str = ""
    smtp_backup_use_tls: bool = True
    smtp_backup_use_ssl: bool = False
    smtp_backup_user_configured: bool = False
    emails_per_hour: int = 10
    email_configured: bool = False  # True if SMTP is usable
    email_footer: str = ""
    # Demo rejection email template (editable in settings)
    demo_rejection_subject: str = ""
    demo_rejection_body: str = ""
    demo_approval_subject: str = ""
    demo_approval_body: str = ""
    demo_receipt_subject: str = ""
    demo_receipt_body: str = ""
    portal_invite_subject: str = ""
    portal_invite_body: str = ""
    groover_invite_subject: str = ""
    groover_invite_body: str = ""
    update_profile_invite_subject: str = ""
    update_profile_invite_body: str = ""
    password_reset_subject: str = ""
    password_reset_body: str = ""
    # OAuth / redirects
    oauth_redirect_base: str = ""
    oauth_success_redirect: str = ""
    google_oauth_configured: bool = False
    gmail_connected: bool = False
    gmail_connected_email: str = ""
    artist_portal_base_url: str = ""  # Base URL for artist portal (e.g. for pending-release form link)


class SystemSettingsMailTestRequest(BaseModel):
    """Test SMTP connectivity or send a test email with optional unsaved overrides."""
    smtp_test_target: Literal["primary", "backup"] = "primary"
    smtp_host: str | None = None
    smtp_port: int | None = None
    smtp_from_email: str | None = None
    smtp_use_tls: bool | None = None
    smtp_use_ssl: bool | None = None
    smtp_user: str | None = None
    smtp_password: str | None = None
    smtp_backup_host: str | None = None
    smtp_backup_port: int | None = None
    smtp_backup_from_email: str | None = None
    smtp_backup_use_tls: bool | None = None
    smtp_backup_use_ssl: bool | None = None
    smtp_backup_user: str | None = None
    smtp_backup_password: str | None = None
    emails_per_hour: int | None = None
    test_email: EmailStr | None = None


class SystemSettingsMailTestResponse(BaseModel):
    success: bool
    message: str


class SystemSettingsMailUpdate(BaseModel):
    """Update mail server settings (all optional). Empty string clears DB override for that field."""
    smtp_host: str | None = None
    smtp_port: int | None = None
    smtp_from_email: str | None = None
    smtp_use_tls: bool | None = None
    smtp_use_ssl: bool | None = None
    smtp_user: str | None = None
    smtp_password: str | None = None
    smtp_backup_host: str | None = None
    smtp_backup_port: int | None = None
    smtp_backup_from_email: str | None = None
    smtp_backup_use_tls: bool | None = None
    smtp_backup_use_ssl: bool | None = None
    smtp_backup_user: str | None = None
    smtp_backup_password: str | None = None
    emails_per_hour: int | None = None
    email_footer: str | None = None
    demo_rejection_subject: str | None = None
    demo_rejection_body: str | None = None
    demo_approval_subject: str | None = None
    demo_approval_body: str | None = None
    demo_receipt_subject: str | None = None
    demo_receipt_body: str | None = None
    portal_invite_subject: str | None = None
    portal_invite_body: str | None = None
    groover_invite_subject: str | None = None
    groover_invite_body: str | None = None
    update_profile_invite_subject: str | None = None
    update_profile_invite_body: str | None = None
    password_reset_subject: str | None = None
    password_reset_body: str | None = None


class GrooverInviteRequest(BaseModel):
    email: EmailStr
    artist_name: str | None = None
    full_name: str | None = None
    notes: str | None = None


class GrooverInviteResponse(BaseModel):
    message: str
    artist_id: int
    email: EmailStr
    registration_url: str
    created_artist: bool = False


class ArtistRegistrationFormInfo(BaseModel):
    artist_id: int
    email: EmailStr
    artist_name: str = ""
    full_name: str = ""
    notes: str = ""
    expires_at: datetime


class ArtistRegistrationCompleteRequest(BaseModel):
    token: str
    artist_name: str
    full_name: str | None = None
    website: str | None = None
    soundcloud: str | None = None
    instagram: str | None = None
    spotify: str | None = None
    apple_music: str | None = None
    youtube: str | None = None
    tiktok: str | None = None
    facebook: str | None = None
    linktree: str | None = None
    notes: str | None = None
    password: str


class ArtistRegistrationCompleteResponse(BaseModel):
    message: str
    portal_url: str






class AgentPlanRequest(BaseModel):
    text: str
    max_agents: int = 4


class AgentDefinitionOut(BaseModel):
    key: str
    title: str
    role: str
    description: str
    capabilities: list[str] = []
    handoff_triggers: list[str] = []


class AgentSupervisorOut(BaseModel):
    key: str
    title: str
    role: str
    description: str


class AgentDelegationOut(BaseModel):
    work_item: str
    agent_key: str
    agent_title: str
    reason: str
    confidence: float


class AgentPlanOut(BaseModel):
    supervisor: AgentSupervisorOut
    summary: str
    primary_agent_key: str
    primary_agent_title: str
    delegations: list[AgentDelegationOut] = []
    agents: list[AgentDefinitionOut] = []

