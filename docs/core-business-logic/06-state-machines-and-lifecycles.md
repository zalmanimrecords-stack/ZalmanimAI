# State Machines And Lifecycles

**Last updated:** 2026-04-17

**Scope analyzed:** Status-bearing models and route/service transitions in server code

**Confidence level:** Medium

---

## `Campaign`

- States: `draft`, `scheduled`, `sending`, `sent`, `failed`
- Transitions: `draft` -> `scheduled`; `scheduled` -> `draft`; `scheduled` -> `sending`; `sending` -> `sent` or `failed`
- Invalid transitions: non-`draft` campaigns cannot be scheduled; only `draft`/`scheduled` can be updated; only `draft`/`failed` can be deleted
- Business meaning: campaign readiness, execution in progress, and aggregate delivery outcome

## `CampaignRequest`

- States: `pending`, `approved`, `rejected`
- Transitions: `pending` -> `approved` or `rejected`
- Invalid transitions: not strongly centralized; exact post-approval patch rules are `Unclear from code`
- Business meaning: label decision on an artist request

## `DemoSubmission`

- States observed: `demo`, `in_review`, `approved`, `rejected`, `pending_release`
- Transitions: review and approval updates occur in admin routes
- Invalid transitions: status values are validated against a set, but transitions are distributed
- Business meaning: intake and review maturity of submitted music

## `PendingRelease`

- States: `pending`, `processed`
- Transitions: created as `pending`, later moved to `processed`
- Invalid transitions: route-level checks exist but are not centralized
- Business meaning: whether release prep is still waiting on work

## `ReleaseLinkScanRun`

- States: `queued`, `running`, `completed`, `failed`
- Transitions: worker marks runs `running`, then `completed` or `failed`
- Invalid transitions: process function ignores runs outside `queued`/`running`
- Business meaning: background enrichment job progress

## `ReleaseLinkCandidate`

- States: `pending_review`, `approved`, `rejected`, `auto_rejected`
- Transitions: new candidate -> `pending_review` or `auto_rejected`; admin can approve/reject
- Invalid transitions: not fully blocked by a single state machine service
- Business meaning: confidence-ranked review queue for release URLs

## `SocialConnection`

- States observed: `pending`, `connected`
- Transitions: starts pending during OAuth setup and becomes connected when complete
- `Unclear from code`: full disconnect/reconnect lifecycle details without tracing every route branch

## Lifecycle Risks

- Many stateful entities use raw strings rather than enums or dedicated transition services.
- Transition validation is concentrated in routes and helper functions rather than one domain layer.

## Code References

- `apps/server/app/models/models.py` - persisted status fields
- `apps/server/app/api/campaign_routes.py` - campaign transitions
- `apps/server/app/services/campaign_service.py` - campaign transition helpers
- `apps/server/app/services/campaign_send.py` - send-result transitions
- `apps/server/app/api/campaign_request_routes.py` - request approval transitions
- `apps/server/app/services/release_link_discovery.py` - scan and candidate transitions
- `apps/server/app/api/routes.py` - demo and pending release lifecycle handling
