# Glossary

**Last updated:** 2026-04-18

**Scope analyzed:** Domain terms visible in models, routes, services, and UI labels

**Confidence level:** High

---

## Terms

| Term | Definition | Notes |
|------|------------|-------|
| `Artist` | Core artist record used for portal login, profile metadata, releases, media, and inbox linkage | Not always the same thing as a `User` |
| `User` | LM-side authenticated account, usually `admin` or `manager`, but can also be linked to an artist | Separate table from `Artist` |
| Demo submission | Inbound music submission captured in `DemoSubmission` | Can originate from public form or artist portal |
| Pending release | Follow-up work item storing artist/release details after approval | Separate from final `Release` record |
| Campaign request | Artist request asking the label to run promotion for a release | Approval leads to next-step intake, not immediate publishing |
| Campaign | Unified outbound publishing object targeting social, Mailchimp, or WordPress | Distinct from `CampaignRequest` |
| Label inbox | Artist-wide conversation thread between artist and label | Separate from `PendingReleaseComment` |
| Pending-release comments | Release-specific conversation attached to a `PendingRelease` | Narrower than inbox |
| Release minisite | Public or preview release page driven by `Release.minisite_*` fields | Admin-managed |
| Artist minisite / public share page | Artist-facing share page driven mainly by `Artist.extra_json` and public linktree route | Artist-managed in portal |
| Link candidate | Potential platform URL discovered for a release | Reviewed before becoming active platform link |
| Scan run | One background or manual attempt to discover links for a release | Stored in `ReleaseLinkScanRun` |
| Hub connector | Generic stored integration connection such as Mailchimp or WordPress bridge | Distinct from social OAuth connection |
| Social connection | OAuth-backed connected social account used for publishing | Tokens stored encrypted when possible |
| Mail settings | Single-row persisted override for SMTP, backup SMTP, and template content | Couples transport and template concerns |
| `AutomationTask` | Artist-linked task record shown in some surfaces | `Needs validation` as a live automated workflow |

## Code References

- `apps/server/app/models/models.py` - most domain terms and persisted names
- `apps/server/app/api/routes.py` - workflow-oriented terms
- `apps/server/app/api/campaign_request_routes.py` - `CampaignRequest`
- `apps/server/app/api/inbox_routes.py` - label inbox terminology
- `apps/server/app/services/release_link_discovery.py` - scan/candidate terminology
- `apps/artist_portal/lib/features/dashboard/artist_dashboard_page.dart` - artist-facing wording
- `apps/client/lib/features/admin/tabs/release_links_tab.dart` - admin minisite/link-review wording
