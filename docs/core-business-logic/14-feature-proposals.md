# Feature Proposals

**Last updated:** 2026-04-18

**Scope analyzed:** Existing domains, entities, and workflows currently implemented in code

**Confidence level:** Medium

---

## Proposals

| Feature title | Problem/opportunity | Target actors | Domain fit | Reused components | Required changes | Priority | Risks/constraints | Confidence | Validation plan |
|---------------|---------------------|---------------|------------|-------------------|----------|----------|-------------------|------------|-----------------|
| Pending-release checklist and completion stages | Current `PendingRelease.status` is coarse and JSON fields already encode multiple sub-steps like mastering, images, comments, and metadata completeness | Admin, artist | Pending release completion | `PendingRelease`, comments, reminders, image options, artist portal release page | Add staged completeness fields and progress UI for artist/admin | P1 | Must avoid breaking existing pending-release API payloads | High | Pilot on admin detail page and compare operator throughput |
| Failed-target campaign retry action | Campaigns can partially succeed but only expose aggregate `failed` at the campaign level | Admin | Campaign delivery | `CampaignDelivery`, `CampaignTarget`, worker send flow | Add route/UI to retry only failed targets using existing target definitions | P1 | Needs idempotency review for external channels | High | Create mixed-success fixture and verify only failed targets rerun |
| Approval delivery fallback inside admin inbox | Demo/campaign approvals depend on email for next-step links | Admin | Demo review, campaign-request approval | inbox system, token generators, mail templates | When send fails, create actionable inbox/log item with resend/copy-link actions | P1 | Must avoid leaking raw tokens to wrong users | Medium | Induce SMTP failure and confirm operator can still complete workflow |
| Artist-facing pending-release timeline | Artists can submit details and comments, but there is no explicit timeline of label actions beyond current status/comments | Artist | Pending release follow-up | `PendingReleaseComment`, reminders, status fields, artist portal release page | Add event timeline entries for approval, reminder, comment, image updates, and processing | P2 | Requires deciding which events are business-relevant versus noisy | Medium | User-test timeline usefulness with a few real pending releases |
| Release-link review prioritization | Link discovery may produce many candidates, but review urgency is not explicitly ranked beyond confidence | Admin | Release enrichment | candidate confidence, scan summaries, release-links tab | Add queue view sorted by confidence and missing-platform importance | P2 | Confidence score alone may not capture business priority | Medium | Track review time-to-approve before and after introducing prioritization |
| Artist self-serve campaign draft handoff | Artists can request campaigns, but cannot prepare draft content before admin publication work starts | Artist, admin | Campaign request and outbound campaigns | `CampaignRequest`, artist dashboard, `Campaign` target model | Let artists attach draft copy/media intent to campaign requests for admin refinement | P2 | Needs careful role boundary so artists do not publish directly | Medium | Trial on one release workflow and compare back-and-forth comments |

## Code References

- `apps/server/app/api/routes.py` - pending-release, release, and reminder flows
- `apps/server/app/api/campaign_request_routes.py` - request lifecycle
- `apps/server/app/api/campaign_routes.py` - campaign lifecycle
- `apps/server/app/api/inbox_routes.py` - operator communication path
- `apps/server/app/services/campaign_send.py` - delivery result model
- `apps/server/app/services/release_link_discovery.py` - candidate scoring/review
- `apps/server/app/models/models.py` - reusable entities
