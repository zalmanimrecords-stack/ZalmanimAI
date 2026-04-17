# Executive Summary

**Last updated:** 2026-04-17

**Scope analyzed:** Full repo with business focus on `apps/server/app`, worker automation, and relevant admin UI surfaces

**Confidence level:** Medium

---

## System Purpose

The implemented system is a label-operations platform for Zalmanim. It handles artist/admin access, demo intake, release-preparation workflows, release enrichment, and outbound communications/publishing.

## Core Capabilities

- intake demos from public and artist-authenticated sources
- review demos and convert approved work into release-preparation tasks
- collect release details from artists through tokenized/public and authenticated flows
- maintain release records, cover art, platform links, and public minisites
- schedule and send campaigns to social, Mailchimp, and WordPress
- manage SMTP settings, email templates, logs, and backups through the admin UI

## Major Business Risks

- The most important rules live in long route handlers, which raises drift and maintenance risk.
- One failed target causes an entire campaign to be marked failed, even when other targets succeed.
- Several critical flows rely on email side effects after the main DB mutation already succeeded.
- Integration-enabling settings such as OAuth and connector secrets are configuration-only and not visible in the admin UI.

## Prioritized Recommendations

- `P0` Extract the release-intake pipeline from `routes.py` into dedicated domain services with explicit transition helpers.
- `P1` Add clearer reconciliation or retry semantics for partially successful campaigns.
- `P1` Separate operational mail transport settings from message-template content.
- `P2` Rationalize manager-visible UI capabilities against actual route enforcement.

## Code References

- `apps/server/app/api/routes.py` - primary business flow concentration
- `apps/server/app/api/campaign_routes.py` - outbound campaign surface
- `apps/server/app/api/campaign_request_routes.py` - intake approval surface
- `apps/server/app/models/models.py` - domain entity inventory
- `apps/server/app/services/campaign_send.py` - aggregate delivery outcome
- `apps/server/app/services/release_link_discovery.py` - enrichment complexity
- `apps/server/app/services/mail_settings.py` - settings/template concentration
- `apps/server/worker.py` - automated execution scope
