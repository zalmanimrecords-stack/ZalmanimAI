# Business Rules

**Last updated:** 2026-04-17

**Scope analyzed:** Server route handlers, auth/config services, campaign services, release-link discovery service

**Confidence level:** High

---

| Rule name | Description | Code location | Trigger | Outcome | Validations | Edge cases | Confidence | Centralized or duplicated |
|-----------|-------------|---------------|---------|---------|-------------|------------|------------|---------------------------|
| LM routes reject artist tokens | Artist JWTs cannot access LM-only endpoints. | `app/api/deps.py` | Any LM request using `get_current_lm_user` | 403 with fixed detail message | JWT must not have `artist:` subject | Admin/manager inactive users still fail 401 earlier | High | Centralized |
| Admin-only enforcement | Some routes require exact `admin` role, not `manager`. | `app/api/deps.py` and many `require_admin` calls | Protected admin route | 403 `Admin only` | Role string equality | Manager read permissions exist, but write access is still route-specific | High | Centralized guard, distributed usage |
| Campaigns are editable only before send | Only `draft` and sometimes `scheduled` campaigns may be changed; only `draft` may be scheduled. | `app/services/campaign_service.py`, `app/api/campaign_routes.py` | Update, delete, schedule, cancel | Reject invalid mutation | Status checks before mutation | `delete_campaign` allows `failed` deletion but not `scheduled` | High | Centralized |
| Scheduled campaign send is single-claim | Worker claims a scheduled campaign by atomic status update from `scheduled` to `sending`. | `app/services/campaign_service.py` | Worker execution | Prevent duplicate send claim | SQL `update ... where status='scheduled'` | Assumption: DB isolation is sufficient for single worker/process races | Medium | Centralized |
| Any failed target fails whole campaign | If any campaign target delivery fails, campaign ends `failed`; otherwise `sent`. | `app/services/campaign_send.py` | Worker processing of targets | Aggregate campaign status | Per-target connector existence and payload checks | Partial success is retained in deliveries, but campaign still marked failed | High | Centralized |
| Approved campaign requests create pending-release tokens | Transition to approved triggers a 30-day token and optional approval email. | `app/api/campaign_request_routes.py` | Admin patches request to `approved` | Artist receives form link to continue release flow | Existing status must newly become `approved` | Re-approving an already approved request does not create a second token in this path | High | Centralized |
| Minimum configured email rate limit is 10/hour when limit is positive | Persisted or env mail limit values below 10 are raised to 10. | `app/services/mail_settings.py` | Effective config calculation | Avoids legacy too-low limits | Applies only when value is positive and not zero | Setting `0` disables the cap | High | Centralized |
| Release-link candidates below review threshold are auto-rejected | Candidate confidence drives `pending_review` vs `auto_rejected`. | `app/services/release_link_discovery.py` | Link scan processing | Reduces manual review volume | Thresholds `AUTO_REJECT_CONFIDENCE` and `REVIEW_MIN_CONFIDENCE` | Confidence is heuristic; exact business correctness `Needs validation` | High | Centralized |
| Pending release inbox messages are auto-created only for artist-linked items | Helper refuses to create inbox messages when `pending_release.artist_id` is missing. | `app/api/inbox_routes.py` | Pending-release helper call | No inbox seed for unlinked artists | Requires `artist_id` | Can hide communication opportunities for email-only pending releases | High | Centralized |
| Production runtime hardening is mandatory | Production requires disabled docs, explicit CORS, trusted hosts, and strong secrets. | `app/core/config.py`, `app/main.py` | App startup | Runtime abort on invalid production config | Secret length, docs off, CORS/trusted hosts set | Development intentionally permits looser defaults | High | Centralized |

## Notes

- `Manager` permissions exist in `ROLE_PERMISSIONS`, but route-level `require_admin` makes some apparently writable capabilities admin-only.
- `routes.py` contains additional inline rules around file sizes, allowed image extensions, and duplicate matching that are not exhaustively cataloged here.

## Code References

- `apps/server/app/api/deps.py` - role enforcement and LM/artist split
- `apps/server/app/services/auth.py` - role permission map and JWT issuance
- `apps/server/app/api/campaign_routes.py` - schedule/cancel/update entry rules
- `apps/server/app/services/campaign_service.py` - campaign mutation rules
- `apps/server/app/services/campaign_send.py` - aggregate success/failure rule
- `apps/server/app/api/campaign_request_routes.py` - approval-to-token rule
- `apps/server/app/api/inbox_routes.py` - inbox creation and reply rules
- `apps/server/app/services/mail_settings.py` - minimum email rate-limit rule
- `apps/server/app/services/release_link_discovery.py` - link candidate thresholds
- `apps/server/app/core/config.py` - production runtime validation rules
