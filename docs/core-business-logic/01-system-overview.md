# System Overview

**Last updated:** 2026-04-17

**Scope analyzed:** Full repo with emphasis on `apps/server/app`, `apps/server/worker.py`, and relevant admin UI surfaces in `apps/client/lib`

**Confidence level:** High

---

## What the system does

This system operates a label-management workflow for Zalmanim. The implemented behavior covers:

- artist/admin authentication and role separation
- public and artist-authenticated demo intake
- admin review, approval, and rejection of demos
- conversion of approved demos or campaign approvals into `PendingRelease` work items
- artist completion of release details, threaded follow-up, and admin processing
- release storage, release minisite publication, and link discovery across streaming platforms
- outbound communication by SMTP/email, inbox reply emails, and unified campaign delivery to social, Mailchimp, and WordPress

## Main actors

- `admin`: full LM access, including users, artists, releases, campaigns, settings, backup, and logs.
- `manager`: read/write for artists, releases, and campaigns, but no write access to users or settings.
- `artist`: separate portal role backed by `artists` records and limited to self-service flows.
- Public submitter: unauthenticated caller for demo and registration-related public routes.
- Background worker: polls for scheduled campaigns and release-link scan runs.

## Main business domains

- Artist identity and access
- Demo intake and review
- Pending release completion
- Release catalog and enrichment
- Outbound campaigns and communications
- Admin operations and observability

## Where core business logic lives

- `apps/server/app/api/routes.py`
- `apps/server/app/api/campaign_request_routes.py`
- `apps/server/app/api/inbox_routes.py`
- `apps/server/app/services/campaign_service.py`
- `apps/server/app/services/campaign_send.py`
- `apps/server/app/services/release_link_discovery.py`
- `apps/server/app/services/mail_settings.py`
- `apps/server/app/models/models.py`

## Layer split

### Core business logic

- Status transitions such as demo approval, campaign scheduling, pending release processing, release-link candidate approval, and role-based access rules.

### Application orchestration

- Route handlers often load entities, apply rules inline, persist changes, and trigger side effects in one function. This is especially true in `routes.py`.

### Infrastructure and technical utilities

- SMTP delivery, OAuth token handling, HTTP clients, DB session wiring, encryption helpers, and worker heartbeat writes.

### UI and presentation

- Flutter admin tabs expose settings, demo review, inbox, pending releases, and templates, but they do not appear to contain primary business decisions beyond shaping payloads for server routes.

## Architectural observations

- Core business behavior is server-centric.
- The largest hotspot is `apps/server/app/api/routes.py`, which mixes domain decisions, persistence, and side effects.
- The background worker executes only two automated domains in the current code: scheduled campaigns and release-link scanning.

## Code References

- `apps/server/app/main.py` - application bootstrap, middleware, router mounting, runtime validation
- `apps/server/app/api/routes.py` - primary business flows and route-level rules
- `apps/server/app/api/campaign_routes.py` - campaign CRUD and scheduling surface
- `apps/server/app/api/campaign_request_routes.py` - artist request approval to pending-release token flow
- `apps/server/app/api/inbox_routes.py` - inbox threads, admin replies, and email side effects
- `apps/server/app/models/models.py` - business entities and statuses
- `apps/server/app/services/campaign_send.py` - scheduled campaign execution rules
- `apps/server/app/services/release_link_discovery.py` - release enrichment and review thresholds
- `apps/server/worker.py` - polling automation boundaries
- `apps/client/lib/features/admin/tabs/settings_tab.dart` - visible admin settings surface
