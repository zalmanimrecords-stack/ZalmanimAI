from datetime import date

from sqlalchemy import Boolean, Column, Date, DateTime, ForeignKey, Integer, String, Table, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base


class MailSettings(Base):
    """Single-row table: editable mail server config (overrides env when set). id=1."""
    __tablename__ = "mail_settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)
    smtp_host: Mapped[str | None] = mapped_column(String(255), nullable=True)
    smtp_port: Mapped[int | None] = mapped_column(Integer, nullable=True)
    smtp_from_email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    smtp_use_tls: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    smtp_use_ssl: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    smtp_user: Mapped[str | None] = mapped_column(String(255), nullable=True)
    smtp_password: Mapped[str | None] = mapped_column(String(255), nullable=True)
    emails_per_hour: Mapped[int | None] = mapped_column(Integer, nullable=True)
    demo_rejection_subject: Mapped[str | None] = mapped_column(String(255), nullable=True)
    demo_rejection_body: Mapped[str | None] = mapped_column(Text, nullable=True)
    demo_approval_subject: Mapped[str | None] = mapped_column(String(255), nullable=True)
    demo_approval_body: Mapped[str | None] = mapped_column(Text, nullable=True)
    updated_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), onupdate=func.now())

# Many-to-many: a release can have multiple artists (e.g. when sync failed and admin assigns, or collab)
release_artists_table = Table(
    "release_artists",
    Base.metadata,
    Column("release_id", ForeignKey("releases.id", ondelete="CASCADE"), primary_key=True),
    Column("artist_id", ForeignKey("artists.id", ondelete="CASCADE"), primary_key=True),
)


class Artist(Base):
    """Artist fields align with reports/artists_from_release_management_raw.csv.
    Artists can log in at the artist portal (artists.zalmanim.com) using email + password_hash
    stored here; no users table row is required."""
    __tablename__ = "artists"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)  # display: artist_brand or full_name
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    notes: Mapped[str] = mapped_column(Text, default="")
    # Portal login: bcrypt hash. Null = password not set (artist cannot use portal until admin sets one).
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    # Extra CSV-style fields (artist_brand, full_name, website, soundcloud, facebook, etc.) as JSON
    extra_json: Mapped[str | None] = mapped_column(Text, nullable=True, default="{}")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    last_login_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_profile_updated_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    releases: Mapped[list["Release"]] = relationship(
        "Release",
        secondary=release_artists_table,
        back_populates="artists",
    )
    tasks: Mapped[list["AutomationTask"]] = relationship(back_populates="artist")
    social_connections: Mapped[list["SocialConnection"]] = relationship(back_populates="artist")
    activity_logs: Mapped[list["ArtistActivityLog"]] = relationship(back_populates="artist")
    media_files: Mapped[list["ArtistMedia"]] = relationship(back_populates="artist", cascade="all, delete-orphan")


class ArtistActivityLog(Base):
    """Log of activity with an artist (e.g. reminder email sent) to avoid flooding and for history."""
    __tablename__ = "artist_activity_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    artist_id: Mapped[int] = mapped_column(ForeignKey("artists.id", ondelete="CASCADE"), nullable=False)
    activity_type: Mapped[str] = mapped_column(String(80), nullable=False, index=True)  # e.g. reminder_email
    details: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    artist: Mapped["Artist"] = relationship(back_populates="activity_logs")


class DemoSubmission(Base):
    __tablename__ = "demo_submissions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    artist_name: Mapped[str] = mapped_column(String(200), nullable=False)
    contact_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    email: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    phone: Mapped[str | None] = mapped_column(String(80), nullable=True)
    genre: Mapped[str | None] = mapped_column(String(120), nullable=True)
    city: Mapped[str | None] = mapped_column(String(120), nullable=True)
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    links_json: Mapped[str] = mapped_column(Text, default="[]")
    fields_json: Mapped[str] = mapped_column(Text, default="{}")
    consent_to_emails: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    consent_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    source: Mapped[str] = mapped_column(String(80), default="wordpress_demo_form", nullable=False)
    source_site_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    status: Mapped[str] = mapped_column(String(30), default="demo", nullable=False, index=True)
    admin_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    approval_subject: Mapped[str | None] = mapped_column(String(255), nullable=True)
    approval_body: Mapped[str | None] = mapped_column(Text, nullable=True)
    approval_email_sent_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    rejection_email_sent_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    artist_id: Mapped[int | None] = mapped_column(ForeignKey("artists.id"), nullable=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    artist: Mapped["Artist"] = relationship()


class ArtistMedia(Base):
    """Per-artist media folder: files uploaded by the artist for their own use."""
    __tablename__ = "artist_media"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    artist_id: Mapped[int] = mapped_column(ForeignKey("artists.id", ondelete="CASCADE"), nullable=False, index=True)
    filename: Mapped[str] = mapped_column(String(255), nullable=False)
    stored_path: Mapped[str] = mapped_column(String(500), nullable=False)
    content_type: Mapped[str | None] = mapped_column(String(120), nullable=True)
    size_bytes: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    artist: Mapped["Artist"] = relationship(back_populates="media_files")


class CampaignRequest(Base):
    """Artist-requested campaign for a release; label can approve and create campaign."""
    __tablename__ = "campaign_requests"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    artist_id: Mapped[int] = mapped_column(ForeignKey("artists.id", ondelete="CASCADE"), nullable=False, index=True)
    release_id: Mapped[int | None] = mapped_column(ForeignKey("releases.id", ondelete="SET NULL"), nullable=True, index=True)
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(30), default="pending", nullable=False, index=True)  # pending | approved | rejected
    admin_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    artist: Mapped["Artist"] = relationship()
    release: Mapped["Release | None"] = relationship()


class PendingReleaseToken(Base):
    """One-time token sent to artist when a campaign request is approved; links to form for artist + track details."""
    __tablename__ = "pending_release_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    campaign_request_id: Mapped[int] = mapped_column(ForeignKey("campaign_requests.id", ondelete="CASCADE"), nullable=False, index=True)
    artist_id: Mapped[int] = mapped_column(ForeignKey("artists.id", ondelete="CASCADE"), nullable=False, index=True)
    expires_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), nullable=False)
    used_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    campaign_request: Mapped["CampaignRequest"] = relationship()
    artist: Mapped["Artist"] = relationship()


class PendingRelease(Base):
    """Track approved for release; artist submitted full details via form; waiting for label treatment."""
    __tablename__ = "pending_releases"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    campaign_request_id: Mapped[int | None] = mapped_column(ForeignKey("campaign_requests.id", ondelete="SET NULL"), nullable=True, index=True)
    artist_id: Mapped[int | None] = mapped_column(ForeignKey("artists.id", ondelete="SET NULL"), nullable=True, index=True)
    artist_name: Mapped[str] = mapped_column(String(200), nullable=False)
    artist_email: Mapped[str] = mapped_column(String(255), nullable=False)
    artist_data_json: Mapped[str] = mapped_column(Text, default="{}")  # Same keys as Artist extra_json
    release_title: Mapped[str] = mapped_column(String(300), nullable=False)
    release_data_json: Mapped[str] = mapped_column(Text, default="{}")  # catalog_number, release_date, track_title, etc.
    status: Mapped[str] = mapped_column(String(30), default="pending", nullable=False, index=True)  # pending | processed
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    campaign_request: Mapped["CampaignRequest | None"] = relationship()
    artist: Mapped["Artist | None"] = relationship()


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    full_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    role: Mapped[str] = mapped_column(String(20), nullable=False)
    artist_id: Mapped[int | None] = mapped_column(ForeignKey("artists.id"), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    last_login_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    artist: Mapped[Artist | None] = relationship()
    identities: Mapped[list["UserIdentity"]] = relationship(back_populates="user", cascade="all, delete-orphan")


class UserIdentity(Base):
    __tablename__ = "user_identities"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    provider: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    provider_subject: Mapped[str] = mapped_column(String(255), nullable=False)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    display_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    last_login_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped["User"] = relationship(back_populates="identities")


class PasswordResetToken(Base):
    """One-time token for password reset; stored as hash, expires after 1 hour."""
    __tablename__ = "password_reset_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    expires_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    user: Mapped["User"] = relationship()


class Release(Base):
    __tablename__ = "releases"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    # Primary/first artist (for backward compat). Nullable when sync did not match any artist.
    artist_id: Mapped[int | None] = mapped_column(ForeignKey("artists.id"), nullable=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    status: Mapped[str] = mapped_column(String(30), default="submitted")
    file_path: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    artist: Mapped[Artist | None] = relationship(foreign_keys=[artist_id])
    artists: Mapped[list["Artist"]] = relationship(
        "Artist",
        secondary=release_artists_table,
        back_populates="releases",
    )


class CatalogTrack(Base):
    """Catalog metadata export schema (Proton / SiYu Rec CSV). One row per track."""
    __tablename__ = "catalog_tracks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    catalog_number: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    release_title: Mapped[str] = mapped_column(String(300), nullable=False)
    pre_order_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    release_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    upc: Mapped[str | None] = mapped_column(String(32), nullable=True)
    isrc: Mapped[str | None] = mapped_column(String(32), nullable=True)
    original_artists: Mapped[str | None] = mapped_column(String(500), nullable=True)
    original_first_last: Mapped[str | None] = mapped_column(String(500), nullable=True)
    remix_artists: Mapped[str | None] = mapped_column(String(500), nullable=True)
    remix_first_last: Mapped[str | None] = mapped_column(String(500), nullable=True)
    track_title: Mapped[str | None] = mapped_column(String(300), nullable=True)
    mix_title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    duration: Mapped[str | None] = mapped_column(String(20), nullable=True)  # e.g. 00:05:17
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class AutomationTask(Base):
    __tablename__ = "automation_tasks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    artist_id: Mapped[int] = mapped_column(ForeignKey("artists.id"), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    status: Mapped[str] = mapped_column(String(30), default="queued")
    details: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    artist: Mapped[Artist] = relationship(back_populates="tasks")


class SocialConnection(Base):
    __tablename__ = "social_connections"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    provider: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    account_label: Mapped[str] = mapped_column(String(120), nullable=False)
    artist_id: Mapped[int | None] = mapped_column(ForeignKey("artists.id"), nullable=True)
    external_account_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    scopes_csv: Mapped[str] = mapped_column(Text, default="")
    oauth_state: Mapped[str | None] = mapped_column(String(255), nullable=True, index=True)
    pkce_code_verifier: Mapped[str | None] = mapped_column(String(255), nullable=True)
    one_time_token: Mapped[str | None] = mapped_column(String(255), nullable=True, index=True)
    one_time_expires_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    access_token: Mapped[str | None] = mapped_column(Text, nullable=True)
    refresh_token: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(30), default="pending")
    authorized_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    artist: Mapped[Artist | None] = relationship(back_populates="social_connections")


class HubConnector(Base):
    """Advanced connectors hub: Mailchimp, WordPress Codex, etc."""
    __tablename__ = "hub_connectors"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    connector_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    account_label: Mapped[str] = mapped_column(String(120), nullable=False)
    config_json: Mapped[str] = mapped_column(Text, default="{}")
    status: Mapped[str] = mapped_column(String(30), default="active")
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())



class MailingList(Base):
    __tablename__ = "mailing_lists"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, default="")
    from_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    reply_to_email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    company_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    physical_address: Mapped[str | None] = mapped_column(Text, nullable=True)
    default_language: Mapped[str] = mapped_column(String(10), default="en", nullable=False)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    subscribers: Mapped[list["MailingSubscriber"]] = relationship(
        back_populates="mailing_list",
        cascade="all, delete-orphan",
    )


class MailingSubscriber(Base):
    __tablename__ = "mailing_subscribers"
    __table_args__ = (UniqueConstraint("list_id", "email", name="uq_mailing_subscribers_list_email"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    list_id: Mapped[int] = mapped_column(ForeignKey("mailing_lists.id", ondelete="CASCADE"), nullable=False, index=True)
    email: Mapped[str] = mapped_column(String(255), nullable=False)
    full_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    status: Mapped[str] = mapped_column(String(30), default="subscribed", nullable=False, index=True)
    consent_source: Mapped[str | None] = mapped_column(String(255), nullable=True)
    consent_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    unsubscribed_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    unsubscribe_token: Mapped[str] = mapped_column(String(64), nullable=False, unique=True, index=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    mailing_list: Mapped["MailingList"] = relationship(back_populates="subscribers")

class Campaign(Base):
    """Unified campaign: one content sent to social, Mailchimp, and/or WordPress."""
    __tablename__ = "campaigns"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    artist_id: Mapped[int | None] = mapped_column(ForeignKey("artists.id"), nullable=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    title: Mapped[str] = mapped_column(String(300), nullable=False)
    body_text: Mapped[str] = mapped_column(Text, default="")
    body_html: Mapped[str | None] = mapped_column(Text, nullable=True)
    media_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    status: Mapped[str] = mapped_column(String(30), default="draft")  # draft | scheduled | sending | sent | failed
    scheduled_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    sent_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    targets: Mapped[list["CampaignTarget"]] = relationship(back_populates="campaign", cascade="all, delete-orphan")
    deliveries: Mapped[list["CampaignDelivery"]] = relationship(back_populates="campaign", cascade="all, delete-orphan")


class CampaignTarget(Base):
    """Per-channel target: social connection, Mailchimp (connector + list_id), or WordPress connector."""
    __tablename__ = "campaign_targets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    campaign_id: Mapped[int] = mapped_column(ForeignKey("campaigns.id"), nullable=False)
    channel_type: Mapped[str] = mapped_column(String(30), nullable=False)  # social | mailchimp | wordpress
    external_id: Mapped[str] = mapped_column(String(100), nullable=False)  # social_connection_id or hub_connector_id
    channel_payload: Mapped[str] = mapped_column(Text, default="{}")  # list_id, post_type, etc. as JSON

    campaign: Mapped["Campaign"] = relationship(back_populates="targets")
    deliveries: Mapped[list["CampaignDelivery"]] = relationship(back_populates="target", cascade="all, delete-orphan")


class CampaignDelivery(Base):
    """Per-channel send result for a campaign."""
    __tablename__ = "campaign_deliveries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    campaign_id: Mapped[int] = mapped_column(ForeignKey("campaigns.id"), nullable=False)
    target_id: Mapped[int] = mapped_column(ForeignKey("campaign_targets.id"), nullable=False)
    channel_type: Mapped[str] = mapped_column(String(30), nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False)  # sent | failed
    external_id: Mapped[str | None] = mapped_column(String(255), nullable=True)  # provider campaign/post id
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    campaign: Mapped["Campaign"] = relationship(back_populates="deliveries")
    target: Mapped["CampaignTarget"] = relationship(back_populates="deliveries")


class SystemLog(Base):
    """System and mail logs for admin Settings > Logs. level: info, warning, error. category: mail, system, etc."""
    __tablename__ = "system_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    level: Mapped[str] = mapped_column(String(20), nullable=False, index=True)  # info, warning, error
    category: Mapped[str] = mapped_column(String(80), nullable=False, index=True)  # mail, system, auth, etc.
    message: Mapped[str] = mapped_column(String(500), nullable=False)
    details: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())

