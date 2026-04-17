# Open Questions And Assumptions

**Last updated:** 2026-04-17

**Scope analyzed:** Full repo with emphasis on server business behavior and admin settings UI

**Confidence level:** Medium

---

## Open Questions

- `Unclear from code`: what exact branch logic differentiates all demo approval/update paths in `routes.py`, because related behavior is spread across long handlers and helpers.
- `Unclear from code`: whether managers are intentionally shown UI affordances for routes that later require `admin`.
- `Needs validation`: whether campaign aggregate failure on one failed target is the intended business outcome or a technical simplification.
- `Needs validation`: whether email-send failure should block approval flows when the only artist next-step link is delivered by email.

## Assumptions Made

- `Assumption`: the server app is the source of truth for business behavior; Flutter clients are presentation/orchestration only.
- `Assumption`: `PendingRelease.status='processed'` means label completion rather than public publication.
- `Assumption`: `CampaignRequest` is release-progress intake, not the same concept as outbound `Campaign`.

## Naming And Model Mismatches

- `CampaignRequest` and `Campaign` are distinct but semantically adjacent; the names are easy to confuse.
- `LabelInboxThread` is not structurally linked to `PendingRelease`, even though pending-release helpers create inbox messages.
- The repo and UI still contain `LabelOps` naming while the product surface also uses `Zalmanim`.

## Settings / Features Without UI Exposure

| Setting or feature | Classification | Evidence | Notes |
|---|---|---|---|
| `smtp_*`, `smtp_backup_*`, `emails_per_hour`, email template fields in `MailSettings` | UI-exposed | `mail_settings.py`, `routes.py`, `apps/client/lib/features/admin/tabs/settings_tab.dart`, `email_templates_tab.dart` | Admin can view/update through Settings tabs. |
| `email_footer` | UI-exposed | `mail_settings.py`, `email_templates_tab.dart` | Saved in template tab and appended globally. |
| `api_docs_enabled`, `cors_allowed_origins`, `trusted_hosts` | Internal-only | `core/config.py`, `main.py` | Runtime/security configuration, no admin UI expected. |
| OAuth client IDs/secrets and connector env vars (`google_client_id`, `mailchimp_api_key`, `wordpress_client_secret`, etc.) | No UI, persisted via env | `core/config.py`, README, connector/callback routes | Business-relevant because they control integration availability, but only env/config path is visible. |
| `demo_submission_token` | No UI, persisted via env | `core/config.py`, public demo route family | Shared-secret protection for demo intake is not surfaced in admin UI. |
| `AutomationTask` | Write-only / dead `Needs validation` | `models.py`, README, worker.py | Persisted model exists, but analyzed worker does not process it. |

## Validation Priorities

- Confirm intended role matrix for managers.
- Confirm whether `AutomationTask` is still a supported feature or a leftover model.
- Confirm whether pending-release reminders and inbox seeding should work for email-only artists without `artist_id`.

## Code References

- `apps/server/app/core/config.py` - env/runtime settings surface
- `apps/server/app/main.py` - settings-driven runtime behavior
- `apps/server/app/models/models.py` - `MailSettings` and `AutomationTask`
- `apps/server/app/services/mail_settings.py` - persisted settings reads/writes
- `apps/server/app/api/routes.py` - settings endpoints and business workflows
- `apps/server/worker.py` - currently automated feature surface
- `apps/client/lib/features/admin/tabs/settings_tab.dart` - admin settings UI exposure
- `apps/client/lib/features/admin/tabs/email_templates_tab.dart` - template UI exposure
