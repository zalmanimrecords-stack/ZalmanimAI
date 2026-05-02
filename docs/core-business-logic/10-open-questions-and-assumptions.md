# Open Questions And Assumptions

**Last updated:** 2026-04-18

**Scope analyzed:** Full repo with business focus on server code and visible admin/artist UI surfaces

**Confidence level:** Medium

---

## Open Questions

- `Unclear from code`: whether the artist-portal UI rule requiring headroom confirmation for mastered releases is intentionally UI-only or should also be enforced server-side.
- `Needs validation`: whether aggregate `Campaign.status="failed"` is the desired business outcome when some targets succeeded.
- `Needs validation`: whether email delivery failure during approval/onboarding flows should block completion when the email contains the only artist-access link.
- `Unclear from code`: whether `PendingRelease.status="processed"` means released, internally archived, or merely reviewed by staff.
- `Needs validation`: whether managers are intentionally shown any controls that later fail due to `require_admin`.
- `Unclear from code`: whether `AutomationTask` is still a supported product feature or just a leftover model/UI concept.

## Assumptions Made

- `Assumption`: the server is the authoritative source of business behavior; Flutter apps mainly expose and orchestrate that behavior.
- `Assumption`: `CampaignRequest` is an intake/approval precursor, not the same concept as an outbound `Campaign`.
- `Assumption`: release minisite data on `Release` and artist minisite/public-share settings in `Artist.extra_json` are intentionally separate scopes.

## Naming And Model Mismatches

- `CampaignRequest` and `Campaign` are adjacent concepts with very different lifecycles.
- `LabelInboxThread` is artist-wide, while `PendingReleaseComment` is release-specific; the names do not make the split obvious.
- Legacy `LabelOps` naming remains present in code, routes, and some UI copy while product-facing text uses `Zalmanim`.

## Settings / Features Without UI Exposure

| Setting or feature | Classification | Evidence | Notes |
|---|---|---|---|
| `smtp_*`, `smtp_backup_*`, `emails_per_hour` | UI-exposed | `mail_settings.py`, `routes.py`, `apps/client/lib/features/admin/mail_settings_content.dart` | Editable in Settings -> Mail settings. |
| Email template fields and `email_footer` | UI-exposed | `mail_settings.py`, `apps/client/lib/features/admin/tabs/email_templates_tab.dart` | Editable in Settings -> Email templates. |
| Artist minisite settings in `Artist.extra_json` such as `minisite_theme`, `minisite_is_public`, gallery ids | UI-exposed | artist dashboard page, artist profile update route | Exposed in artist portal profile/minisite sections. |
| Release minisite settings in `Release.minisite_json` and `Release.minisite_is_public` | UI-exposed | admin release-links UI and release routes | Exposed in admin release management. |
| `api_docs_enabled`, `cors_allowed_origins`, `trusted_hosts`, OAuth/connector env secrets | Internal-only | `core/config.py`, `main.py` | Operational/runtime config, not intended for admin UI. |
| `demo_submission_token` | No UI, persisted | `core/config.py`, public demo routes | Shared-secret guard for demo intake exists only in env/config. |
| `oauth_success_redirect`, `password_reset_base_url`, `public_demo_allowed_origins` | No UI, persisted | `core/config.py` | Integration/runtime behavior controlled outside the product UI. |
| `AutomationTask` processing | Write-only / dead `Needs validation` | `models.py`, artist dashboard UI, `worker.py` | Persisted task model exists, but analyzed worker does not execute task rows. |

## Validation Priorities

- Confirm whether `AutomationTask` should still be documented as active product behavior.
- Confirm the intended meaning of `processed` for pending releases.
- Confirm whether partial campaign success needs a separate state or dashboard presentation.
- Confirm manager-vs-admin UI expectations.

## Code References

- `apps/server/app/core/config.py` - env/runtime settings surface
- `apps/server/app/main.py` - settings-driven runtime behavior
- `apps/server/app/models/models.py` - `MailSettings`, `AutomationTask`, release/minisite fields
- `apps/server/app/services/mail_settings.py` - persisted settings reads/writes
- `apps/server/app/api/routes.py` - settings endpoints and release/pending-release behavior
- `apps/server/worker.py` - actual automated processing surface
- `apps/client/lib/features/admin/mail_settings_content.dart` - mail settings UI exposure
- `apps/client/lib/features/admin/tabs/email_templates_tab.dart` - template/footer UI exposure
- `apps/artist_portal/lib/features/dashboard/artist_dashboard_page.dart` - artist minisite/profile exposure
