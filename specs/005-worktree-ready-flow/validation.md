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
| Stop-and-handoff boundary after create | `quickstart.md` Scenario 9 | pending | |
| Machine-readable handoff contract | `quickstart.md` Scenario 10 | pending | |
| Manual next steps are copy-paste friendly | `quickstart.md` Scenario 11 | pending | |

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

### 2026-03-09 - Stop-and-handoff contract regression pass

- Commands:
  - `./tests/unit/test_worktree_ready.sh`
  - `./tests/run_unit.sh --filter worktree_ready`
- Observed:
  - helper emits `boundary` and `final_state` fields for create/attach flows
  - helper exports shell-safe `key=value` handoff output via `--format env`
  - ambiguous plan requests return exit code `10`
  - missing attach branch returns `blocked_missing_branch`
- Follow-up:
  - manual UAT still required to confirm that `command-worktree` now stops after Phase A instead of continuing downstream work in the originating session

### 2026-03-09 - UAT follow-up requirements

- Latest UAT confirmed that:
  - managed create-flow now stops at the handoff boundary
  - topology refresh succeeds from the invoking branch
- New follow-up expectations:
  - if topology refresh changed `docs/GIT-TOPOLOGY-REGISTRY.md`, the invoking branch should land and push that mutation before returning the final handoff block
  - manual next-step commands should be duplicated in a fenced `bash` block for easier copy-paste

### 2026-03-09 - Mixed-request handoff enrichment

- Goal:
  - preserve explicit downstream intent in the handoff payload without weakening the hard Phase A/Phase B boundary
- Checks:
  - `scripts/worktree-ready.sh create ... --pending-summary "<text>"` replaces the generic `Pending` value
  - command-worktree guidance allows an optional `Phase B Seed Prompt (optional, not executed)` only after the fenced `bash` block
  - the seed prompt remains advisory and does not imply Phase B execution in the originating session
