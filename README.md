# LabelOps (MVP Foundation)

## Pushing to GitHub

The project is already a git repo with an initial commit. To push to GitHub:

1. Create a **new repository** on [GitHub](https://github.com/new) (do not add a README or .gitignore).
2. Add the remote and push (replace `YOUR_USERNAME` and `YOUR_REPO` with your GitHub username and repo name):

```bash
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git branch -M main
git push -u origin main
```

Or with SSH:

```bash
git remote add origin git@github.com:YOUR_USERNAME/YOUR_REPO.git
git branch -M main
git push -u origin main
```

---

## What Exists Now

- Flutter client (`apps/client`):
  - Login
  - Admin portal: artists, social accounts, advanced connectors, **campaigns**
  - Artist portal: upload music + view system tasks
- FastAPI server (`apps/server`):
  - JWT auth
  - Artists endpoints
  - Artist dashboard
  - Music upload endpoint
  - Inactivity check endpoint
  - Social OAuth connection flow + queue-post endpoint
  - **Unified campaigns**: one content to social + Mailchimp + WordPress; schedule or send now
- Containers (`docker-compose.yml`):
  - api, worker (polls for scheduled campaigns and runs send), postgres, redis, minio

## Quick Start

Create a `.env` in the project root with required secrets (see `secrets-backup.txt` for local dev values; that file is gitignored). Then:

```bash
docker compose up --build
```

Seed users are auto-created on first run; set `SEED_ARTIST_PASSWORD`, `SEED_ADMIN_PASSWORD`, `SEED_SIMON_PASSWORD` in `.env` to assign passwords, or set them in the UI after first login.

Flutter run:

```bash
cd apps/client
flutter create .
flutter pub get
flutter run -d chrome
```

## Pre-release checks

Run all available pre-release validations from the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\pre_release_checks.ps1
```

This runs:

- `flutter analyze` + `flutter test` for `apps/client`
- `flutter analyze` + `flutter test` for `apps/artist_portal`
- `pytest` for `apps/server`

If you only need part of the suite, you can skip sections:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\pre_release_checks.ps1 -SkipServer
```

Server test setup:

```powershell
cd apps\server
py -m pip install -r requirements-dev.txt
py -m pytest
```

## Social Providers Configured in Code

- Facebook Page
- Instagram Business
- Threads
- TikTok
- YouTube
- X (Twitter)
- LinkedIn
- SoundCloud

Social connections use a **browser-only OAuth flow**: the server does not call the social provider's token API. The app opens a connect page in the browser; the user signs in at the provider; the callback page exchanges the code for tokens in the browser (PKCE) and then sends the tokens to the server. So `client_secret` is **not required** for providers that support PKCE; only `client_id` is needed. Set env vars in server runtime:

- `META_CLIENT_ID` (and optionally `META_CLIENT_SECRET` if the provider requires it)
- `TIKTOK_CLIENT_ID`, `TIKTOK_CLIENT_SECRET` (or PKCE-only where supported)
- `YOUTUBE_CLIENT_ID`, `YOUTUBE_CLIENT_SECRET`
- `X_CLIENT_ID`, `X_CLIENT_SECRET`
- `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`
- `SOUNDCLOUD_CLIENT_ID`, `SOUNDCLOUD_CLIENT_SECRET`
- `OAUTH_REDIRECT_BASE` (default: `http://localhost:8000/api/admin/social/callback`)
- `OAUTH_SUCCESS_REDIRECT` (optional): after connecting an account, redirect the user here (e.g. your Flutter app URL). If unset, a simple "Connected! Close this tab." page is shown.

## API Endpoints

- `POST /api/auth/login`
- `GET /api/artists` (admin)
- `POST /api/artists` (admin)
- `GET /api/artist/me/dashboard` (artist)
- `POST /api/artist/me/releases/upload` (artist)
- `POST /api/admin/tasks/run-inactivity-check` (admin)
- `GET /api/admin/email/rate-limit` (admin) - email rate limit status
- `POST /api/admin/email/send` (admin) - send email (rate-limited per hour)
- `GET /api/admin/social/providers` (admin)
- `GET /api/admin/social/connections` (admin)
- `POST /api/admin/social/connect/start` (admin; returns `connect_page_url` for browser flow)
- `GET /api/admin/social/connect-page` (browser: claims one-time token, redirects to provider)
- `GET /api/admin/social/connect/claim` (one-time: returns PKCE data for connect-page)
- `GET /api/admin/social/provider-config` (public: token_url, client_id, redirect_uri for callback page)
- `GET /api/admin/social/callback` (oauth callback; serves HTML that does token exchange in browser)
- `POST /api/admin/social/connect/complete` (browser posts tokens after exchange)
- `POST /api/admin/social/connections/{connection_id}/disconnect` (admin)
- `POST /api/admin/social/posts/publish` (admin)
- **Advanced connectors hub:** `GET /api/admin/connectors/types`, `GET /api/admin/connectors`, `GET /api/admin/connectors/{id}`, `POST /api/admin/connectors`, `PATCH /api/admin/connectors/{id}`, `DELETE /api/admin/connectors/{id}`, `POST /api/admin/connectors/{id}/test` (admin)
- **Mailchimp lists:** `GET /api/admin/connectors/{id}/mailchimp/lists` (admin)
- **Campaigns:** `GET /api/admin/campaigns`, `GET /api/admin/campaigns/{id}`, `POST /api/admin/campaigns`, `PATCH /api/admin/campaigns/{id}`, `DELETE /api/admin/campaigns/{id}`, `POST /api/admin/campaigns/{id}/schedule`, `POST /api/admin/campaigns/{id}/cancel` (admin)
- `GET /api/admin/agents/registry` (admin) - list available specialist agents and their responsibilities
- `POST /api/admin/agents/plan` (admin) - supervisor decomposes free-text work into specialist delegations
- `GET /health`

## Advanced Connectors Hub

The admin portal has an **Advanced Connectors** tab that acts as a connections hub. **Credentials are read from the environment** so the UI does not ask for API keys when they are set.

- **Mailchimp** - Set `MAILCHIMP_API_KEY` in the server env (key with datacenter, e.g. `xxxxx-us21`). Then add a connection with just an account label; no API key is asked in the UI. Test uses the ping endpoint.
- **WordPress (Codex WP)** - Set `WORDPRESS_REST_BASE_URL`, `WORDPRESS_CLIENT_KEY`, and `WORDPRESS_CLIENT_SECRET` in the server env. Then add a connection with just a label. Test uses the signed `/context` request (same as `wp-codex-bridge.ps1`).

If these env vars are not set, the Add form shows the credential fields so you can enter them manually (or set the env vars and restart to stop asking).

## Email Sending (SMTP, rate-limited)

The server sends email **via SMTP** with a **per-hour rate limit** to reduce the risk of being flagged as spam. Configure via environment:

- `SMTP_HOST` - SMTP server host (required to enable sending). Default Docker hostname: `mailserver`
- `SMTP_PORT` - default `25` for the internal Docker mail relay; use `587` or `465` only if you point to an external SMTP server
- `SMTP_USER` / `SMTP_PASSWORD` - optional, for authenticated SMTP
- `SMTP_USE_TLS` - default `false` for the internal Docker mail relay
- `SMTP_USE_SSL` - set to `true` for port 465 (implicit SSL from connection start)
- `SMTP_FROM_EMAIL` - "From" address (fallback: `SMTP_USER`). Recommended: `info@zalmanim.com`
- **Backup SMTP (optional)** — if primary SMTP or Gmail API fails, the server tries this next:
  - `SMTP_BACKUP_HOST`, `SMTP_BACKUP_PORT` (default `587`), `SMTP_BACKUP_USER`, `SMTP_BACKUP_PASSWORD`
  - `SMTP_BACKUP_USE_TLS` / `SMTP_BACKUP_USE_SSL`, `SMTP_BACKUP_FROM_EMAIL` (falls back to primary `SMTP_FROM_EMAIL` if empty)
- `EMAILS_PER_HOUR` - max emails per hour (default `30`); set to `0` for no limit (not recommended)
- `REDIS_URL` - used for the rate-limit counter (default `redis://redis:6379/0`)

Send order: **Gmail API** (if connected with send scope) → **primary SMTP** → **backup SMTP**. Admin UI also has **Backup SMTP** fields under Settings → Mail.

The default Docker stack now includes a `mailserver` service (`boky/postfix`) that relays outgoing mail for the app. By default it allows sender addresses from `zalmanim.com`, so `info@zalmanim.com` works out of the box inside the stack.

Admin endpoints: `GET /api/admin/email/rate-limit` (status) and `POST /api/admin/email/send` (send one email). When the hourly limit is reached, send returns `429 Too Many Requests`.

## Demo Intake Flow

- Public intake endpoint: `POST /api/public/demo-submissions`
- Admin review endpoints: `GET /api/admin/demo-submissions`, `PATCH /api/admin/demo-submissions/{id}`, `POST /api/admin/demo-submissions/{id}/approve`
- Admin portal now includes a **Demos** tab for review, status changes, and approval email editing before send.
- Default shared token: `TOKEN` via `DEMO_SUBMISSION_TOKEN`
- Production default endpoint for the WordPress form: `https://lmapi.zalmanim.com/api/public/demo-submissions`
- A WordPress plugin lives at [apps/wordpress-plugin/zalmanim-demo-addon/zalmanim-demo-addon.php](/C:/Users/SimonRosenfeld/ZalmanimAI/apps/wordpress-plugin/zalmanim-demo-addon/zalmanim-demo-addon.php). It provides shortcode `[zalmanim_demo_form]` plus a configurable JSON schema so the WP form can mirror your Google Form layout/fields.

## Unified Campaigns

The admin **Campaigns** tab lets you create one campaign (name, title, body text, optional media URL) and target **social connections** (Facebook Page, Instagram, Threads, etc.), **Mailchimp** (one audience/list), and **WordPress** (Codex Bridge). Create as draft, then **Schedule** to send now or at a future date/time (UTC). The **worker** process polls every 60 seconds for campaigns with `status=scheduled` and `scheduled_at <= now` (or null for "send now"), then runs the senders and records per-channel delivery status.

- **Social:** Meta (Facebook Page, Instagram Business), Threads are implemented; others (TikTok, X, etc.) can be added in `app/services/social_publisher.py`.
- **Mailchimp:** Creates campaign, sets HTML content, sends (or schedules) to the chosen list.
- **WordPress:** Uses Codex Bridge `POST /content` to create/update a post or page.

The worker container needs the same Mailchimp and WordPress env vars as the API (`MAILCHIMP_API_KEY`, `WORDPRESS_REST_BASE_URL`, `WORDPRESS_CLIENT_KEY`, `WORDPRESS_CLIENT_SECRET`) so it can send when processing campaigns.

## Current Limitations

- Social connections are browser-only: token exchange happens in the browser; the server never calls the provider's token API.
- If a provider's token endpoint does not allow CORS from your domain, the callback page may show a network error; use a provider that supports PKCE from the browser or host the app on a domain the provider allows.
- If you have an existing DB and added social OAuth, ensure columns exist: `pkce_code_verifier`, and for browser flow `one_time_token`, `one_time_expires_at` (the server adds these on startup if missing).
- Standalone **queue post** (single social post) is still stored as an automation task; the worker does not process it. Use **Campaigns** to actually publish to social (and Mailchimp/WordPress).
- Security defaults are development-only.

## Restart Script

Use this script to re-initialize and restart the full dev system. It starts the backend and launches both the **admin app** and the **Artist Portal** as web servers, then opens the browser to each.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\restart-system.ps1 -Rebuild
```

By default the script:

1. Stops existing Docker containers.
2. Cleans dev ports (3000, 3001, 8000, 5432) so nothing is left bound from a previous run.
3. Starts the backend stack (API, Postgres, Redis, MinIO, worker).
4. Waits for the API health check.
5. Runs `flutter pub get` for the admin app and starts `flutter run -d web-server --web-port 3000` in a new window; opens `http://127.0.0.1:3000`.
6. Runs `flutter pub get` for the Artist Portal and starts it on port 3001 in another window; opens `http://127.0.0.1:3001`.

Useful flags:

- `-NoFlutter` : restart only backend containers (no admin app)
- `-NoArtistPortal` : do not launch the Artist Portal (admin app only)
- `-NoBrowser` : start Flutter web servers but do not open the browser automatically
- `-CleanVolumes` : reset Docker volumes (wipes local DB data)
- `-FlutterDevice chrome` : use another Flutter device instead of the local web server
- `-FlutterTarget lib/main.dart` : entry target for Flutter
- `-WebHost 127.0.0.1` : host for `web-server`
- `-WebPort 3000` : port for the admin app
- `-ArtistPortalPort 3001` : port for the Artist Portal
