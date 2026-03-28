# Validation Log: Worktree Ready UX

**Feature**: `005-worktree-ready-flow`
**Created**: 2026-03-08
**Purpose**: Record implementation-time validation runs against `quickstart.md`.

## Scenario Matrix

| Scenario | Source | Status | Notes |
|----------|--------|--------|-------|
| Existing branch, manual handoff | `quickstart.md` Scenario 1 | pass | Covered across attach preview, boundary, and rich-handoff fixtures in `tests/unit/test_worktree_ready.sh` |
| Existing branch with blocked environment | `quickstart.md` Scenario 2 | pass | Covered by blocked-env attach handoff contract fixture in `tests/unit/test_worktree_ready.sh` |
| New task, new branch flow | `quickstart.md` Scenario 3 | pending | |
| One-shot slug-only clean start | `quickstart.md` Scenario 4 | pass | Covered by `tests/unit/test_worktree_ready.sh` plan-mode fixture |
| Similar-name ambiguity | `quickstart.md` Scenario 5 | pass | Covered by `tests/unit/test_worktree_ready.sh` similar-branch fixture |
| Doctor mode | `quickstart.md` Scenario 6 | pending | |
| Stale registry during start flow | `quickstart.md` Scenario 7 | pending | |
| Opt-in terminal or Codex handoff | `quickstart.md` Scenario 8 | pass | Covered by explicit terminal dry-run launch and codex fallback fixtures in `tests/unit/test_worktree_ready.sh` |
| Stop-and-handoff boundary after create | `quickstart.md` Scenario 9 | pass | Covered by create boundary and mixed-request handoff fixtures in `tests/unit/test_worktree_ready.sh` |
| Machine-readable handoff contract | `quickstart.md` Scenario 10 | pass | Covered by create/attach `--format env` boundary and payload fixtures in `tests/unit/test_worktree_ready.sh` |
| Manual next steps are copy-paste friendly | `quickstart.md` Scenario 11 | pass | Covered by manual create handoff fixture that asserts fenced `bash` commands in `tests/unit/test_worktree_ready.sh` |
| Mixed request preserves downstream intent without breaking the boundary | `quickstart.md` Scenario 12 | pass | Verified by create rich-payload fixture, concise `pending`, and absence of duplicate short seed block in `tests/unit/test_worktree_ready.sh` |
| Attach flow preserves rich deferred payload | `quickstart.md` Scenario 13 | pass | Verified by attach rich-payload fixture plus attach boundary contract assertions in `tests/unit/test_worktree_ready.sh` |
| Canonical-root cleanup with GitHub-aware branch deletion | `quickstart.md` Scenario 14 | pass | Covered by cleanup lifecycle, idempotency, GitHub fallback, and degraded-auth fixtures in `tests/unit/test_worktree_ready.sh` plus resolver guard coverage in `tests/unit/test_bd_dispatch.sh` |
| Clean-create always starts from canonical main | latest mixed-request UAT | pending | Needs deterministic Phase A executor coverage |
| Mixed request does not create downstream artifacts | latest mixed-request UAT | pending | Must prove no Beads/spec side effects during Phase A |

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
  - `scripts/worktree-ready.sh create ... --pending-summary "<text>"` replaces the generic `Pending` value with a short summary
  - `scripts/worktree-ready.sh create ... --phase-b-seed-payload "<text>"` preserves richer deferred Phase B context separately
  - command-worktree guidance allows a dedicated `Phase B Seed Payload (deferred, not executed)` block only after the fenced `bash` block
  - the richer deferred payload remains advisory and does not imply Phase B execution in the originating session

### 2026-03-11 - Contract alignment targets for boundary hardening

- Goal:
  - align command guidance, helper schema, and manual handoff rendering around one short summary plus one optional richer deferred payload
- Checks:
  - both `create` and `attach` document the same hard stop-after-Phase-A boundary
  - `pending` is documented as concise summary-only
  - `phase_b_seed_payload` is documented as the richer deferred carrier for structured downstream requests
  - helper human output is treated as the canonical manual handoff payload
- Follow-up:
  - confirm runtime helper and regression tests match this documented contract once the parallel runtime changes land

### 2026-03-11 - Boundary and handoff hardening implementation pass

- Commands:
  - `bash -n scripts/worktree-ready.sh`
  - `bash -n tests/unit/test_worktree_ready.sh`
  - `./tests/unit/test_worktree_ready.sh`
- Observed:
  - create and attach handoff env output exposes the hard boundary plus separate optional `phase_b_seed_payload`
  - manual handoff renders the short `Phase B only` block only when no richer payload is present
  - structured downstream requests preserve a concise `Pending` summary plus a separate `Phase B Seed Payload (deferred, not executed)` block
  - opt-in terminal handoff can report `handoff_launched` without weakening the attach boundary
  - failed opt-in codex launch degrades to manual handoff while preserving `stop_after_attach`
- Result:
  - Scenarios 1, 2, 8, 9, 10, 11, 12, and 13 are now covered by the unit regression suite

### 2026-03-09 - Deterministic Phase A hardening

- Goal:
  - prevent wrong-parent branch creation, second refresh cycles, and Phase A leakage into downstream artifacts
- Checks:
  - `scripts/worktree-phase-a.sh create-from-base ...` creates the target branch/worktree from explicit `base_ref`/`base_sha`
  - existing drifted branches return a blocked exit code instead of in-place repair
  - manual handoff guidance now requires exact fenced `bash` output and optional fixed-template fenced `text`
- Follow-up:
  - rerun mixed-request UAT to confirm no `bd create`, no `.beads/issues.jsonl` mutation, and no post-create branch repair

### 2026-03-09 - Issue-aware bootstrap handoff

- Goal:
  - ensure manual handoff for issue-aware branches created from `main` includes an exact bootstrap import command when the target worktree lacks issue-linked foundation artifacts
- Checks:
  - `scripts/worktree-ready.sh create ...` renders `Bootstrap Source` and `Bootstrap Files` when issue-linked docs exist only in the invoking branch
  - fenced `bash` block includes `git checkout <source> -- .beads/issues.jsonl <issue-linked paths...>` before `direnv allow` / `codex`
  - env output exposes `bootstrap_source` and `bootstrap_file_*` fields for machine-readable orchestration

### 2026-03-09 - Speckit-compatible branch allocation

- Goal:
  - ensure Speckit-oriented create flows allocate or reuse numeric `NNN-<slug>` branches instead of creating legacy `feat/...` branches that must be normalized later
- Checks:
  - `./tests/unit/test_worktree_ready.sh`
  - explicit `--speckit` planning emits `001-codex-update-monitor` style branch names in a clean fixture repo
  - issue-driven planning for `molt-2` reuses an existing exact numeric branch such as `007-codex-update-monitor`
  - generic non-Speckit issue-aware planning still stays on legacy `feat/<issue>-<slug>` behavior

### 2026-03-09 - Doctor probe-state hardening

- Goal:
  - port the useful doctor UX from the 005 micro-branch without treating unavailable probes as missing readiness state
- Checks:
  - `./tests/unit/test_worktree_ready.sh`
  - branch-only doctor suppresses the false `already attached` warning
  - unavailable Beads probes do not force `bd worktree list` or a blocked doctor result by themselves
  - missing guard script does not produce `./scripts/git-session-guard.sh --refresh`
  - missing-worktree recovery routes back to managed attach flow instead of raw `bd worktree create`

### 2026-03-26 - Cleanup contract hardening

- Goal:
  - align the documented cleanup workflow with the real helper-backed lifecycle path and close the merge-proof gap for squash/rebase merged branches
- Checks:
  - `bash tests/unit/test_bd_dispatch.sh`
  - `bash tests/unit/test_worktree_ready.sh`
  - `bash tests/static/test_beads_worktree_ownership.sh`
  - `bash -n scripts/worktree-ready.sh`
  - `bash -n scripts/beads-resolve-db.sh`
- Observed:
  - canonical root now allows only the narrow `bd worktree remove <absolute-path>` admin path for linked worktrees
  - cleanup helper emits `worktree-cleanup/v1` and blocks mutation when invoked outside the canonical root worktree
  - linked worktree removal is verified against `git worktree list --porcelain`, including stale `prunable` cleanup
  - GitHub merged-PR metadata can prove safe delete for the same branch, base branch, and head SHA when git ancestry is inconclusive
  - local branch deletion switches to `git branch -D` only for the GitHub-verified merged-PR fallback, which avoids false negatives on squash/rebase merges
