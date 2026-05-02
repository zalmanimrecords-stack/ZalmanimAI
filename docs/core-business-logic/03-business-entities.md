# Business Entities

**Last updated:** 2026-04-18

**Scope analyzed:** `apps/server/app/models/models.py`, schema serialization, and route/service usage

**Confidence level:** High

---

## `Artist`

- Purpose: primary artist record for portal access, profile metadata, releases, inbox association, and media.
- Important fields: `name`, `email`, `password_hash`, `extra_json`, `is_active`, `last_login_at`, `last_profile_updated_at`.
- Usage: created from admin actions, demo approval, or catalog backfill; updated by artist self-service and admin editing.
- Relationships: linked to `Release`, `AutomationTask`, `SocialConnection`, `ArtistActivityLog`, `ArtistMedia`.
- Lifecycle notes: inactive artists remain in data; login requires active status and password.
- Business-significant vs technical-only: `extra_json` is business-significant because it stores profile, minisite, and social-link fields.

## `User` And `UserIdentity`

- Purpose: LM-side users for `admin` and `manager`, plus optional linked `artist` users for OAuth or reset flows.
- Important fields: `role`, `artist_id`, `is_active`, `password_hash`, `last_login_at`.
- Usage: used for LM authentication and admin/manager authorization.
- Relationships: optional link to `Artist`; `UserIdentity` stores external-provider subject and email.
- Lifecycle notes: OAuth login can create a `User` from an existing `Artist`.

## `DemoSubmission`

- Purpose: stores inbound demo metadata and review state.
- Important fields: `artist_name`, `contact_name`, `email`, `links_json`, `fields_json`, `status`, `approval_subject`, `approval_body`, `artist_id`.
- Usage: created by public or artist routes; later reviewed, approved, rejected, or converted to pending release.
- Relationships: optional link to `Artist`.
- Lifecycle notes: statuses include `demo`, `in_review`, `approved`, `rejected`, `pending_release`.

## `PendingRelease` And `PendingReleaseToken`

- Purpose: capture approved release work awaiting completion or processing.
- Important fields: `artist_name`, `artist_email`, `artist_data_json`, `release_title`, `release_data_json`, `status`.
- Usage: created from approved demos or approved `CampaignRequest`s; enriched by artist submissions and admin edits.
- Relationships: optional links to `CampaignRequest`, `DemoSubmission`, `Artist`; comments via `PendingReleaseComment`.
- Lifecycle notes: token rows gate public form access; business status is effectively `pending` or `processed`.

## `PendingReleaseComment`

- Purpose: persist threaded comments on a pending release.
- Important fields: `sender`, `body`, `created_at`.
- Usage: artists and label add comments from portal/admin flows.
- Relationships: belongs to `PendingRelease`.
- Business significance: enables release-preparation collaboration separate from the broader inbox.

## `LabelInboxThread` And `LabelInboxMessage`

- Purpose: general-purpose artist-label conversation store.
- Important fields: `sender`, `body`, `admin_read_at`, `reply_email_sent_at`.
- Usage: artist-initiated messages create threads; pending-release helpers also seed artist-style messages for admin visibility.
- Relationships: thread belongs to `Artist`; messages belong to thread.
- Lifecycle notes: admin opening a thread marks artist messages as read; admin replies can also trigger email.

## `Release`

- Purpose: canonical release record used by artist dashboards, admin release tooling, minisites, and link discovery.
- Important fields: `artist_id`, `title`, `status`, `platform_links_json`, `cover_image_path`, `minisite_slug`, `minisite_is_public`, `minisite_json`.
- Usage: created from artist uploads, catalog sync, and admin flows; later enriched by scans and minisite updates.
- Relationships: one primary artist plus many-to-many `artists`; child `ReleaseLinkCandidate` and `ReleaseLinkScanRun`.
- Lifecycle notes: status strings are implicit and route-managed, not centralized.

## `CatalogTrack`

- Purpose: imported catalog metadata for releases/tracks from CSV exports.
- Important fields: `catalog_number`, `release_title`, `release_date`, `isrc`, `original_artists`, `track_title`.
- Usage: import, dedupe, artist matching, and release creation/sync.
- Relationships: no direct FK to `Release`; matching is title/name-based.

## `CampaignRequest`

- Purpose: artist-side request asking the label to run a campaign for a release.
- Important fields: `artist_id`, `release_id`, `message`, `status`, `admin_notes`.
- Usage: created in the artist portal, approved or rejected by admin.
- Lifecycle notes: approval creates a pending-release token email rather than a `Campaign` directly.

## `Campaign`, `CampaignTarget`, And `CampaignDelivery`

- Purpose: draft/scheduled outbound campaign plus target definitions and delivery outcomes.
- Important fields: `status`, `scheduled_at`, `sent_at`, `channel_type`, `channel_payload`, `error_message`.
- Usage: admin creates draft, schedules it, worker claims it, sender records target-level results.
- Lifecycle notes: aggregate campaign status becomes `failed` if any target fails.

## `SocialConnection` And `HubConnector`

- Purpose: store credentials or connection metadata for outbound integrations.
- Important fields: provider/channel identity, encrypted access/refresh tokens, connector config JSON, connection status.
- Usage: social publishing, Mailchimp target resolution, WordPress publishing.
- Lifecycle notes: social tokens can be migrated from legacy plaintext to encrypted form.

## `MailSettings`, `MailingList`, And `MailingSubscriber`

- Purpose: support communication settings and simple mailing-list storage.
- Important fields: SMTP values, template subjects/bodies, `emails_per_hour`, footer text, subscriber consent fields.
- Usage: admin settings UI, template UI, demo-intake mailing list maintenance.
- Lifecycle notes: `MailSettings` is a single-row override over environment configuration.

## `SystemLog`

- Purpose: persist operational and mail logs visible in the admin UI.
- Important fields: `level`, `category`, `message`, `details`.
- Usage: request errors, mail activity, and other events.

## `AutomationTask`

- Purpose: queue-like artist task model.
- Usage: present in artist dashboard and schema, but `Needs validation` as a live automation feature because the analyzed worker does not process it.

## Code References

- `apps/server/app/models/models.py` - entity definitions and relationships
- `apps/server/app/schemas/schemas.py` - outward entity shaping and derived fields
- `apps/server/app/api/routes.py` - entity creation and mutation flows
- `apps/server/app/api/inbox_routes.py` - inbox entities in use
- `apps/server/app/api/campaign_request_routes.py` - `CampaignRequest` usage
- `apps/server/app/services/campaign_send.py` - `Campaign`, `CampaignTarget`, `CampaignDelivery` usage
- `apps/server/app/services/release_link_discovery.py` - `Release`, `ReleaseLinkCandidate`, `ReleaseLinkScanRun` usage
