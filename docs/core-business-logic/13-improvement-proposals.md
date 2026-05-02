# Improvement Proposals

**Last updated:** 2026-04-18

**Scope analyzed:** Current server architecture, worker behavior, integrations, and persisted workflow structures

**Confidence level:** Medium

---

## Proposals

| Proposal title | Category | Current evidence | Impact | Scope | Suggested approach | Priority | Risk level | Confidence | Validation plan |
|----------------|----------|------------------|--------|-------|--------------------|----------|------------|------------|-----------------|
| Extract release-intake workflow services | Architecture | Demo approval, pending-release creation, comments, reminders, and archive/process actions are concentrated in `routes.py` with helper spillover | Reduces regression risk and makes transition rules easier to test | `app/api/routes.py`, `pending_release_helpers.py`, related tests | Create domain services for demo approval, pending-release mutation, and reminder/comment notifications; keep routes thin | P0 | Medium | High | Add service-level tests for status transitions and side effects |
| Add campaign reconciliation for partial success | Architecture | `campaign_send.py` marks campaign failed when any target fails, while some targets may already have published | Improves operator clarity and retry behavior | `campaign_service.py`, `campaign_send.py`, admin campaign UI | Introduce a partial-success state or derived summary and allow retrying failed targets without recreating successful deliveries | P1 | Medium | High | Simulate mixed target outcomes and verify UI/API reporting |
| Split mail transport settings from content templates | Architecture | `MailSettings` stores SMTP fields, backup SMTP, rate limit, footer, and all template bodies in one row | Simplifies ownership boundaries and reduces accidental coupling | `models.py`, `mail_settings.py`, settings/template routes and UI | Separate transport config from template content storage while keeping API compatibility during migration | P1 | Medium | Medium | Migrate one non-critical template first in staging and verify unchanged UI behavior |
| Harden pending-release schema for image and notification state | Architecture | `image_options`, `selected_image_id`, and `notifications_muted` live inside free-form JSON | Improves data integrity and reduces hidden bugs | `PendingRelease`, `pending_release_helpers.py`, pending-release routes | Move high-value fields to typed columns or a child table while leaving lower-value free-form metadata in JSON | P1 | Medium | Medium | Compare current JSON-derived API outputs before and after migration |
| Add controlled retry/backoff for release-link enrichment failures | Performance | Link discovery depends on many brittle external sources; periodic rescans are cooldown-based only | Reduces unnecessary repeated failures and supports observability | `release_link_discovery.py`, `worker.py` | Track failure classes and rescan backoff per platform/run instead of only release-wide cooldown | P2 | Low | Medium | Measure failed-run volume before/after backoff logic |
| Strengthen operational alerts around email-dependent approvals | Security | Critical approvals can succeed even when email delivery fails, leaving artists without next-step access | Lowers risk of silent workflow stalls and support load | approval routes, email service, admin logs/inbox | Promote send failures into more visible admin logs/inbox alerts and optionally expose resend actions inline | P1 | Low | High | Force SMTP failure in staging and confirm visible operator alert path |

## Code References

- `apps/server/app/api/routes.py` - multi-domain route concentration and pending-release logic
- `apps/server/app/api/campaign_routes.py` - campaign route surface
- `apps/server/app/services/campaign_service.py` - campaign state operations
- `apps/server/app/services/campaign_send.py` - target-loop delivery logic
- `apps/server/app/services/mail_settings.py` - mail config/template coupling
- `apps/server/app/services/release_link_discovery.py` - enrichment retries and heuristics
- `apps/server/app/models/models.py` - `MailSettings` and `PendingRelease` storage shapes
