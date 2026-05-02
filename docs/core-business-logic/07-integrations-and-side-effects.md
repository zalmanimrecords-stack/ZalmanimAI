# Integrations And Side Effects

**Last updated:** 2026-04-18

**Scope analyzed:** Connector services, OAuth helpers, campaign senders, email services, and file-writing flows

**Confidence level:** High

---

## SMTP / Email

- External system: configured SMTP server(s), with optional backup SMTP
- Purpose: send receipts, approvals, rejections, invites, password resets, reminders, inbox replies, and test emails
- Trigger points: demo workflows, onboarding, password reset, inbox reply, reminder routes, admin test route
- Inbound/outbound data: plain-text email bodies plus template fields and optional footer
- Error handling: send helpers return success/message; many callers log warning and continue
- Retry/async behavior: mostly synchronous request-time delivery; admin can manually retry some flows
- Business impact if integration fails: approval/request state can persist while the artist misses the next-step email

## Social Providers

- External system: Meta, TikTok, YouTube, X, LinkedIn, SoundCloud, and related OAuth/browser flows
- Purpose: connect accounts and publish social campaign targets
- Trigger points: OAuth start/callback/complete routes, campaign send execution
- Data flow: PKCE/browser-side token exchange and stored encrypted tokens on `SocialConnection`
- Error handling: missing/disconnected connection marks campaign target failed
- Retry/async behavior: publish occurs inside worker send loop
- Business impact if integration fails: campaign may become aggregate `failed`

## Mailchimp

- External system: Mailchimp API
- Purpose: connector test, audience/list retrieval, and campaign send delivery
- Trigger points: connector routes and `campaign_send.py`
- Data flow: API key from env or connector config, list id from `CampaignTarget.channel_payload`
- Error handling: sender returns failed delivery with message
- Retry/async behavior: worker-time send only
- Business impact if integration fails: email campaign channel does not go out; overall campaign may fail

## WordPress Codex Bridge

- External system: WordPress bridge endpoint
- Purpose: publish campaign content and support WordPress-facing demo tooling
- Trigger points: campaign send and external plugin usage
- Data flow: connector config plus title/content/post type/status
- Error handling: missing connector or HTTP failure marks target failed
- Retry/async behavior: worker-time send only
- Business impact if integration fails: website post/page is not published

## Release-Link Discovery Web Sources

- External system: Apple/iTunes, Deezer, YouTube, Spotify web, SoundCloud web, Beatport web, Bandcamp web, Tidal web, Amazon Music web, DuckDuckGo HTML
- Purpose: discover likely official release links and artwork
- Trigger points: manual scans, release creation, periodic rescans, artwork refresh
- Data flow: outbound HTTP search/scrape requests and inbound candidate metadata/artwork bytes
- Error handling: per-platform failure stored in scan summary; run can still complete with partial results
- Retry/async behavior: periodic worker rescans after cooldown
- Business impact if integration fails: releases remain without links/artwork and require manual curation

## Local File Storage

- External system: local filesystem under `settings.upload_dir`
- Purpose: store release uploads, artist media, campaign media, pending-release images, demo files, and downloaded cover art
- Trigger points: upload routes, normalization routes, cover-art refresh
- Error handling: request errors on invalid size/type/path; some old-file cleanup failures are ignored
- Retry/async behavior: request-time writes except background cover-art download after approval
- Business impact if integration fails: artists/admin lose attachment workflow continuity

## Redis

- External system: Redis
- Purpose: hourly email rate-limit counter
- Trigger points: outbound email send path
- Error handling: `Unclear from code` from analyzed slices whether Redis failure hard-fails or degrades gracefully in all cases
- Retry/async behavior: runtime cache/counter dependency, not queued work

## Backup / Restore Export Files

- External system: downloaded/uploaded JSON backup files
- Purpose: portable full-database export and restore
- Trigger points: admin backup/restore endpoints
- Data flow: JSON payload built from DB and later uploaded back
- Error handling: file size and JSON validation on restore
- Business impact if integration fails: operational recovery workflow breaks

## Code References

- `apps/server/app/services/email_service.py` - email delivery paths
- `apps/server/app/services/mail_settings.py` - mail config sourcing
- `apps/server/app/services/social_publisher.py` - social delivery integration
- `apps/server/app/services/social_oauth.py` and `app/api/oauth_helpers.py` - OAuth/browser token flows
- `apps/server/app/services/mailchimp_service.py` - Mailchimp integration
- `apps/server/app/services/hub_connectors.py` - WordPress bridge integration
- `apps/server/app/services/release_link_discovery.py` - search/scrape integrations and cover downloads
- `apps/server/app/api/routes.py` - upload, backup/restore, and integration-triggering routes
- `apps/server/app/services/campaign_send.py` - per-target send orchestration
