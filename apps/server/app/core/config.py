from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "LabelOps API"
    jwt_secret: str = ""  # Set via env (e.g. JWT_SECRET); see secrets-backup.txt for local dev
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 60 * 24
    database_url: str = ""  # Set via env DATABASE_URL; see secrets-backup.txt for local dev
    upload_dir: str = "storage/uploads"

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
    emails_per_hour: int = 30  # Max emails per hour; 0 = no limit (not recommended)
    redis_url: str = "redis://redis:6379/0"  # Used for rate-limit counter
    demo_submission_token: str = ""  # Set via env DEMO_SUBMISSION_TOKEN; optional shared secret for demo form
    # Base URL for password reset links in email (client app, not API). If empty, routes use https://lm.zalmanim.com
    password_reset_base_url: str = ""
    artist_portal_base_url: str = "https://artists.zalmanim.com"
    zalmanim_website_url: str = "https://zalmanim.com"


settings = Settings()
