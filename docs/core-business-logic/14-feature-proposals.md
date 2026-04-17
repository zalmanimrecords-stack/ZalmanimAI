# Feature Proposals

**Last updated:** 2026-04-17

**Scope analyzed:** Existing business entities, gaps in current flows, and current worker/integration capabilities

**Confidence level:** Medium

---

| Feature title | Problem/opportunity | Target actors | Domain fit | Reused components | Required changes | Priority | Risks/constraints | Confidence | Validation plan |
|-------|---------|---------|---------|---------|---------|---------|---------|---------|---------|
| Pending release SLA dashboard | Pending releases already collect timestamps, comments, reminders, and statuses, but there is no explicit urgency/risk view. | Admin, manager | Pending release completion | `PendingRelease`, comments, inbox, reminder endpoints, admin tabs | Add derived aging fields, filtering/sorting, and optional escalation markers. | P1 | Requires agreement on SLA definitions. | High | Track time-to-process before/after introducing dashboard. |
| Campaign delivery reconciliation view | Campaigns keep per-target delivery records, but aggregate failure hides actionable retry context. | Admin | Outbound campaigns | `CampaignDelivery`, campaign routes, worker | Add UI/API to inspect failed targets and retry specific ones. | P1 | Must avoid duplicate posts on targets that already succeeded. | Medium | Test with mixed-success campaigns and confirm no duplicate success targets are retried. |
| Release-link review queue prioritization | Link candidates already have confidence and review status, but there is no explicit queue prioritization feature surfaced in the analyzed docs/code. | Admin | Release enrichment | `ReleaseLinkCandidate`, scan summaries, release admin routes | Add queue endpoints/UI sorted by confidence, recency, and unresolved release state. | P2 | Depends on admin workflow demand. | High | Measure approval throughput and unresolved-link counts. |
| Artist-facing progress visibility | Artists can submit demos and pending-release data, but they do not appear to have a unified "where is my release?" status timeline. | Artist | Intake and release preparation | `DemoSubmission`, `CampaignRequest`, `PendingRelease`, inbox | Expose consolidated read-only status timeline in artist portal. | P1 | Requires careful wording so internal states map cleanly to artist language. | Medium | Pilot with internal artists and track support questions. |
| Integration readiness panel | Integration configuration is hidden in env/config, leaving admins without a simple readiness screen. | Admin | Admin operations and outbound communications | `Settings`, connector routes, config flags | Show redacted configured/not configured status per SMTP, OAuth, Mailchimp, and WordPress dependency. | P2 | Must avoid exposing secrets. | Medium | Confirm setup time and support tickets decline after adding visibility. |

## Code References

- `apps/server/app/models/models.py` - reusable entities and persisted signals
- `apps/server/app/api/routes.py` - pending release and release admin surfaces
- `apps/server/app/api/campaign_routes.py` - campaign API surface
- `apps/server/app/services/campaign_send.py` - existing delivery result model
- `apps/server/app/services/release_link_discovery.py` - link candidate review data
- `apps/client/lib/features/admin/tabs/pending_releases_tab.dart` - current pending release UI surface
- `apps/client/lib/features/admin/tabs/settings_tab.dart` - admin operations surface
