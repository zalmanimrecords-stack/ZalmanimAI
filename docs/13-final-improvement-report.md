# Final improvement report (continuous-code-improver pass)

Pass date: 2026-05-02 (local).

## Commits created (this loop)

Use `git log` for hashes. Expected split:

1. **`fix(artist_portal)`** — `Color.withOpacity` instead of `withValues`; `DropdownButtonFormField` uses `value` instead of removed `initialValue` (matches pinned Flutter SDK analyzer).
2. **`chore(ci)`** — README testing note, `pre_release_checks.ps1` uses `flutter test --no-pub`, this report.

## Recommended-next continuation (previous pass)

| Item | Outcome |
|------|---------|
| Run Flutter tests beyond analyze | `flutter test --no-pub`: client **18**, artist portal **1**, all passed |
| `pre_release_checks.ps1` | Now uses **`flutter test --no-pub`**; full Flutter stage passes (`-SkipServer` verified) |
| Artist portal analyze | Was **26 errors** on older Color/Dropdown APIs — **fixed** in this loop |

## Validation

| Check | Result |
|-------|--------|
| `apps/server` pytest | **77 passed** |
| `apps/client` flutter analyze | **No issues** (prior pass) |
| `apps/client` flutter test --no-pub | **18 passed** |
| `apps/artist_portal` flutter analyze | **No issues** |
| `apps/artist_portal` flutter test --no-pub | **1 passed** |
| `scripts/pre_release_checks.ps1 -SkipServer` | **Passed** |

## What changed (summary)

- **Artist portal:** SDK-aligned opacity helpers and dropdown form field parameters (no UI behavior change intended).
- **README:** Clarify `flutter test` vs `dart test`; mention `--no-pub` for stable lockfiles.
- **`pre_release_checks.ps1`:** `flutter test --no-pub` for both Flutter apps.

## Suggested improvements

1. JWT `utcnow` deprecation (`python-jose`) — `worth-refactoring-soon`.
2. Server large-route/module split — only with tests — `unclear-needs-more-evidence`.

## Topics for treatment

- E2E / CI parity — `unclear-needs-more-evidence`.
- Remove duplicate improver skill under **Zalmanolator** — `acceptable-as-is`.

## New feature ideas

- None.

## Tests added or updated

- None (fixes restore analyzer compatibility; existing tests green).

## Dead code removed

- None.

## Docs / scripts updated

- `README.md`, `scripts/pre_release_checks.ps1`, this report.

## UI coverage findings

- Not scanned beyond compile/test validation.

## Performance findings

- None.

## Risks requiring human review

- Dropdown `value` vs prior `initialValue` must stay in sync with state — spot-check genre/release/theme pickers in the artist portal manually if anything feels off.

## Areas intentionally left unchanged

- Auth rules, billing, schema, secrets.

## Recommended next loop

1. Run full `pre_release_checks.ps1` including server on your machine or CI.
2. Optional: `flutter analyze --no-pub` in pre-release if your SDK supports it and skips unwanted resolution.
3. Narrow server test around one non-sensitive route helper.
