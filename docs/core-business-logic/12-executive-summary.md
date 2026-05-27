# Executive Summary

**Last updated:** 2026-05-27

**Scope analyzed:** Full repo with business emphasis on `apps/server/app`, worker automation, and matching admin/artist UI surfaces

**Confidence level:** High

---

## System Purpose

The implemented product is a label-operations platform for Zalmanim that combines artist onboarding, demo review, release-preparation workflows, release enrichment, and outbound publishing.

## Core Capabilities

- collect demos from public forms and artist-authenticated users
- review demos and convert approved work into structured pending releases
- let artists complete release information and exchange follow-up comments with the label
- manage releases, streaming links, cover artwork, and public minisites
- create and schedule cross-channel campaigns
- manage operational email settings, templates, inbox replies, logs, and backups

## Major Domains

- Artist identity and access
- Demo intake and review
- Pending release completion
- Release catalog and enrichment
- Campaign delivery
- Operational communications

## Major Business Risks

- The largest business workflows remain concentrated in `routes.py`, increasing drift and regression risk.
- Approval and onboarding flows often commit state before attempting email delivery, so artist access to the next step can fail silently from a workflow perspective.
- Campaign aggregate status collapses partial success into `failed`, which may hide useful nuance for operators.
- The system uses multiple parallel communication and identity models (`Artist` vs `User`, inbox vs pending-release comments), which raises mental overhead.

## Complexity Hotspots

- `apps/server/app/api/routes.py`
- `apps/server/app/api/pending_release_helpers.py`
- `apps/server/app/services/release_link_discovery.py`
- `apps/server/app/services/campaign_send.py`

## Documentation Confidence Summary

- High confidence on current domains, entities, route entry points, worker behavior, and explicit status strings
- Medium confidence on a few lifecycle semantics where names exist without centralized transition policy
- Open validations remain around `AutomationTask`, manager UX, and partial campaign failure handling

## Prioritized Recommendations

- `P0` ~~Move demo approval into domain services~~ — **Done** (`demo_service.py`, workflow email, resend).
- `P1` ~~Campaign partial success + retry~~ — **Done** (`partial` status, `retry-failed` endpoint, admin UI).
- `P1` ~~Separate SMTP from templates~~ — **Done** (`mail_template_settings` table + migration).
- `P1` ~~Manager permission alignment~~ — **Partially done** (campaigns + client gating; extend to more routes).
- `P1` Clarify and document the intended split between artist-wide inbox conversations and pending-release comments.
- `P4` Further `routes.py` slimming (demos, artists, public minisite HTML).
- `P3` done: release/catalog/settings routers, permission alignment for managers.
- `P4` done: demo/artist/public/artist-portal routers extracted; `routes.py` holds auth, users, dashboard, OAuth, and startup `init_db()`.

See also [`docs/REMEDIATION-CHANGELOG.md`](../REMEDIATION-CHANGELOG.md) and [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md).

## Code References

- `apps/server/app/api/routes.py` - primary business-flow concentration
- `apps/server/app/api/campaign_routes.py` - campaign surface
- `apps/server/app/api/campaign_request_routes.py` - request-approval flow
- `apps/server/app/models/models.py` - domain entity inventory
- `apps/server/app/services/campaign_send.py` - aggregate delivery outcome
- `apps/server/app/services/release_link_discovery.py` - enrichment complexity
- `apps/server/app/services/mail_settings.py` - settings/template concentration
- `apps/server/worker.py` - automated execution scope
