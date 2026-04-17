# Permissions And Roles

**Last updated:** 2026-04-17

**Scope analyzed:** `app/services/auth.py`, `app/api/deps.py`, and guarded route surfaces

**Confidence level:** High

---

## Roles

| Role | Source | Key permissions from code |
|------|--------|---------------------------|
| `admin` | `users.role` | read/write artists, releases, campaigns, reports, settings, users |
| `manager` | `users.role` | read/write artists, releases, campaigns; read reports/settings/users |
| `artist` | artist JWT subject `artist:{id}` or artist-linked user context | `artist:self`, `releases:self` |

## Authorization Logic

- JWT decoding happens in `decode_token`.
- Current-user resolution happens in `get_current_user`.
- LM-only route filtering happens in `get_current_lm_user`.
- Exact role checks are done by `require_admin` and `require_artist`.

## Enforcement Points

- Route dependencies are the primary enforcement mechanism.
- Many admin routes use `get_current_lm_user` plus `require_admin`.
- Artist self-service routes typically use `get_current_user` plus `require_artist`.
- Object-level artist ownership checks are implemented inside route handlers for releases and campaign requests.

## Notable Gaps And Inconsistencies

- `ROLE_PERMISSIONS` exposes `manager` read access to settings/users, but many actual settings or operational routes still require exact admin role.
- Permissions are returned to clients, but enforcement relies on route guards rather than a single permission-check abstraction.

## Code References

- `apps/server/app/services/auth.py` - role permission map and token creation
- `apps/server/app/api/deps.py` - dependency-based authorization
- `apps/server/app/api/routes.py` - guarded admin and artist route usage
- `apps/server/app/api/campaign_routes.py` - admin-only campaigns
- `apps/server/app/api/campaign_request_routes.py` - artist self routes and admin review routes
- `apps/server/app/api/inbox_routes.py` - artist/admin inbox segregation
