# State Machines And Lifecycles

**Last updated:** 2026-04-18

**Scope analyzed:** Persisted status fields and the route/service code that mutates them

**Confidence level:** Medium

---

## `DemoSubmission`

- States: `demo`, `in_review`, `approved`, `rejected`, `pending_release`
- Transitions:
  - `demo -> in_review`
  - `demo|in_review -> approved`
  - `demo|in_review -> rejected`
  - `approved -> pending_release` `Assumption` based on workflow naming and admin surfaces
- Triggers: admin review/update routes
- Invalid transitions: `Unclear from code`; there is no centralized transition map, only route-level status writes
- Business meaning:
  - `demo`: newly submitted
  - `in_review`: under label consideration
  - `approved`: accepted and eligible for follow-up
  - `rejected`: not moving forward
  - `pending_release`: accepted and moved into release-preparation work
- Explicit vs implicit lifecycle: explicit status strings, implicit allowed transitions

## `CampaignRequest`

- States: `pending`, `approved`, `rejected`
- Transitions:
  - `pending -> approved`
  - `pending -> rejected`
- Triggers: admin patch route
- Invalid transitions: `Unclear from code`; no explicit rejection of `approved -> rejected` rewrites, but only new approval triggers token/email side effect
- Business meaning:
  - `pending`: awaiting label review
  - `approved`: artist should supply fuller release details
  - `rejected`: request declined
- Explicit vs implicit lifecycle: explicit status, implicit transition policy

## `PendingRelease`

- States: `pending`, `processed`
- Transitions:
  - `pending -> processed`
  - `processed -> pending` `Unclear from code` whether any route restores this state
- Triggers: admin processing/archive flows and related routes
- Invalid transitions: not centralized
- Business meaning:
  - `pending`: artist/release information still under preparation or review
  - `processed`: label has completed its current handling of the item
- Explicit vs implicit lifecycle: explicit status with broad implicit meaning

## `Campaign`

- States: `draft`, `scheduled`, `sending`, `sent`, `failed`
- Transitions:
  - `draft -> scheduled`
  - `scheduled -> draft` via cancel
  - `scheduled -> sending` via worker claim
  - `sending -> sent`
  - `sending -> failed`
- Triggers: admin schedule/cancel actions and worker execution
- Invalid transitions:
  - non-`draft` campaigns cannot be scheduled
  - only `draft` or `scheduled` campaigns are editable
  - only `draft` or `failed` campaigns are deletable
- Business meaning:
  - `draft`: editable but not queued
  - `scheduled`: queued for future or immediate worker send
  - `sending`: worker owns delivery
  - `sent`: every target succeeded
  - `failed`: at least one target failed
- Explicit vs implicit lifecycle: strongly explicit and comparatively well-bounded

## `ReleaseLinkScanRun`

- States: `queued`, `running`, `completed`, `failed`
- Transitions:
  - `queued -> running`
  - `running -> completed`
  - `running -> failed`
- Triggers: worker processing and exception handling
- Invalid transitions: completed runs are not reused
- Business meaning: background enrichment progress for one release scan request

## `ReleaseLinkCandidate`

- States: `pending_review`, `auto_rejected`, `approved`, `rejected`
- Transitions:
  - new candidate -> `pending_review` when confidence is high enough
  - new candidate -> `auto_rejected` when confidence is below review threshold
  - `pending_review -> approved`
  - `pending_review|approved -> rejected`
- Triggers: discovery scoring and admin review
- Invalid transitions: `Unclear from code`; there is no explicit restore from `rejected`
- Business meaning:
  - `pending_review`: admin should inspect
  - `auto_rejected`: hidden by low confidence
  - `approved`: active chosen link for that platform
  - `rejected`: manually dismissed

## Token Lifecycles

### `PendingReleaseToken`

- States: active, expired, used
- Transitions:
  - created active
  - active -> expired when `expires_at <= now`
  - active -> used when `used_at` is set `Needs validation`; some flows resolve tokens without immediately consuming them

### `ArtistRegistrationToken`

- States: active, expired, used
- Transitions: created, completed at registration, or naturally expired

### `PasswordResetToken`

- States: active, expired
- Transitions: active on issuance, invalid after expiry; explicit used-state field is absent

## Artist Profile / Minisite Lifecycle

- `Artist.extra_json` stores evolving self-service state such as `artist_brand`, social links, `minisite_theme`, `minisite_is_public`, `profile_image_media_id`, and gallery ids.
- `Release.minisite_json` stores release-specific public-page details.
- `Unclear from code`: the product boundary between artist minisite state in `Artist.extra_json` and release minisite state in `Release.minisite_*` is not fully unified.

## Code References

- `apps/server/app/models/models.py` - persisted status/token fields
- `apps/server/app/api/routes.py` - demo, pending-release, release, and token lifecycle mutations
- `apps/server/app/api/campaign_request_routes.py` - `CampaignRequest` transitions
- `apps/server/app/services/campaign_service.py` - `Campaign` transitions
- `apps/server/app/services/campaign_send.py` - send completion/failure
- `apps/server/app/services/release_link_discovery.py` - scan-run and candidate transitions
