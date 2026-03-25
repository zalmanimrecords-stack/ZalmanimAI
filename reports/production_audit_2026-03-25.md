# Production Audit 2026-03-25

## Fixed in this pass

- Disabled unsafe-by-default API docs and wildcard CORS fallback.
- Added stricter runtime validation for `JWT_SECRET`, `DATABASE_URL`, production CORS, and trusted hosts.
- Added optional `TOKEN_ENCRYPTION_KEY` validation and encrypted social provider access/refresh tokens at rest with legacy-token migration on startup.
- Added trusted-host middleware support and local-dev CORS regex fallback.
- Removed `DEMO_SUBMISSION_TOKEN` from the public artist portal frontend bundle.
- Allowed public demo submissions from configured first-party origins without exposing a shared secret in the browser.
- Added redirect sanitization for OAuth start/callback flows and moved app login tokens to URL fragments instead of query parameters.
- Tightened root `.gitignore` and `.dockerignore`.
- Added `apps/server/.dockerignore` so uploaded files do not get baked into API images.
- Hardened production compose with Redis/API/worker/web healthchecks and worker heartbeat-based readiness.
- Switched the API container to run as a non-root user.
- Added explicit upload size/type limits and raised the password baseline to 12 characters.
- Removed tracked temp dumps and backup exports from the repository workspace.
- Replaced `wp-codex-bridge.env` with a placeholder example so no real credentials remain in the tracked file.

## Important remaining risks

- Large route and UI files still need refactoring for long-term maintainability.
- `tmp_release_mgmt` is still tracked in git even though it appears to be an extracted workbook artifact with no code references.
- `tmp_deploy_branch` is still tracked as a gitlink-style nested checkout and should not be removed blindly without confirming the release workflow no longer depends on it.
- Upload endpoints now have size limits, but they still buffer files into memory instead of streaming to disk.
- FastAPI startup wiring still relies on deprecated `on_event()` hooks and should be moved to lifespan handlers.
- Pydantic models still use class-based `Config`, which raises deprecation warnings on every test run.

## Biggest oversized code files

- `apps/client/lib/features/admin/admin_dashboard_page.dart`
- `apps/server/app/api/routes.py`
- `apps/artist_portal/lib/features/dashboard/artist_dashboard_page.dart`
- `apps/client/lib/core/api_client.dart`

## Verification

- `python -m pytest tests/test_priority_one_hardening.py -q` from `apps/server`
- Result: `16 passed`
- `python -m pytest tests/test_social_connection_token_hardening.py -q` from `apps/server`
- Result: `4 passed`
- `python -m py_compile apps/server/app/api/routes.py apps/server/app/models/models.py apps/server/app/core/config.py apps/server/app/services/email_service.py apps/server/app/services/social_publisher.py apps/server/worker.py`
