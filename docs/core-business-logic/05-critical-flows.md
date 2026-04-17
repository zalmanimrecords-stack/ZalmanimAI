# Critical Flows

**Last updated:** 2026-04-17

**Scope analyzed:** `app/api/routes.py`, `campaign_request_routes.py`, `campaign_routes.py`, `inbox_routes.py`, `campaign_send.py`, `worker.py`

**Confidence level:** Medium

---

## Demo Submission To Pending Release

1. Public or artist route stores a `DemoSubmission` with contact metadata and optional file details.
2. Admin reviews the submission and updates its status.
3. On approval, the system can reuse an existing `Artist` by email or create a new one from demo metadata.
4. The system creates a `PendingRelease` if one does not already exist for that demo.
5. Template-aware approval messaging may be sent by email.

- Modules involved: `app/api/routes.py`, `app/api/mail_templates.py`, `app/models/models.py`
- Validations: file size/type checks, role checks, duplicate/artist-link checks
- State changes: `DemoSubmission.status` mutates; `Artist` and `PendingRelease` may be created
- Side effects: mailing-list maintenance and outbound approval/receipt/rejection emails

## Campaign Request Approval To Pending Release Form

1. Artist creates `CampaignRequest` with optional `release_id`.
2. Admin reviews and sets `status`.
3. If status newly becomes `approved`, the server generates a raw token, stores its SHA-256 hash in `PendingReleaseToken`, and sets a 30-day expiry.
4. The server constructs a pending-release form link pointing to the artist portal hash route.
5. If email is configured, it sends the approval message containing the link.

- Modules involved: `app/api/campaign_request_routes.py`, `app/models/models.py`, `app/services/email_service.py`
- Validations: artist can only reference owned releases; admin required for approval
- State changes: `CampaignRequest.status` changes; `PendingReleaseToken` created
- Side effects: email delivery to the artist

## Artist Pending Release Completion

1. The system validates a pending-release or demo-confirm token.
2. Artist submits artist/release data and optional reference images.
3. The server saves structured JSON snapshots on `PendingRelease`.
4. Artist and label can exchange comments and select images.
5. Admin can archive, delete, or send reminders for unfinished items.

- Modules involved: `app/api/routes.py`, `app/api/pending_release_helpers.py`, `app/api/inbox_routes.py`
- Validations: token validity, ownership, allowed image extensions, upload size limits
- State changes: `PendingRelease` content and `status`; `PendingReleaseComment` rows; optional inbox messages
- Side effects: email reminders and file writes to upload storage

## Unified Campaign Draft To Delivery

1. Admin creates a `Campaign` with optional `CampaignTarget` rows.
2. Admin schedules the campaign, moving it from `draft` to `scheduled`.
3. Worker polls every 60 seconds for ready campaigns.
4. Worker atomically claims the campaign by flipping status to `sending`.
5. For each target, sender-specific logic calls social, Mailchimp, or WordPress delivery code and records a `CampaignDelivery`.
6. Campaign ends as `sent` only if every target succeeds; otherwise it becomes `failed`.

- Modules involved: `app/api/campaign_routes.py`, `app/services/campaign_service.py`, `app/services/campaign_send.py`, `apps/server/worker.py`
- Validations: target existence, required list IDs, allowed campaign status transitions
- State changes: `Campaign.status`, `scheduled_at`, `sent_at`; per-target delivery records
- Side effects: remote post/campaign creation in external systems

## Release Link Discovery And Review

1. A scan run is queued for a release.
2. Worker loads queued scan runs and marks each as `running`.
3. Platform adapters search APIs or HTML/web results for candidate URLs.
4. Each candidate receives a confidence score from title/artist similarity and URL heuristics.
5. Candidates are stored as `pending_review` or `auto_rejected`.
6. Best artwork candidates can update release cover art automatically.
7. Admin approval writes the chosen URL into `Release.platform_links_json` and rejects sibling approved links for the same platform.

- Modules involved: `app/services/release_link_discovery.py`, `apps/server/worker.py`, `app/api/routes.py`
- Validations: supported platform list, release existence, candidate thresholds
- State changes: `ReleaseLinkScanRun.status`, `ReleaseLinkCandidate.status`, `Release.platform_links_json`, cover image fields
- Side effects: outbound HTTP requests and image downloads to local storage

## Code References

- `apps/server/app/api/routes.py` - demo, pending release, release, and scan flows
- `apps/server/app/api/campaign_request_routes.py` - campaign request approval flow
- `apps/server/app/api/campaign_routes.py` - campaign scheduling flow
- `apps/server/app/api/inbox_routes.py` - inbox/reply flow
- `apps/server/app/services/campaign_service.py` - campaign state changes
- `apps/server/app/services/campaign_send.py` - delivery orchestration
- `apps/server/app/services/release_link_discovery.py` - scan and approval flow
- `apps/server/worker.py` - polling and asynchronous execution
