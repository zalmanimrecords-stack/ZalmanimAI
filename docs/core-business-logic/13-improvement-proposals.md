# Improvement Proposals

**Last updated:** 2026-05-27

**Scope analyzed:** Current server architecture, worker behavior, integrations, and persisted workflow structures

**Confidence level:** Medium

---

## Proposals

| Proposal title | Category | Current evidence | Impact | Scope | Suggested approach | Priority | Risk level | Confidence | Validation plan |
|----------------|----------|------------------|--------|-------|--------------------|----------|------------|------------|-----------------|
| Extract release-intake workflow services | Architecture | Demo approval extracted to `demo_service.py`; pending-release and catalog still in `routes.py` | Reduces regression risk | `demo_service.py`, `routes.py`, `pending_release_helpers.py` | Continue pending-release and catalog extraction | P1 | Medium | High | Service tests per domain |
| Add campaign reconciliation for partial success | Architecture | **Implemented 2026-05-27**: `partial` status, per-target deliveries, `retry-failed` | Operator clarity | `campaign_send.py`, `campaign_routes.py` | Monitor production partial campaigns | P1 | Low | High | `tests/test_campaign_partial_success.py` |
| Split mail transport settings from content templates | Architecture | **Implemented 2026-05-27**: `mail_template_settings` table + migration from `mail_settings` | Cleaner boundaries | `mail_template_settings.py`, `mail_settings.py` | Optionally drop legacy template columns from `mail_settings` after stable deploy | P1 | Low | Medium | Verify template save/load in admin UI |
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
