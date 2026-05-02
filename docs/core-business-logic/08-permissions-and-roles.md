# Permissions And Roles

**Last updated:** 2026-04-18

**Scope analyzed:** `app/services/auth.py`, `app/api/deps.py`, route guards, and visible client affordances

**Confidence level:** High

---

## Roles

- `admin`
- `manager`
- `artist`
- Public unauthenticated caller `Assumption`: not modeled as a role, but functionally an actor for public routes

## Role Permissions Defined In Code

| Role | Permission set from code |
|------|---------------------------|
| `admin` | `artists:read`, `artists:write`, `releases:read`, `releases:write`, `campaigns:read`, `campaigns:write`, `reports:read`, `settings:read`, `settings:write`, `users:read`, `users:write` |
| `manager` | `artists:read`, `artists:write`, `releases:read`, `releases:write`, `campaigns:read`, `campaigns:write`, `reports:read`, `settings:read`, `users:read` |
| `artist` | `artist:self`, `releases:self` |

## Access Rules

- LM routes using `get_current_lm_user` reject artist-portal JWTs even if the artist is active.
- Admin-only actions require `require_admin(user)`.
- Artist self-service actions require `require_artist(user)` and often `artist_id` ownership checks.
- Public tokenized flows bypass login but require a valid hashed token row and non-expired `expires_at`.

## Enforcement Points

- Middleware-level auth is not used for roles; enforcement is route dependency based.
- `get_current_user` resolves both LM users and artist tokens.
- `get_current_lm_user` blocks artist tokens early with a special 403 detail.
- `require_admin` and `require_artist` perform the final role checks.
- Additional business ownership checks are embedded directly in route handlers.

## Business-Driven Vs Framework-Driven Enforcement

### Business-Driven

- artist can only act on self-owned releases and self-owned inbox/media/dashboard data
- campaign requests for artists are scoped to releases they own
- admin-only actions cover restore, mail settings, portal invites, and review-heavy operations

### Framework-Driven

- bearer-token extraction and HTTP 401/403 response generation
- route dependency injection for DB sessions and auth contexts

## Gaps And Inconsistencies

- `manager` has read access to settings in the permission map but many settings routes still call `require_admin`; the effective capability is narrower than the permission list suggests.
- `manager` has `users:read` in the permission list, but routes involving user management remain admin-gated.
- `Needs validation`: client tabs may expose controls that later fail at the API layer for non-admin users.
- Artists are represented both as direct `Artist` portal users and as optional `User(role="artist")` rows, which increases identity-shape complexity.

## Special Cases

- OAuth login can create or link a `User` from an existing `Artist` email, but only when that artist already exists in the system.
- Public forms rely on token possession rather than account identity.
- Inbox reply emails are sent to the artist email without requiring an active portal session.

## Code References

- `apps/server/app/services/auth.py` - role permission definitions
- `apps/server/app/api/deps.py` - token resolution and role guards
- `apps/server/app/api/routes.py` - route-level admin/artist enforcement
- `apps/server/app/api/campaign_request_routes.py` - artist ownership checks
- `apps/server/app/api/inbox_routes.py` - artist/admin inbox boundaries
- `apps/client/lib/features/admin/admin_dashboard_page.dart` - admin UI navigation surface
- `apps/artist_portal/lib/features/dashboard/artist_dashboard_page.dart` - artist self-service UI surface
