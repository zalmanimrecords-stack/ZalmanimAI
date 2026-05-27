# Remediation changelog

**Last updated:** 2026-05-27

## P0 (completed)

### Team A — Backend domain extraction

- Added `app/services/demo_service.py` (approve, resend, pending release, artist link)
- `routes.py` delegates demo approval; removed duplicate demo template helpers
- Tests: `tests/test_demo_service.py`

### Team B — Admin UI decomposition

- `demo_submission_dialogs.dart` — approve/reject + email warning UI
- `demo_submission_details_dialog.dart` — resend approval email
- Thinner `admin_dashboard_page.dart` for demo flows

### Team C — Email reliability

- `app/services/workflow_email.py` — structured logging (`workflow` category)
- Demo approval: completes on non-rate-limit email failure; `DemoSubmissionApproveResponse.email_warning`
- `POST /api/admin/demo-submissions/{id}/resend-approval-email`
- Pending-release artist emails use workflow email

## P1 (completed)

### Team D — Campaign partial success

- Campaign status `partial` when some targets succeed and some fail
- `POST /api/admin/campaigns/{id}/retry-failed` — retries only failed targets
- Admin UI: **Retry failed** on partial/failed campaigns
- Tests: `tests/test_campaign_partial_success.py`

### Team E — Mail transport vs templates

- New table/model `mail_template_settings` (id=1)
- `app/services/mail_template_settings.py` — read/write templates; migrates from legacy `mail_settings` row on startup
- `mail_settings.py` — transport in `mail_settings`; templates via template service

### Team F — Pending release typed fields

- Columns: `pending_releases.selected_image_id`, `pending_releases.notifications_muted`
- `pending_release_helpers.py` syncs JSON ↔ columns

### Team G — Manager permissions

- `require_permission()` / `has_permission()` in `app/api/deps.py`
- Campaign routes use `campaigns:read` / `campaigns:write` (managers allowed)
- Client: `AuthSession.can()`, `role_permissions.dart`, settings DB/backup gated for `settings:write`
- Tests: `tests/test_manager_permissions.py`

## P2

- **CI** — `.github/workflows/ci.yml` (pytest, Flutter analyze/test for client + artist portal)
- **Pending releases** — `pending_release_service.py`, `pending_release_routes.py` (admin routes extracted from `routes.py`)
- **MinIO** — removed from `docker-compose.yml` (uploads use local `UPLOAD_DIR` only)
- **Link discovery** — per-platform backoff via `releases.link_scan_backoff_json` and `release_link_backoff.py`

## P3

- **Route extraction** — `release_routes.py`, `catalog_routes.py`, `settings_routes.py`; `release_minisite_helpers.py` for shared minisite URL helpers
- **Permissions** — `require_permission` on releases, catalog, settings, reports, and users (managers: read settings/releases/reports; write blocked where role lacks permission)
- **Tests** — extended `test_manager_permissions.py`; catalog/minisite/restore tests target extracted routers
