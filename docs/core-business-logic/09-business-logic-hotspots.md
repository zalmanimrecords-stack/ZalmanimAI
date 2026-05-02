# Business Logic Hotspots

**Last updated:** 2026-04-18

**Scope analyzed:** Server modules with concentrated branching, cross-domain writes, or repeated business rules

**Confidence level:** High

---

## `apps/server/app/api/routes.py`

- Concentrated logic: demo intake/review, artist onboarding, pending releases, releases, reports, settings, backup/restore, and release minisites all live here.
- Mixed concerns: request validation, DB mutation, email sending, file handling, and workflow transitions happen in the same module.
- Architectural risk: high change surface and rule drift because multiple domains share one file.
- Refactor target: split by domain use case, especially demo approval, pending-release processing, and release enrichment orchestration.

## Pending-Release Domain Across `routes.py` And `pending_release_helpers.py`

- Concentrated logic: token validation, serialization, comments, notifications, image-option management, and reminders.
- Mixed concerns: JSON-field shaping, mail notifications, file lifecycle, and business status changes.
- Risk: much of the core state is stored in ad-hoc JSON keys like `notifications_muted`, `image_options`, and `selected_image_id`, which reduces schema-level guarantees.

## Release Enrichment In `release_link_discovery.py`

- Concentrated logic: search adapters, confidence scoring, candidate persistence, rescan policy, cover download, and platform-link approval.
- Strength: most enrichment rules are centralized.
- Risk: large integration surface and heuristic scoring create brittle behavior that is hard to validate exhaustively.

## Campaign Execution Split Between `campaign_service.py`, `campaign_send.py`, And `worker.py`

- Concentrated logic: status lifecycle, worker claim semantics, target delivery, and aggregate campaign outcome.
- Risk: external side effects happen inside a loop with no per-target retry policy or reconciliation layer.
- Duplication/drift: route-level rules and service-level state checks are cleaner here than elsewhere, but business meaning of `failed` still compresses partial success into a single state.

## Dual Conversation Models: `PendingReleaseComment` And Inbox Threads

- Mixed concerns: release-specific collaboration and generic artist-label inbox messaging are stored separately.
- Risk: admin context can fragment between pending-release comments and inbox messages because the same artist interaction may touch both systems.
- `Needs validation`: whether both channels are intentionally separate product concepts.

## Identity Duality: `Artist` Vs `User(role="artist")`

- Concentrated logic: direct artist portal tokens use `Artist`, while some flows create `User` rows linked to artists.
- Risk: authorization and lifecycle rules must account for two identity shapes.
- Refactor target: define one canonical artist-auth model or explicitly document the split.

## Settings Concentration In `MailSettings`

- Mixed concerns: SMTP transport settings, template content, and global footer live in one persisted row.
- Risk: operational configuration and content-authoring concerns are coupled in one table and update route.

## Catalog And Release Matching Logic In `routes.py`

- Concentrated logic: import, dedupe, artist matching, placeholder release creation, and merge flows.
- Risk: title/name-based matching is business-important but not isolated into a dedicated service, making future changes harder to test.

## Code References

- `apps/server/app/api/routes.py` - broad multi-domain hotspot
- `apps/server/app/api/pending_release_helpers.py` - pending-release helper concentration
- `apps/server/app/services/release_link_discovery.py` - release enrichment hotspot
- `apps/server/app/services/campaign_service.py` - campaign lifecycle hotspot
- `apps/server/app/services/campaign_send.py` - external send hotspot
- `apps/server/worker.py` - asynchronous execution hotspot
- `apps/server/app/models/models.py` - identity and conversation model split
