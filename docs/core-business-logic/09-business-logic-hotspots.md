# Business Logic Hotspots

**Last updated:** 2026-04-17

**Scope analyzed:** Server routes/services plus selected admin UI integration points

**Confidence level:** High

---

## `apps/server/app/api/routes.py`

- Concentrates demo intake/review, artist management, pending release flows, release management, reports, settings, logs, and backup/restore.
- Risk: mixes business rules, persistence, side effects, and response shaping.

## Intake Pipeline Split Across Multiple Concepts

- Hotspot entities: `DemoSubmission`, `CampaignRequest`, `PendingRelease`, `LabelInboxThread`.
- Risk: one business pipeline is represented by several adjacent but separately implemented models.

## Raw String Status Fields

- Affected entities: campaigns, campaign requests, demos, pending releases, link candidates, scan runs, social connections.
- Risk: transition validation is distributed instead of centralized.

## Mail Configuration And Template Surface

- Hotspot modules: `MailSettings`, `mail_settings.py`, settings routes, email template helpers, admin settings UI.
- Risk: one single-row persistence model carries operational SMTP config and multiple business templates.

## Campaign Delivery Aggregation

- Hotspot modules: `campaign_service.py`, `campaign_send.py`, `worker.py`.
- Risk: partial target success still yields failed aggregate campaign state.

## Release Link Discovery Heuristics

- Hotspot module: `release_link_discovery.py`.
- Risk: heuristic confidence scoring determines manual review volume and approved link quality.

## Code References

- `apps/server/app/api/routes.py` - primary hotspot
- `apps/server/app/api/campaign_request_routes.py` - request-to-release coupling
- `apps/server/app/api/inbox_routes.py` - communication logic coupled to release intake
- `apps/server/app/models/models.py` - status-string spread and cross-domain entities
- `apps/server/app/services/mail_settings.py` - settings/template concentration
- `apps/server/app/services/campaign_send.py` - delivery aggregation logic
- `apps/server/app/services/release_link_discovery.py` - heuristic enrichment hotspot
- `apps/client/lib/features/admin/tabs/settings_tab.dart` - UI surface that can drift from server permissions/features
