from urllib.parse import urlparse

from pydantic_settings import BaseSettings, SettingsConfigDict


def _split_csv(value: str) -> list[str]:
    return [item.strip() for item in (value or "").split(",") if item.strip()]


def _origin_from_url(value: str) -> str:
    parsed = urlparse((value or "").strip())
    if not parsed.scheme or not parsed.netloc:
        return ""
    return f"{parsed.scheme}://{parsed.netloc}"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "LabelOps API"
    environment: str = "development"
    api_docs_enabled: bool = False
    cors_allowed_origins: str = ""
    trusted_hosts: str = ""
    oauth_allowed_redirect_origins: str = ""
    public_demo_allowed_origins: str = ""
    jwt_secret: str = ""  # Set via env (e.g. JWT_SECRET); keep out of source control.
    token_encryption_key: str = ""  # Optional dedicated key for encrypting stored provider tokens.
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 60 * 24
    database_url: str = ""  # Set via env DATABASE_URL; keep out of source control.
    upload_dir: str = "storage/uploads"

    admin_app_base_url: str = "https://lm.zalmanim.com"
    oauth_redirect_base: str = "http://localhost:8000/api/admin/social/callback"
    oauth_success_redirect: str = ""  # Optional: redirect here after connect (e.g. Flutter app URL)
    google_client_id: str = ""
    google_client_secret: str = ""

    meta_client_id: str = ""
    meta_client_secret: str = ""

    tiktok_client_id: str = ""
    tiktok_client_secret: str = ""

    youtube_client_id: str = ""
    youtube_client_secret: str = ""

    x_client_id: str = ""
    x_client_secret: str = ""

    linkedin_client_id: str = ""
    linkedin_client_secret: str = ""

    soundcloud_client_id: str = ""
    soundcloud_client_secret: str = ""

    # Advanced connectors: use env instead of asking for API keys in the UI
    mailchimp_api_key: str = ""
    wordpress_rest_base_url: str = ""
    wordpress_client_key: str = ""
    wordpress_client_secret: str = ""

    # Email sending via SMTP with per-hour rate limit to avoid spam listing
    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587  # 587 = STARTTLS, 465 = implicit SSL (use smtp_use_ssl=True)
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_use_tls: bool = True   # STARTTLS on port 587
    smtp_use_ssl: bool = False  # True for port 465 (implicit SSL); use with smtp_port=465
    smtp_from_email: str = ""  # Default "From" address; fallback to smtp_user if empty
    # Optional backup SMTP (env defaults; DB mail_settings overrides when set)
    smtp_backup_host: str = ""
    smtp_backup_port: int = 587
    smtp_backup_user: str = ""
    smtp_backup_password: str = ""
    smtp_backup_use_tls: bool = True
    smtp_backup_use_ssl: bool = False
    smtp_backup_from_email: str = ""  # If empty, primary smtp_from_email is used when sending via backup
    emails_per_hour: int = 10  # Max emails per hour; 0 = no limit (not recommended)
    redis_url: str = "redis://redis:6379/0"  # Used for rate-limit counter
    demo_submission_token: str = ""  # Set via env DEMO_SUBMISSION_TOKEN; optional shared secret for demo form
    # Base URL for password reset links in email (client app, not API). If empty, routes use https://lm.zalmanim.com
    password_reset_base_url: str = ""
    artist_portal_base_url: str = "https://artists.zalmanim.com"
    zalmanim_website_url: str = "https://zalmanim.com"

    def is_production(self) -> bool:
        return (self.environment or "").strip().lower() in {"prod", "production"}

    def cors_origin_list(self) -> list[str]:
        return _split_csv(self.cors_allowed_origins)

    def trusted_host_list(self) -> list[str]:
        configured = _split_csv(self.trusted_hosts)
        if configured:
            return configured
        if self.is_production():
            return []
        return ["localhost", "127.0.0.1", "testserver"]

    def oauth_allowed_redirect_origin_list(self) -> list[str]:
        origins: list[str] = []
        candidates = _split_csv(self.oauth_allowed_redirect_origins)
        candidates.extend(
            [
                self.admin_app_base_url,
                self.artist_portal_base_url,
                self.zalmanim_website_url,
                self.password_reset_base_url,
                self.oauth_success_redirect,
            ]
        )
        if not self.is_production():
            candidates.extend(["http://localhost", "http://127.0.0.1"])
        for candidate in candidates:
            origin = _origin_from_url(candidate)
            if origin and origin not in origins:
                origins.append(origin)
        return origins

    def public_demo_allowed_origin_list(self) -> list[str]:
        origins: list[str] = []
        candidates = _split_csv(self.public_demo_allowed_origins)
        candidates.extend([self.artist_portal_base_url, self.zalmanim_website_url])
        if not self.is_production():
            candidates.extend(["http://localhost", "http://127.0.0.1"])
        for candidate in candidates:
            origin = _origin_from_url(candidate)
            if origin and origin not in origins:
                origins.append(origin)
        return origins

    def validate_runtime(self) -> None:
        errors: list[str] = []
        jwt_secret = (self.jwt_secret or "").strip()
        database_url = (self.database_url or "").strip()
        cors_origins = self.cors_origin_list()

        if not database_url:
            errors.append("DATABASE_URL is required.")
        if not jwt_secret:
            errors.append("JWT_SECRET is required.")
        elif len(jwt_secret) < 32:
            errors.append("JWT_SECRET must be at least 32 characters.")
        token_encryption_key = (self.token_encryption_key or "").strip()
        if token_encryption_key and len(token_encryption_key) < 32:
            errors.append("TOKEN_ENCRYPTION_KEY must be at least 32 characters when set.")
        if "*" in cors_origins:
            errors.append("CORS_ALLOWED_ORIGINS must not contain '*'.")

        if self.is_production():
            if self.api_docs_enabled:
                errors.append("API docs must be disabled in production.")
            if not cors_origins:
                errors.append("CORS_ALLOWED_ORIGINS must be set in production.")
            if not self.trusted_host_list():
                errors.append("TRUSTED_HOSTS must be set in production.")

        if errors:
            raise ValueError("Invalid runtime configuration: " + " ".join(errors))


settings = Settings()
