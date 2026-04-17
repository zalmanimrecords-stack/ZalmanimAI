# Glossary

**Last updated:** 2026-04-17

**Scope analyzed:** Business terms visible in code, models, routes, and UI text

**Confidence level:** Medium

---

| Term | Definition | Notes |
|------|------------|-------|
| `Artist` | Core person/brand record used for portal access, releases, inbox, and outreach. | Distinct from LM `User`. |
| `User` | LM-side authenticated account for admin/manager, and sometimes artist-linked identity. | Role-based access anchor. |
| `DemoSubmission` | Intake record for music sent to the label. | Can originate from public form or artist portal. |
| `CampaignRequest` | Artist-originated request that can be approved into a pending-release form flow. | Not the same as outbound `Campaign`. |
| `PendingRelease` | Release-preparation work item holding artist/release details before label processing. | Central queue-like entity. |
| `Release` | Published or prepared release record with links, cover art, and minisite data. | Can exist as placeholder after catalog sync. |
| `ReleaseLinkCandidate` | One discovered possible platform URL for a release. | Requires review or auto-rejection. |
| `ReleaseLinkScanRun` | One background/manual scan execution against music platforms. | Worker processes queued runs. |
| `Campaign` | Outbound content package sent to social, Mailchimp, and/or WordPress. | Lifecycle: draft to sent/failed. |
| `CampaignTarget` | Per-channel destination for a campaign. | Stores connector/social IDs plus payload JSON. |
| `CampaignDelivery` | Result row for one target send attempt. | Used to summarize campaign outcome. |
| `SocialConnection` | Connected social publishing account. | Stores encrypted tokens. |
| `HubConnector` | Generic integration record for external tools such as Mailchimp or WordPress. | Connector config lives in JSON. |
| `MailSettings` | Single-row operational and template settings store. | Combines transport config and message templates. |
| `LabelInboxThread` | Conversation between artist and label. | Loosely coupled to release workflows. |
| `AutomationTask` | Artist-associated automation/task record. | Current runtime use is `Needs validation`. |

## Code References

- `apps/server/app/models/models.py` - term definitions through entity names and comments
- `apps/server/app/api/routes.py` - operational meaning of intake/release/campaign terms
- `apps/server/app/api/campaign_request_routes.py` - `CampaignRequest` meaning
- `apps/server/app/api/inbox_routes.py` - inbox terminology
- `apps/client/lib/features/admin/tabs/settings_tab.dart` - visible admin terminology
