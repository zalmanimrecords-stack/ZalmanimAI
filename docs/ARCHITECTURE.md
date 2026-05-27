# LabelOps (ZalmanimAI) — Architecture

**Last updated:** 2026-05-27

## Overview

LabelOps is a label-operations platform: demo intake, artist onboarding, pending releases, release catalog/minisites, multi-channel campaigns, and operational email.

## Applications

| App | Path | Role |
|-----|------|------|
| Admin (LM) | `apps/client` | Label staff: demos, artists, releases, campaigns, settings |
| Artist portal | `apps/artist_portal` | Artists: demos, pending-release forms, profile |
| API | `apps/server` | FastAPI + PostgreSQL |
| Worker | `apps/server/worker.py` | Scheduled campaigns, release link scans |

## Runtime (Docker Compose)

- **postgres** — primary data
- **redis** — email/auth rate limits
- **api** — FastAPI on port 8000
- **worker** — polls every 60s
- **mailserver** — local SMTP (dev)
## Layering (server)

```
HTTP routes (thin)
  → domain services (demo_service, campaign_service, campaign_send, workflow_email)
  → models / DB
  → integrations (SMTP, Gmail API, social, Mailchimp, WordPress)
```

**Hotspot:** `app/api/routes.py` still holds many domains; new work should extract services (see `demo_service.py` as the pattern).

## Auth

- JWT; role resolved from DB on each request
- LM routes: `get_current_lm_user` (blocks artist tokens)
- Permissions: `ROLE_PERMISSIONS` in `app/services/auth.py`; enforce with `require_permission()` in routes
- Roles: `admin`, `manager`, `artist` (portal)

## Key workflows (P0/P1)

| Workflow | Service / module | Notes |
|----------|------------------|--------|
| Demo approval | `demo_service.py` | Approval completes even if email fails; `email_warning` in response; resend endpoint |
| Workflow email | `workflow_email.py` | Logs to system log category `workflow` |
| Campaign send | `campaign_send.py` | Status: `sent`, `partial`, `failed`; retry failed targets |
| Mail templates | `mail_template_settings` table + `mail_settings` transport | Split persistence (P1) |
| Pending release fields | `pending_releases.selected_image_id`, `notifications_muted` | Synced with JSON (P1) |

## Documentation

Business logic (evidence-based): [`docs/core-business-logic/`](core-business-logic/)

Change log for remediation passes: [`docs/REMEDIATION-CHANGELOG.md`](REMEDIATION-CHANGELOG.md)

## Deploy

Production: Hostinger VPS, Docker Compose — see [`deploy/DEPLOY_VPS.md`](../deploy/DEPLOY_VPS.md).

Pre-release: `scripts/pre_release_checks.ps1` (Flutter analyze/test + pytest).
