# Core Domains

**Last updated:** 2026-04-18

**Scope analyzed:** `apps/server/app/api`, `apps/server/app/services`, `apps/server/app/models`, and matching Flutter surfaces

**Confidence level:** High

---

## Artist Identity And Access

| Field | Content |
|-------|---------|
| Purpose | Manage login, role resolution, artist self-service profile data, and portal onboarding/reset flows. |
| Main modules | `app/services/auth.py`, `app/api/deps.py`, `app/api/routes.py`, `app/models/models.py` |
| Responsibilities | JWT creation/validation, artist-vs-LM separation, password reset, registration completion, profile updates, user/artist linking |
| Dependencies | Email templates, password-reset tokens, artist registration tokens |
| Boundaries | Does not own release-link discovery or campaign delivery |
| Cohesion | Mixed; auth rules are centralized, but onboarding and profile rules are spread across `routes.py` |

## Demo Intake And Review

| Field | Content |
|-------|---------|
| Purpose | Receive demos from public or artist users, review them, and convert approved submissions into next-step release work. |
| Main modules | `app/api/routes.py`, `app/api/mail_templates.py`, `app/models/models.py` |
| Responsibilities | Demo submission validation, file handling, review statuses, approval/rejection emails, mailing-list updates, artist creation/linking |
| Dependencies | `MailSettings`, `Artist`, `PendingRelease`, `MailingList`, `MailingSubscriber` |
| Boundaries | Does not send social/Mailchimp/WordPress campaigns |
| Cohesion | Fragmented; business flow is real but concentrated in long route handlers |

## Pending Release Completion And Follow-Up

| Field | Content |
|-------|---------|
| Purpose | Collect artist and release metadata after approval, support conversation around missing assets, and let admin process the item. |
| Main modules | `app/api/routes.py`, `app/api/pending_release_helpers.py`, `app/api/inbox_routes.py` |
| Responsibilities | Token validation, pending-release submission, comments, image-option management, reminders, archive/delete actions |
| Dependencies | `PendingRelease`, `PendingReleaseToken`, `PendingReleaseComment`, `LabelInboxThread`, SMTP email |
| Boundaries | Does not itself create outbound campaigns; it prepares release data |
| Cohesion | Mixed; helper functions centralize serialization and notification rules, but most mutations remain in `routes.py` |

## Release Catalog, Enrichment, And Minisites

| Field | Content |
|-------|---------|
| Purpose | Maintain release records, import catalog metadata, discover platform links, manage cover art, and expose release minisites. |
| Main modules | `app/api/routes.py`, `app/services/release_link_discovery.py`, `app/models/models.py` |
| Responsibilities | Catalog import, artist matching, scan-run queuing, candidate approval/rejection, cover download, minisite publication |
| Dependencies | `Release`, `CatalogTrack`, `ReleaseLinkCandidate`, `ReleaseLinkScanRun`, file storage |
| Boundaries | Does not own artist authentication or mail transport settings |
| Cohesion | Moderate; discovery logic is well grouped in one service, while catalog/minisite flows remain route-heavy |

## Campaign Orchestration And Delivery

| Field | Content |
|-------|---------|
| Purpose | Create unified outbound campaigns and deliver them through configured channel targets. |
| Main modules | `app/api/campaign_routes.py`, `app/services/campaign_service.py`, `app/services/campaign_send.py`, `worker.py` |
| Responsibilities | Draft creation, target replacement, scheduling, worker claiming, per-target delivery logging, sent/failed outcome |
| Dependencies | `Campaign`, `CampaignTarget`, `CampaignDelivery`, `HubConnector`, `SocialConnection` |
| Boundaries | Does not decide demo approval or pending-release completion |
| Cohesion | Mostly cohesive; CRUD/state changes and send execution are split cleanly between service modules |

## Operational Communications And Admin Tooling

| Field | Content |
|-------|---------|
| Purpose | Support admin-side email settings, templates, logs, backup/restore, and inbox responses. |
| Main modules | `app/services/mail_settings.py`, `app/services/email_service.py`, `app/api/inbox_routes.py`, `app/api/routes.py` |
| Responsibilities | Mail configuration overrides, test sends, template persistence, log retrieval, backup export/restore |
| Dependencies | `MailSettings`, `SystemLog`, `PasswordResetToken`, `LabelInboxMessage` |
| Boundaries | These modules support the business workflow but are not the main release-intake domain |
| Cohesion | Mixed; settings and templates are separated in the UI but persisted in one table and updated through one route family |

## Code References

- `apps/server/app/api/routes.py` - demo, artist, release, settings, backup, and pending-release flows
- `apps/server/app/api/campaign_routes.py` - campaign domain surface
- `apps/server/app/api/campaign_request_routes.py` - artist request intake and approval path
- `apps/server/app/api/inbox_routes.py` - inbox workflow
- `apps/server/app/api/pending_release_helpers.py` - pending-release helpers
- `apps/server/app/services/auth.py` - role permissions and token issuance
- `apps/server/app/services/campaign_service.py` - campaign lifecycle operations
- `apps/server/app/services/campaign_send.py` - delivery execution
- `apps/server/app/services/release_link_discovery.py` - enrichment logic
- `apps/server/app/services/mail_settings.py` - mail settings persistence
- `apps/server/app/models/models.py` - entity boundaries and relationships
