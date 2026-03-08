import json
from datetime import date, datetime

from pydantic import BaseModel, EmailStr


class LoginRequest(BaseModel):
    email: str  # plain str so seed emails like admin@label.local are accepted
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str


class UserContext(BaseModel):
    user_id: int
    role: str
    artist_id: int | None = None


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


def _artist_extra_from_model(m: BaseModel) -> dict:
    keys = (
        "artist_brand", "full_name", "website", "soundcloud", "facebook",
        "twitter_1", "twitter_2", "youtube", "tiktok", "instagram", "spotify",
        "other_1", "other_2", "other_3", "comments", "apple_music", "address", "source_row",
    )
    out = {k: getattr(m, k) for k in keys if getattr(m, k) is not None}
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

    class Config:
        from_attributes = True

    @classmethod
    def from_artist(
        cls,
        artist,
        *,
        last_release: dict | None = None,
        last_reminder_sent_at: datetime | None = None,
    ) -> "ArtistOut":
        """Build ArtistOut from ORM Artist (extra from extra_json). Optionally include last_release, last_reminder_sent_at."""
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
        )


class ReleaseOut(BaseModel):
    id: int
    artist_id: int | None  # Primary/first artist (backward compat)
    artist_ids: list[int] = []  # All artists linked to this release (one or more)
    title: str
    status: str
    file_path: str | None
    created_at: datetime

    class Config:
        from_attributes = True

    @classmethod
    def from_release(cls, release) -> "ReleaseOut":
        """Build ReleaseOut from ORM Release; artist_ids from release.artists or fallback to [artist_id]."""
        artist_ids = [a.id for a in release.artists] if getattr(release, "artists", None) else []
        if not artist_ids and getattr(release, "artist_id", None):
            artist_ids = [release.artist_id]
        return cls(
            id=release.id,
            artist_id=release.artist_id,
            artist_ids=artist_ids,
            title=release.title,
            status=release.status,
            file_path=release.file_path,
            created_at=release.created_at,
        )


class ReleaseUpdateArtists(BaseModel):
    """Set one or more artists for a release (e.g. when sync did not match)."""
    artist_ids: list[int]


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


class ArtistActivityLogOut(BaseModel):
    id: int
    activity_type: str
    details: str | None
    created_at: datetime


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


class ScheduleCampaignRequest(BaseModel):
    scheduled_at: datetime | None = None  # None = send now


class SystemSettingsOut(BaseModel):
    """Read-only view of server config for admin UI. Secrets are never returned."""
    # SMTP
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_from_email: str = ""
    smtp_use_tls: bool = True
    smtp_use_ssl: bool = False
    smtp_user_configured: bool = False  # True if smtp_user is set (password not exposed)
    emails_per_hour: int = 30
    email_configured: bool = False  # True if SMTP is usable
    # OAuth / redirects
    oauth_redirect_base: str = ""
    oauth_success_redirect: str = ""


class SystemSettingsMailUpdate(BaseModel):
    """Update mail server settings (all optional). Empty string clears DB override for that field."""
    smtp_host: str | None = None
    smtp_port: int | None = None
    smtp_from_email: str | None = None
    smtp_use_tls: bool | None = None
    smtp_use_ssl: bool | None = None
    smtp_user: str | None = None
    smtp_password: str | None = None
    emails_per_hour: int | None = None
