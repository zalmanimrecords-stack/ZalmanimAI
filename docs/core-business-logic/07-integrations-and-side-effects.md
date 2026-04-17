# Integrations And Side Effects

**Last updated:** 2026-04-17

**Scope analyzed:** Server integration services, OAuth/config, worker tasks, and admin settings surfaces

**Confidence level:** Medium

---

## SMTP / Email Delivery

- Purpose: send approval, rejection, receipt, invite, password-reset, reminder, inbox-reply, and ad hoc admin emails.
- Trigger points: demo workflows, campaign request approval, pending-release reminders, inbox replies, settings test route, password reset, admin manual send.
- Error handling: send helpers return success/error text; many flows log or warn but keep the main DB mutation.
- Retry/async behavior: no general retry queue in analyzed code; backup SMTP is the main fallback.

## Social Providers

- Purpose: connect accounts for publish or identity flows.
- Trigger points: OAuth start/callback/complete routes and social publish inside campaign delivery.
- Data flow: provider client IDs/secrets, PKCE state, encrypted access/refresh tokens, external account IDs.
- Error handling: missing connectors or disconnected accounts fail the target delivery.

## Mailchimp

- Purpose: send campaign email content to a selected list/audience.
- Trigger points: campaign send.
- Error handling: missing connector or missing `list_id` marks delivery failed.

## WordPress Codex Bridge

- Purpose: create or update post/page content from campaigns.
- Trigger points: campaign send and connector test/setup flows.
- Error handling: missing connector or connector failure marks delivery failed.

## External Music / Search Sites

- Systems: iTunes, Deezer, YouTube, Bandcamp, Spotify/Open web pages, Beatport, Tidal, Amazon Music, DuckDuckGo.
- Purpose: discover release links and artwork.
- Trigger points: manual and scheduled scan runs, cover-art refresh.
- Error handling: per-platform failures are captured into scan summaries; retry waits one day when links remain unresolved.

## Redis

- Purpose: email rate-limit counter storage.
- `Needs validation`: downstream failure behavior was not fully traced in the email service implementation.

## File System

- Purpose: hold release uploads, pending-release images, artist media, campaign media, and downloaded cover art.
- Trigger points: artist uploads, admin uploads, cover-art download, campaign media upload.
- Error handling: route-level size/type checks exist; filesystem failure behavior is mostly exception-driven.

## Code References

- `apps/server/app/services/email_service.py` - email delivery entry points
- `apps/server/app/services/mail_settings.py` - effective mail config and backup SMTP use
- `apps/server/app/api/routes.py` - email-triggering business routes and media/file flows
- `apps/server/app/api/inbox_routes.py` - reply email side effects
- `apps/server/app/services/social_publisher.py` - social publish integration
- `apps/server/app/services/campaign_send.py` - outbound campaign integration dispatch
- `apps/server/app/services/hub_connectors.py` - WordPress connector publishing
- `apps/server/app/services/mailchimp_service.py` - Mailchimp campaign sending
- `apps/server/app/services/release_link_discovery.py` - external link/artwork discovery
- `apps/server/app/core/config.py` - integration configuration surface
- `apps/server/worker.py` - async/polling execution context
