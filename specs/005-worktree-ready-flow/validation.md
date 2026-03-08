# Validation Log: Worktree Ready UX

**Feature**: `005-worktree-ready-flow`
**Created**: 2026-03-08
**Purpose**: Record implementation-time validation runs against `quickstart.md`.

## Scenario Matrix

| Scenario | Source | Status | Notes |
|----------|--------|--------|-------|
| Existing branch, manual handoff | `quickstart.md` Scenario 1 | pending | |
| Existing branch with blocked environment | `quickstart.md` Scenario 2 | pending | |
| New task, new branch flow | `quickstart.md` Scenario 3 | pending | |
| One-shot slug-only clean start | `quickstart.md` Scenario 4 | pass | Covered by `tests/unit/test_worktree_ready.sh` plan-mode fixture |
| Similar-name ambiguity | `quickstart.md` Scenario 5 | pass | Covered by `tests/unit/test_worktree_ready.sh` similar-branch fixture |
| Doctor mode | `quickstart.md` Scenario 6 | pending | |
| Stale registry during start flow | `quickstart.md` Scenario 7 | pending | |
| Opt-in terminal or Codex handoff | `quickstart.md` Scenario 8 | pending | |

## Execution Notes

- Add one dated entry per validation pass.
- Record exact commands used, observed status output, and any follow-up fixes.
- Keep this log additive so it remains useful across multiple implementation commits.

### 2026-03-09 - Helper plan-mode regression pass

- Commands:
  - `./tests/unit/test_worktree_ready.sh`
  - `./tests/run_unit.sh --filter worktree_ready`
  - `./scripts/worktree-ready.sh plan --slug remote-uat-hardening --repo .`
- Observed:
  - helper derives clean branch/path for slug-only start without issue id
  - helper reuses exact attached worktrees instead of proposing duplicates
  - helper switches to `attach_existing_branch` for exact unattached local branches
  - helper switches to `needs_clarification` when only similar names exist
- Follow-up:
  - manual UAT from `uat/006-git-topology-registry` still pending for end-to-end Codex skill behavior
