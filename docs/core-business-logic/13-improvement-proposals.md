# Improvement Proposals

**Last updated:** 2026-04-17

**Scope analyzed:** Current business-flow implementation, hotspots, and operational settings surfaces

**Confidence level:** Medium

---

| Proposal title | Category | Current evidence | Impact | Scope | Suggested approach | Priority | Risk level | Confidence | Validation plan |
|-------|---------|---------|---------|---------|---------|---------|---------|---------|---------|
| Extract intake workflow services | Architecture | `app/api/routes.py` owns demo approval, artist linking, pending-release creation, and related email side effects inline. | Reduces drift and makes approval/review changes safer. | Demo, campaign request, pending release, inbox seeding flows. | Move lifecycle mutations into small domain services with explicit transition methods and tests. | P0 | Medium | High | Add tests around approval, rejection, reminder, and token generation paths before/after extraction. |
| Introduce typed status constants or enums | Architecture | Multiple entities use raw status strings across routes and services. | Lowers risk of inconsistent transitions and improves maintainability. | Campaigns, demos, requests, pending releases, link candidates, scan runs. | Centralize allowed states and transition helpers. | P1 | Low | High | Add unit tests for invalid transitions and schema serialization. |
| Add per-target campaign retry/reconciliation | Performance / Architecture | `campaign_send.py` marks the whole campaign failed when any target fails, while successful deliveries remain persisted. | Improves operational recovery without rebuilding whole campaigns. | Campaign send worker and admin campaign review UX. | Track target retry eligibility and expose retry action for failed deliveries only. | P1 | Medium | Medium | Simulate one-target failure with others succeeding and verify targeted re-run behavior. |
| Separate mail transport config from message templates | Architecture / Security | `MailSettings` stores SMTP credentials, limits, footer, and all template text in one row. | Shrinks blast radius of changes and allows better validation/access partitioning. | `MailSettings`, settings routes, admin settings UI. | Split transport settings and template library into separate persistence/API surfaces. | P1 | Medium | Medium | Verify admin UI still loads/saves both surfaces and that all email flows resolve templates correctly. |
| Harden integration visibility and startup diagnostics | Security / Architecture | Integration-critical values such as OAuth and connector env vars are not visible in the admin UI, yet they determine publish/connect viability. | Speeds support and reduces hidden misconfiguration. | Config, settings UI, health/status endpoints. | Expose redacted integration readiness flags in admin settings or health diagnostics without revealing secrets. | P2 | Low | Medium | Add an admin status screen showing configured/not configured per integration. |

## Code References

- `apps/server/app/api/routes.py` - intake workflow concentration
- `apps/server/app/models/models.py` - status fields and `MailSettings`
- `apps/server/app/services/campaign_send.py` - aggregate failure behavior
- `apps/server/app/services/mail_settings.py` - mixed config/template persistence
- `apps/server/app/core/config.py` - hidden integration configuration surface
- `apps/client/lib/features/admin/tabs/settings_tab.dart` - current settings exposure
