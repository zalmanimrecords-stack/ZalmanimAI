# Critical Flows

**Last updated:** 2026-04-18

**Scope analyzed:** `app/api/routes.py`, `campaign_request_routes.py`, `campaign_routes.py`, `inbox_routes.py`, `campaign_send.py`, `release_link_discovery.py`, `worker.py`

**Confidence level:** High

---

## Demo Submission To Pending Release

- Goal: turn inbound demos into actionable label-release work.
- Trigger: public demo submission, artist demo submission, and later admin approval.

1. Public or artist route stores `DemoSubmission` metadata and optional uploaded file.
2. Demo-related templates and mailing-list updates can run around intake/review actions.
3. Admin reviews the submission, updates status, and may edit notes/template content.
4. Approval reuses an existing `Artist` by email or creates one from demo data.
5. The server creates a `PendingRelease` if one does not already exist for that demo.
6. Approval messaging is sent if email is configured.

- Modules involved: `app/api/routes.py`, `app/api/mail_templates.py`, `app/models/models.py`
- Validations: role checks, upload size/type checks, duplicate pending-release prevention, email-driven artist lookup
- State changes: `DemoSubmission.status`, optional `Artist`, optional `PendingRelease`
- Side effects: email sends, mailing-list subscription updates, file writes
- Failure paths: send failures do not necessarily roll back approved data changes
- Rollback/retry: no explicit transactional compensation beyond DB rollback on raised exceptions

## Campaign Request Approval To Pending-Release Access

- Goal: move an artist campaign request into a structured release-information collection step.
- Trigger: admin changes `CampaignRequest.status` to `approved`.

1. Artist creates `CampaignRequest` against an owned release or without one.
2. Admin loads and updates the request.
3. If status changed from non-approved to `approved`, server creates a raw token and stores only its SHA-256 hash in `PendingReleaseToken`.
4. The token expiry is set to 30 days.
5. The email body includes a hash-route link into the artist portal pending-release form.
6. Email delivery is attempted but approval persists even if send fails.

- Modules involved: `app/api/campaign_request_routes.py`, `app/models/models.py`, `app/services/email_service.py`
- Validations: ownership checks on artist-requested release IDs, admin-only approval
- State changes: `CampaignRequest.status`, new `PendingReleaseToken`
- Side effects: email delivery
- Failure paths: email warning only; no rollback of approval

## Artist Pending-Release Completion And Follow-Up

- Goal: collect business-ready metadata and assets for approved work.
- Trigger: tokenized public form, artist portal release page, admin review pages, or reminder/comment actions.

1. Server validates the pending-release token or artist ownership context.
2. Artist submits identity fields, release metadata, mastering flags, and optional cover reference image.
3. Server stores artist and release snapshots into JSON fields on `PendingRelease`.
4. Artist and admin can add comments to the pending release.
5. Admin can upload image options, normalize/remove images, select defaults, archive, delete, or mark processed.
6. Admin reminders and comments may notify the artist unless `notifications_muted` is set.
7. Helper logic can also seed the label inbox with release-related artist messages.

- Modules involved: `app/api/routes.py`, `app/api/pending_release_helpers.py`, `app/api/inbox_routes.py`
- Validations: token validity, upload size/type, comment sender identity, selected-image membership
- State changes: `PendingRelease.release_data_json`, `PendingRelease.status`, `PendingReleaseComment`, optional inbox messages
- Side effects: local file writes, reminder/update emails
- Failure paths: invalid/expired token, missing image id, oversized uploads
- Rollback/retry: mostly request-scoped DB rollback; reminders can be retried manually

## Unified Campaign Draft To Delivery

- Goal: publish one piece of campaign content across multiple channels.
- Trigger: admin creates a draft and schedules it; worker polling detects readiness.

1. Admin creates `Campaign` and target rows.
2. Admin optionally updates targets or media while status is editable.
3. Scheduling flips status from `draft` to `scheduled`; `scheduled_at=None` means send on next worker poll.
4. Worker polls every 60 seconds and queries scheduled campaigns due now.
5. Worker atomically claims one campaign by flipping `scheduled` to `sending`.
6. Sender iterates over targets and delegates to social, Mailchimp, or WordPress integrations.
7. Each target produces a `CampaignDelivery` with `sent` or `failed`.
8. Campaign becomes `sent` only when every target succeeds; otherwise it becomes `failed`.

- Modules involved: `app/api/campaign_routes.py`, `app/services/campaign_service.py`, `app/services/campaign_send.py`, `apps/server/worker.py`
- Validations: target existence, connector type, required list IDs, allowed status transitions
- State changes: `Campaign.status`, `scheduled_at`, `sent_at`, `CampaignDelivery`
- Side effects: external post/campaign creation
- Failure paths: missing connectors, disconnected social connection, provider/API errors
- Rollback/retry: no multi-target rollback; partial external delivery can coexist with aggregate `failed`

## Release Link Discovery And Minisite Enrichment

- Goal: discover official platform links, store review candidates, and improve release presentation.
- Trigger: manual admin scan, release creation, periodic worker scan, or artwork refresh.

1. A `ReleaseLinkScanRun` is queued manually or automatically.
2. Worker marks queued runs as `running` and loads the target release.
3. Platform adapters call APIs or scrape HTML/web search results.
4. Candidate confidence is computed from title similarity, artist similarity, domain bonus, and URL/path heuristics.
5. Candidates are persisted as `pending_review` or `auto_rejected`.
6. Best artwork candidates can download and attach local cover images.
7. Admin approves or rejects candidates; approval updates `Release.platform_links_json`.
8. Admin can also edit minisite metadata and toggle public visibility.

- Modules involved: `app/services/release_link_discovery.py`, `app/api/routes.py`, `apps/server/worker.py`
- Validations: supported platforms, release existence, review thresholds, public minisite checks
- State changes: `ReleaseLinkScanRun.status`, `ReleaseLinkCandidate.status`, `Release.platform_links_json`, `Release.cover_image_*`, `Release.minisite_*`
- Side effects: outbound HTTP requests and local image downloads
- Failure paths: adapter/network failures, missing release, invalid public minisite state
- Rollback/retry: periodic rescans retry releases with no links and no pending-review candidates

## Inbox Reply Flow

- Goal: preserve artist-label conversations and optionally mirror admin replies by email.
- Trigger: artist sends message, admin opens thread, or admin replies.

1. Artist creates a new inbox thread with an initial message.
2. Admin listing/opening threads loads joined artist/message data.
3. Opening a thread marks unread artist messages as read.
4. Admin reply creates a `LabelInboxMessage` with sender `label`.
5. If email is configured, the reply body is also emailed to the artist and `reply_email_sent_at` is stamped.

- Modules involved: `app/api/inbox_routes.py`, `app/services/email_service.py`
- Validations: artist ownership and non-empty message body
- State changes: `LabelInboxMessage`, `admin_read_at`, `reply_email_sent_at`, `thread.updated_at`
- Side effects: reply email delivery
- Failure paths: missing thread/artist, email send warning

## Code References

- `apps/server/app/api/routes.py` - demo, pending-release, release, minisite, and reminder flows
- `apps/server/app/api/campaign_request_routes.py` - campaign-request approval flow
- `apps/server/app/api/campaign_routes.py` - campaign scheduling and editing flow
- `apps/server/app/api/inbox_routes.py` - inbox flow
- `apps/server/app/api/pending_release_helpers.py` - pending-release serialization and notification logic
- `apps/server/app/services/campaign_service.py` - campaign state transitions
- `apps/server/app/services/campaign_send.py` - delivery orchestration
- `apps/server/app/services/release_link_discovery.py` - scan, confidence, and approval flow
- `apps/server/worker.py` - polling automation
