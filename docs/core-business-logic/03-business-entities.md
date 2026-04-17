# Business Entities

**Last updated:** 2026-04-17

**Scope analyzed:** `apps/server/app/models/models.py` and entity-creating flows in `app/api` and `app/services`

**Confidence level:** High

---

## `Artist`

- Purpose: canonical artist record for contact data, portal access, release ownership, social connections, and media.
- Important fields: `name`, `email`, `password_hash`, `extra_json`, `is_active`, `last_login_at`, `last_profile_updated_at`.
- Used by: admin artist management, portal login, demo approval linking, release ownership, invite emails, and inbox threads.
- Relationships: releases, tasks, social connections, activity logs, media files.
- Lifecycle: created manually, from approved demos, or from missing catalog artists; may be deactivated during merge.

## `User` and `UserIdentity`

- Purpose: LM-side identity for admins/managers and some artist-linked logins.
- Important fields: `role`, `artist_id`, `is_active`, `last_login_at`; identity stores `provider`, `provider_subject`.
- Used by: admin login, OAuth user linking, dashboard stats, permissions.
- Lifecycle: created by admin flows or OAuth matching; deactivated users are blocked.

## `DemoSubmission`

- Purpose: intake record for inbound music submissions.
- Important fields: contact metadata, `links_json`, `fields_json`, `consent_to_emails`, `status`, approval/rejection send timestamps, optional `artist_id`.
- Used by: public demo form, artist dashboard demo uploads, admin review list, approval conversion to artist and pending release.
- Lifecycle: starts as `demo`, may move through review states and to `approved`, `rejected`, or `pending_release`.

## `CampaignRequest`

- Purpose: artist-originated request to move a release toward campaign/release work.
- Important fields: `artist_id`, `release_id`, `message`, `status`, `admin_notes`.
- Used by: artist request submission and admin approval/rejection.
- Lifecycle: `pending` to `approved` or `rejected`; approval creates a `PendingReleaseToken`.

## `PendingRelease` and `PendingReleaseComment`

- Purpose: hold release details awaiting label completion or processing.
- Important fields: artist snapshot, `release_title`, `artist_data_json`, `release_data_json`, `status`.
- Used by: tokenized forms, artist/admin comments, reference image uploads, reminders, archive/delete handling.
- Lifecycle: created from approved demo or campaign request, usually begins `pending`, and may move to `processed`.

## `LabelInboxThread` and `LabelInboxMessage`

- Purpose: artist-label conversation log.
- Important fields: thread `artist_id`; message `sender`, `body`, `admin_read_at`, `reply_email_sent_at`.
- Used by: artist-initiated inbox messages, admin replies, and pending-release helper notifications.

## `Release`

- Purpose: label release record with ownership, assets, links, and minisite data.
- Important fields: `artist_id`, `title`, `status`, `platform_links_json`, cover image fields, `minisite_slug`, `minisite_is_public`, `minisite_json`.
- Used by: artist uploads, admin edits, catalog sync, release-link discovery, public minisite rendering.

## `ReleaseLinkCandidate` and `ReleaseLinkScanRun`

- Purpose: persist discovered release-link options and the scan jobs that found them.
- Important fields: platform, URL, confidence, review status, run trigger type, summary, error.
- Used by: manual scans, scheduled scans, admin review/approval, cover-art refresh.

## `CatalogTrack`

- Purpose: imported label catalog metadata used to sync releases and normalize artist names.
- Important fields: catalog identifiers, dates, original/remix artist strings, track names.
- Used by: import, release sync, original-artist normalization, creation of missing artist shells.

## `Campaign`, `CampaignTarget`, and `CampaignDelivery`

- Purpose: model a reusable outbound campaign and per-channel outcomes.
- Important fields: campaign content, `status`, `scheduled_at`, target `channel_type`, target payload, delivery `status`, provider `external_id`.
- Used by: admin campaigns UI and worker execution.

## `MailSettings`

- Purpose: editable single-row override for SMTP settings and email templates.
- Important fields: primary and backup SMTP config, rate limit, footer, and multiple template subject/body pairs.
- Used by: settings retrieval, mail sends, approval/rejection templates, portal invites, password reset.

## `SocialConnection`, `HubConnector`, `MailingList`, and `MailingSubscriber`

- Purpose: store outbound integration endpoints and mailing-audience state.
- Important fields: provider/account labels, encrypted tokens, connector config JSON, subscriber consent and unsubscribe metadata.
- Used by: campaign sends, social publish, Mailchimp and WordPress connector testing, demo mailing-list maintenance.

## `SystemLog`

- Purpose: admin-facing persistent log stream for API, artist portal, and mail/system events.
- Important fields: `level`, `category`, `message`, `details`.
- Used by: error handlers, admin logs tab, support/diagnostic workflows.

## Code References

- `apps/server/app/models/models.py` - entity definitions and field-level semantics
- `apps/server/app/api/routes.py` - creation and mutation of artists, demos, pending releases, releases, settings, and backups
- `apps/server/app/api/campaign_request_routes.py` - `CampaignRequest` approval behavior
- `apps/server/app/api/inbox_routes.py` - inbox thread/message lifecycle
- `apps/server/app/services/campaign_send.py` - `CampaignDelivery` creation
- `apps/server/app/services/mail_settings.py` - `MailSettings` merge and persistence behavior
- `apps/server/app/services/release_link_discovery.py` - `ReleaseLinkCandidate` and `ReleaseLinkScanRun` lifecycle
