# Final improvement report (continuous-code-improver pass)

Pass date: 2026-05-02 (local).

## Global skill install

The **continuous-code-improver** Cursor skill was copied to the personal (all-projects) location:

`%USERPROFILE%\.cursor\skills\continuous-code-improver\SKILL.md`

Per Cursor conventions, personal skills live under `~/.cursor/skills/`, not under `~/.cursor/skills-cursor/` (reserved for built-ins).

A copy still exists under `Zalmanolator\.cursor\skills\continuous-code-improver\`; consider removing it later to avoid drift (`worth-refactoring-soon`).

## This repository (ZalmanimAI)

### Baseline validation

- `cd apps/server && python -m pytest tests/ -q` → **77 passed** (warnings only).

### Commits created (this pass)

See git history for the commit that adds:

- `scripts/check-ssh-vps.ps1` — SSH probe using `Resolve-HostingerSshKey.ps1` and `-F NUL`; propagates `ssh` exit code.
- `deploy/DEPLOY_VPS.md` — documents the quick PowerShell check for broken Windows `.ssh/config` ACLs.

### Files intentionally not staged

Many edits under `docs/core-business-logic/*.md` were already modified before this pass and were left **unstaged** so this loop does not mix unrelated documentation changes.

### Suggested improvements

1. Resolve pytest cache permission warnings on Windows (`apps/server/.pytest_tmp`, `pytest-cache-files-*`) via `.gitignore` hygiene or cache dir outside restricted folders (`needs-refactor-now` if it blocks CI locally).
2. Align duplicate **continuous-code-improver** skill: single source in `~/.cursor/skills/` (`worth-refactoring-soon`).
3. Optional: reference the global skill from `README.md` under a short “Agent skills” note (`acceptable-as-is` until someone relies on Zalmanolator-only copy).

### Topics for treatment

- Flutter/client `dart analyze` / widget tests as a second baseline when touching `apps/client`.
- Split large API modules only with characterization tests (`unclear-needs-more-evidence` until profiled).

### New feature ideas

- None from this pass (ops/docs only).

### UI coverage findings

- Not re-scanned this pass (no UI edits).

### Performance findings

- None.

### Risks requiring human review

- None for the staged deploy/SSH changes.

### Recommended next loop

1. User: commit or stash existing `docs/core-business-logic/*` work, then rerun the skill on a clean branch.
2. Run `dart analyze` on `apps/client` and fix any quick wins.
3. Remove obsolete `Zalmanolator\.cursor\skills\continuous-code-improver` after confirming the global skill loads in Cursor.
