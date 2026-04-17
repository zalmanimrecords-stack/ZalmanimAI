# Core Domains

**Last updated:** 2026-04-17

**Scope analyzed:** `apps/server/app`, `apps/server/worker.py`, selected admin UI files in `apps/client/lib`

**Confidence level:** High

---

## Artist Identity And Access

| Field | Content |
|-------|---------|
| Purpose | Authenticate admins/managers and artists, bind artist-portal access to artist records, and enforce route separation. |
| Main modules | `app/api/deps.py`, `app/services/auth.py`, `app/api/routes.py`, `app/models/models.py` |
| Responsibilities | Login, password reset, portal invite flows, OAuth identity linking, permission exposure, inactive-user blocking. |
| Dependencies | Mail settings, email service, artist records, user records. |
| Boundaries | Does not own release or campaign business decisions. |
| Cohesion | Mixed. Auth helpers are centralized, but invite/reset flows are embedded in `routes.py`. |

## Demo Intake And Review

| Field | Content |
|-------|---------|
| Purpose | Accept demo submissions, persist review status, and convert approved demos into downstream work. |
| Main modules | `app/api/routes.py`, `app/api/mail_templates.py`, `app/models/models.py` |
| Responsibilities | Public demo submission, artist demo uploads, approval/rejection state changes, approval email customization, demo-to-artist linking. |
| Dependencies | Mailing lists, artists, pending releases, SMTP delivery. |
| Boundaries | Does not publish releases or campaigns directly. |
| Cohesion | Fragmented. Business rules are mostly route-local, with template helpers split out. |

## Pending Release Completion

| Field | Content |
|-------|---------|
| Purpose | Collect full release data after an item is approved for release and support artist-label back-and-forth. |
| Main modules | `app/api/routes.py`, `app/api/pending_release_helpers.py`, `app/api/inbox_routes.py`, `app/models/models.py` |
| Responsibilities | Tokenized form access, reference image handling, comments, reminders, archive/delete, inbox seeding. |
| Dependencies | Demo review, campaign requests, artist records, email delivery. |
| Boundaries | Does not distribute releases externally. |
| Cohesion | Mixed. Helpers exist, but the lifecycle still spans multiple route handlers. |

## Release Catalog And Enrichment

| Field | Content |
|-------|---------|
| Purpose | Maintain label release records, import catalog metadata, discover platform links, and manage minisites and cover art. |
| Main modules | `app/api/routes.py`, `app/services/release_link_discovery.py`, `app/models/models.py` |
| Responsibilities | Release CRUD, catalog import, artist matching, link candidate review, periodic scan creation, minisite updates. |
| Dependencies | Artists, worker polling, external music/search sites. |
| Boundaries | Does not own campaign delivery. |
| Cohesion | Mixed but stronger than intake flows because link discovery logic is extracted into a service. |

## Outbound Campaigns And Communications

| Field | Content |
|-------|---------|
| Purpose | Send outbound content or messages to artists and channels. |
| Main modules | `app/api/campaign_routes.py`, `app/services/campaign_service.py`, `app/services/campaign_send.py`, `app/services/mail_settings.py`, `app/api/inbox_routes.py` |
| Responsibilities | Campaign drafting/scheduling, per-target deliveries, SMTP config/templates, inbox reply emails, approval emails. |
| Dependencies | Social connections, hub connectors, Mailchimp, WordPress, worker polling, Redis-backed email rate limiting. |
| Boundaries | Does not own artist or release creation rules except where campaign approval opens a pending-release form. |
| Cohesion | Split between well-factored campaign services and route-local email workflows. |

## Admin Operations And Observability

| Field | Content |
|-------|---------|
| Purpose | Provide logs, DB inspection, backup/restore, and light agent-planning endpoints. |
| Main modules | `app/api/routes.py`, `app/services/system_log.py`, `app/services/backup_service.py` |
| Responsibilities | System settings read/update, log retrieval, backup export/import, dashboard stats. |
| Dependencies | Every other domain writes data consumed here. |
| Boundaries | Mostly operational; limited direct business ownership. |
| Cohesion | Mixed; operational concerns are centralized in routes. |

## Cross-Domain Boundary Notes

- `DemoSubmission`, `CampaignRequest`, and `PendingRelease` form a shared intake-to-release pipeline.
- `Campaign` is separate from `CampaignRequest`: one is outbound delivery, the other is artist-originated release interest.
- `LabelInboxThread` is adjacent to pending releases but not formally linked; integration happens through helper-created messages.

## Code References

- `apps/server/app/api/deps.py` - role resolution and LM-vs-artist route separation
- `apps/server/app/api/routes.py` - demo, pending release, release, settings, and backup flows
- `apps/server/app/api/campaign_routes.py` - campaign administration
- `apps/server/app/api/campaign_request_routes.py` - artist-to-label request domain
- `apps/server/app/api/inbox_routes.py` - inbox communication domain
- `apps/server/app/models/models.py` - entity ownership across domains
- `apps/server/app/services/campaign_service.py` - campaign state operations
- `apps/server/app/services/campaign_send.py` - outbound campaign execution
- `apps/server/app/services/release_link_discovery.py` - release enrichment domain
