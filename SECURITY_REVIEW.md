# Security Review – ZalmanimAI / LabelOps

**Date:** March 2025  
**Scope:** Backend API (FastAPI), Flutter client, backup/restore, auth, and public endpoints.

---

## Executive summary

The system uses JWT-based auth, role-based access, and Pydantic validation. Several issues should be addressed before or soon after production: **default credentials in the client**, **weak default secrets**, **no login/API rate limiting**, **XSS risk on the unsubscribe page**, and **missing security headers**. Backup/restore is correctly restricted to admins and uses whitelisted structures.

---

## 1. Authentication and authorization

### Implemented

- **Login:** `POST /api/auth/login` with email/password; bcrypt via `passlib`, JWT (HS256) with configurable expiry (default 24h).
- **Roles:** `admin`, `manager`, `artist` with permissions in `ROLE_PERMISSIONS`; `require_admin()` and `require_artist()` used on sensitive routes.
- **Protection:** Most API routes use `user: UserContext = Depends(get_current_user)`; backup/restore use `require_admin(user)`.
- **OAuth:** Google/Facebook; OAuth state is signed JWT; PKCE for browser flows; social connect includes `user_id` in state.

### Findings

| Severity | Issue | Location | Recommendation |
|----------|--------|----------|----------------|
| **High** | Default login credentials pre-filled in client | `apps/client/lib/features/auth/login_page.dart`: `TextEditingController(text: 'admin@label.local')`, `'admin123'`; seed hint in UI | Remove pre-fill for production builds (e.g. use a build flag or empty strings when not in debug). Never ship default admin credentials. |
| **Medium** | No login rate limiting or account lockout | Auth routes | Add rate limiting (e.g. Redis) for `POST /api/auth/login` and consider lockout after N failures. |
| **Low** | Stateless JWT only; no server-side revocation | `app/services/auth.py` | Acceptable for many deployments; for strict revocation consider a blocklist or short-lived tokens + refresh. |

---

## 2. API and route protection

### Public endpoints (no auth)

- `POST /api/auth/login`
- `GET /api/auth/{provider}/start`, `GET /api/auth/{provider}/callback`
- `POST /api/public/demo-submissions` (optional `x-demo-token` when `demo_submission_token` is set)
- `GET /api/unsubscribe/{token}` (unsubscribe by token)
- `GET /api/media/campaigns/{filename}` (public by design for social previews)
- `GET /health`, `GET /`

All other `/api/*` routes require `get_current_user`; admin-only routes also call `require_admin(user)`.

### Backup and restore

- **GET /api/admin/backup:** Requires admin; returns full DB export as JSON download. Properly protected.
- **POST /api/admin/restore:** Requires admin; accepts only `.json`; uses whitelisted tables and columns in `backup_service.py` (no raw user input in SQL table/column names). Restore validates `version == 1` and structure.

**Finding:** Backup/restore design is sound. Consider adding a confirmation step or optional extra auth for restore (e.g. re-enter password) because it is destructive.

---

## 3. Data and secrets management

### Implemented

- Config via `pydantic_settings` and `.env`; no secrets in code.
- JWT secret, DB URL, OAuth client secrets, SMTP, Mailchimp, WordPress, Redis, and `demo_submission_token` read from environment.

### Findings

| Severity | Issue | Location | Recommendation |
|----------|--------|----------|----------------|
| **High** | Weak default `jwt_secret` and DB URL | `app/core/config.py`: `jwt_secret: str = "change-me"`, default `database_url` with fixed user/password | Require strong `JWT_SECRET` in production (e.g. fail startup or refuse login if still default). Use env-only DB URL in production. |
| **Medium** | Default secrets in Docker Compose | `docker-compose.yml`: `JWT_SECRET: change-me-in-prod`, default Postgres/Minio passwords | Document that these must be overridden; consider no default for `JWT_SECRET` in prod. |

---

## 4. Input validation and injection

### Implemented

- Pydantic schemas for request bodies; `EmailStr` where used; role and status allowlists.
- SQL: SQLAlchemy ORM; backup/restore uses whitelisted table/column names only (no user input in DDL/DML identifiers).
- File uploads: release upload uses `uuid.hex + extension`; campaign media restricts extensions and blocks path traversal; restore accepts only `.json`.

### Findings

| Severity | Issue | Location | Recommendation |
|----------|--------|----------|----------------|
| **Medium** | Unsubscribe page: email and list name interpolated into HTML without escaping | `apps/server/app/api/audience_routes.py` ~471: `{subscriber.email}`, `{list_name}` in HTML | HTML-escape `subscriber.email` and `list_name` (e.g. `html.escape`) before inserting into the page to prevent XSS if data contains markup. |
| **Low** | Release upload: extension from client not allowlisted | `routes.py` (release upload) | Restrict to a fixed set (e.g. `.mp3`, `.wav`, `.zip`) to reduce risk of executable or unexpected types. |

---

## 5. Security headers and CORS

### Implemented

- CORS: `CORSMiddleware` with `allow_origins=["*"]`, `allow_credentials=False`, standard methods and headers.

### Findings

| Severity | Issue | Location | Recommendation |
|----------|--------|----------|----------------|
| **Medium** | No security headers on API responses | `app/main.py` | Add middleware or default headers: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY` (or appropriate value), and optionally `Content-Security-Policy` for any HTML responses. |
| **Low** | CORS allows any origin | `main.py` | For production, consider restricting `allow_origins` to the Flutter web origin(s) if the app is only served from known domains. |

---

## 6. Other areas

- **Email rate limiting:** Redis-backed “emails per hour” limit is in place; good for abuse prevention.
- **Logging:** No passwords or tokens logged; request bodies/headers not logged.
- **Demo submissions:** Optional token (`x-demo-token` / `x-labelops-demo-token`) when `demo_submission_token` is set; consider always requiring it in production if the endpoint is public.
- **File download (backup):** `Content-Disposition: attachment` is set; filename is server-generated (timestamp), so no user-controlled filename in response.

---

## 7. Remediation summary (priority order)

1. **High:** Remove or gate default login credentials in the Flutter client for production (e.g. empty fields when not in debug).
2. **High:** Enforce strong `JWT_SECRET` and non-default DB credentials in production (fail fast if defaults detected).
3. **Medium:** Add login (and optionally global API) rate limiting and consider account lockout.
4. **Medium:** Escape `subscriber.email` and `list_name` on the unsubscribe HTML page (XSS).
5. **Medium:** Add security headers (e.g. `X-Content-Type-Options`, `X-Frame-Options`, and CSP where HTML is served).
6. **Low:** Restrict release upload file extensions to an allowlist.
7. **Low:** Restrict CORS origins in production to known front-end origins.

---

## 8. Files referenced

| Area | Paths |
|------|--------|
| Auth & tokens | `apps/server/app/services/auth.py`, `apps/server/app/api/routes.py`, `apps/client/lib/core/session_storage.dart`, `apps/client/lib/features/auth/login_page.dart` |
| Config & secrets | `apps/server/app/core/config.py`, `docker-compose.yml`, `deploy/.env.production.example` |
| API protection | `apps/server/app/api/routes.py`, `apps/server/app/api/audience_routes.py` |
| Backup/restore | `apps/server/app/api/routes.py` (admin backup/restore), `apps/server/app/services/backup_service.py` |
| Unsubscribe / XSS | `apps/server/app/api/audience_routes.py` |
| CORS / middleware | `apps/server/app/main.py` |
