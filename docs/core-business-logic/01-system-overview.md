# System Overview

**Last updated:** 2026-04-18

**Scope analyzed:** Full repo with emphasis on `apps/server/app`, `apps/server/worker.py`, `apps/client/lib`, and `apps/artist_portal/lib`

**Confidence level:** High

---

## What The System Does

The implemented system is a label-operations platform for Zalmanim. From code, it supports:

- admin and artist authentication with separate access boundaries
- public and artist-authenticated demo intake
- admin review of demos and conversion of approved work into artist-release follow-up
- artist completion of release metadata through tokenized public forms and logged-in portal flows
- release enrichment through platform-link discovery, cover-art download, and minisite publishing
- outbound communication through SMTP-backed email, admin inbox replies, and unified campaigns for social, Mailchimp, and WordPress
- operational controls such as logs, backups, mail settings, and simple database inspection

## Main Actors

- `admin`: full label-management access, including users, settings, backups, logs, artists, releases, campaigns, demos, inbox, and restore.
- `manager`: partial LM access; can read and write artists, releases, and campaigns, but cannot perform admin-only actions guarded by `require_admin`.
- `artist`: portal user backed primarily by `Artist` records and limited to self-service flows.
- Public submitter: unauthenticated caller for demo submission, demo confirmation, pending-release completion, registration, and release minisite pages.
- Background worker: asynchronous executor for scheduled campaigns and release-link scan runs.

## Main Business Domains

- Artist identity and access
- Demo intake and review
- Pending release completion and follow-up
- Release catalog, enrichment, and minisites
- Campaign orchestration and delivery
- Operational communications and admin tooling

## Where Core Business Logic Lives

- `apps/server/app/api/routes.py`
- `apps/server/app/api/campaign_routes.py`
- `apps/server/app/api/campaign_request_routes.py`
- `apps/server/app/api/inbox_routes.py`
- `apps/server/app/api/pending_release_helpers.py`
- `apps/server/app/services/campaign_service.py`
- `apps/server/app/services/campaign_send.py`
- `apps/server/app/services/release_link_discovery.py`
- `apps/server/app/services/mail_settings.py`
- `apps/server/app/models/models.py`

## Layer Split

### Core Business Logic

- role restrictions, status transitions, approval flows, candidate confidence thresholds, inbox reply semantics, reminder behavior, and release/minisite visibility rules

### Application Orchestration

- route handlers that load rows, validate ownership, call helper services, persist changes, and trigger email or background side effects

### Infrastructure And Technical Utilities

- DB sessions, JWT decoding, SMTP transport, Redis-backed rate limiting, OAuth helpers, connector HTTP calls, token encryption, and worker heartbeat writes

### UI And Presentation

- Flutter admin and artist-portal pages that expose forms, tabs, previews, filters, and payload construction, but generally defer policy enforcement to the API

## Architectural Observations

- The server is the source of truth for business behavior.
- `routes.py` is still the dominant hotspot and mixes business rules with persistence and transport logic.
- The worker automates only two domains in the analyzed code: campaign sending and release-link scanning.
- Both admin and artist UIs expose meaningful workflow controls, but the business invariants remain server-enforced.

## Code References

- `apps/server/app/main.py` - application bootstrap, runtime validation, middleware, router mounting
- `apps/server/app/api/routes.py` - primary business flows and most state transitions
- `apps/server/app/api/campaign_routes.py` - campaign CRUD and scheduling surface
- `apps/server/app/api/campaign_request_routes.py` - campaign-request approval to pending-release token flow
- `apps/server/app/api/inbox_routes.py` - inbox thread behavior and reply side effects
- `apps/server/app/api/pending_release_helpers.py` - pending-release serialization, token validation, notification rules
- `apps/server/app/models/models.py` - entities, relationships, persisted state fields
- `apps/server/app/services/campaign_send.py` - scheduled campaign execution rules
- `apps/server/app/services/release_link_discovery.py` - release enrichment rules and review thresholds
- `apps/server/worker.py` - background automation boundaries
- `apps/client/lib/features/admin/tabs/settings_tab.dart` - admin operational UI surface
- `apps/artist_portal/lib/features/dashboard/artist_dashboard_page.dart` - artist self-service workflow surface
