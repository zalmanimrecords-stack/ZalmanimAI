# Executive Summary

**Last updated:** 2026-04-18

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

- `P0` Move demo approval and pending-release lifecycle logic into dedicated domain services with explicit transition helpers.
- `P1` Introduce clearer campaign reconciliation for partial success, retry, and operator visibility.
- `P1` Clarify and document the intended split between artist-wide inbox conversations and pending-release comments.
- `P1` Separate operational SMTP settings from editable template content at the persistence layer.
- `P2` Align manager-visible UI with actual route enforcement or broaden route support intentionally.

## Code References

- `apps/server/app/api/routes.py` - primary business-flow concentration
- `apps/server/app/api/campaign_routes.py` - campaign surface
- `apps/server/app/api/campaign_request_routes.py` - request-approval flow
- `apps/server/app/models/models.py` - domain entity inventory
- `apps/server/app/services/campaign_send.py` - aggregate delivery outcome
- `apps/server/app/services/release_link_discovery.py` - enrichment complexity
- `apps/server/app/services/mail_settings.py` - settings/template concentration
- `apps/server/worker.py` - automated execution scope
