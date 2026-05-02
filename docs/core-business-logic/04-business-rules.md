# Business Rules

**Last updated:** 2026-04-18

**Scope analyzed:** Route guards, service-layer decisions, entity status mutations, and worker send/scan logic

**Confidence level:** High

---

| Rule name | Description | Code location | Trigger | Outcome | Validations | Edge cases | Confidence | Centralized or duplicated |
|-----------|-------------|---------------|---------|---------|-------------|------------|------------|---------------------------|
| LM routes reject artist tokens | Label-management routes require `users`-table JWT subjects, not `artist:{id}` tokens | `app/api/deps.py` | Artist token hits LM route | 403 with artist-specific detail | JWT subject prefix check | Managers still fail later on admin-only routes | High | Centralized |
| Admin-only enforcement | Many sensitive routes require exact role `admin` | `app/api/deps.py`, LM routes | Admin functions called | 403 unless `user.role == "admin"` | Explicit role comparison | Managers may still see UI affordances `Needs validation` | High | Centralized |
| Artist ownership on self-service release access | Artist can reference only owned releases when creating campaign requests or viewing self-service resources | `campaign_request_routes.py`, `routes.py` | Artist acts on release-linked flow | 404/403 when release not owned | FK ownership checks including many-to-many artists | Placeholder releases with null primary artist still rely on join table | High | Repeated |
| Demo approval can create or link artist | Approved demo reuses `Artist` by lowercased email or creates one | `app/api/routes.py` | Admin approves demo | `DemoSubmission.artist_id` assigned and possibly new `Artist` created | Email-based lookup | Same email becomes the dedupe key | High | Centralized |
| Approved demo creates pending release idempotently | Only one `PendingRelease` per demo submission is created | `app/api/routes.py` helper | Demo approved | Existing row reused or new row added | Query by `demo_submission_id` | Multiple approvals do not duplicate rows | High | Centralized |
| Campaign-request approval sends artist to pending-release form | Newly approved `CampaignRequest` generates a 30-day token and email | `campaign_request_routes.py` | Admin changes status to `approved` | `PendingReleaseToken` stored and email attempted | Status transition from non-approved to approved | Email failure logs warning but does not undo approval | High | Centralized |
| Pending-release submission requires minimum identity fields | Public pending-release form requires artist name, email, and release title | `apps/artist_portal/...pending_release_form_page.dart`, `app/api/routes.py` | Form submission | Pending release updated/created | UI checks and server token checks | Exact server-side required-field enforcement is spread across route logic | Medium | Duplicated between UI and server |
| Mastering confirmation required when mastering requested | If `mastering_required` is true, artist must confirm 6 dB headroom | `apps/artist_portal/...pending_release_form_page.dart` | Public pending-release submit | UI blocks submit | Client-side conditional validation | `Unclear from code` whether same invariant is enforced server-side | Medium | UI-only visible |
| Pending-release notifications can be muted | Reminder/update emails are skipped when `release_data["notifications_muted"]` is true | `pending_release_helpers.py`, `routes.py` | Admin comment/reminder or other pending-release email | No email sent | JSON flag lookup | Data still changes even when notifications are muted | High | Centralized |
| Selected pending-release image must come from stored options | Artist can only choose an image id already present in `image_options` | `app/api/routes.py` | Artist selects image | `selected_image_id` updated | Set-membership check | Removal of selected image auto-falls back to first remaining image | High | Centralized |
| Campaign is editable only before sending | Only `draft` and sometimes `scheduled` campaigns can be updated; only `draft` can be scheduled | `campaign_service.py`, `campaign_routes.py` | Admin edits/schedules campaign | Mutations allowed or rejected | Status checks | Delete allows only `draft` or `failed` | High | Centralized |
| Worker claims scheduled campaign atomically | Send execution starts only if a row updates from `scheduled` to `sending` | `campaign_service.py` | Worker attempts send | At most one worker claims campaign | SQL update by status | Rollback occurs when claim fails | High | Centralized |
| Any failed target fails whole campaign | Campaign aggregate status becomes `failed` if any target send fails | `campaign_send.py` | Campaign send loop completes | Campaign marked `failed` even if some deliveries succeeded | Per-target try/except | `Needs validation` whether partial success should surface differently | High | Centralized |
| Release-link candidates below review threshold auto-reject | Candidate confidence below `REVIEW_MIN_CONFIDENCE` is auto-rejected | `release_link_discovery.py` | Scan discovers candidate | Candidate status becomes `auto_rejected` or `pending_review` | Confidence scoring with title/artist/domain heuristics | Existing pending-review candidates block periodic rescans | High | Centralized |
| Only one approved link per platform survives | Approving one candidate rejects sibling approved candidates for same release/platform | `release_link_discovery.py` | Admin approves candidate | `platform_links_json` updated and siblings demoted | Platform equality check | Rejecting approved candidate also removes active link | High | Centralized |
| Release minisite public page needs slug and `minisite_is_public` | Public minisite endpoint returns only when both values are truthy | `app/api/routes.py` | Public minisite request | 404 when not public | Slug and boolean check | Artist portal also keeps parallel minisite intent in `Artist.extra_json` | High | Partially duplicated |
| Effective hourly email limit has a floor | Persisted or env email limit below 10 is raised to 10 when positive | `mail_settings.py` | Effective config read | Minimum effective rate is 10/hour | `max(10, raw_limit)` | UI can save smaller values, but runtime raises them | High | Centralized |

## Notes

- `Unclear from code`: whether the public pending-release mastering confirmation is intentionally enforced only in the artist portal UI.
- `Needs validation`: whether `CampaignRequest` approval should remain independent from email delivery success.

## Code References

- `apps/server/app/api/deps.py` - role and token rules
- `apps/server/app/api/routes.py` - demo, pending-release, release, and minisite rules
- `apps/server/app/api/campaign_request_routes.py` - campaign-request approval rules
- `apps/server/app/services/campaign_service.py` - campaign lifecycle restrictions
- `apps/server/app/services/campaign_send.py` - aggregate send outcome logic
- `apps/server/app/services/release_link_discovery.py` - confidence thresholds and approval effects
- `apps/server/app/services/mail_settings.py` - effective mail-rate rule
- `apps/artist_portal/lib/features/public/pending_release_form_page.dart` - client-visible pending-release validation
