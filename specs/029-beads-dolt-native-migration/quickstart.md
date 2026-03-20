# Quickstart: Beads Dolt-Native Migration

## Goal

Validate the migration design without applying a full repository cutover.

## Scenario 1: Inventory / Report-Only

1. Start from the `029-beads-dolt-native-migration` worktree.
2. Run the inventory/report-only workflow: `./scripts/beads-dolt-migration-inventory.sh --format json`.
3. Confirm the report lists:
   - repo-local wrappers
   - hook-based JSONL rewrites
   - docs/skills still prescribing `bd sync`
   - worktree/bootstrap surfaces
   - current backend/runtime status
4. Confirm the report produces a deterministic readiness verdict.

Expected result:

- No mutating cutover occurs.
- Critical blockers are explicit.
- Re-running the report without repo changes yields the same readiness verdict.

Current captured result from the live worktree:

- verdict: `blocked`
- pilot gate: `blocked`
- observed surfaces: `25/25`
- discovered worktrees: `22`
- blockers: `32`
- warnings: `14`

## Scenario 2: Pilot Worktree Cutover

1. Prepare one isolated pilot worktree that passes readiness checks.
2. Run the pilot workflow:
   - `./scripts/beads-dolt-pilot.sh status --format json`
   - `./scripts/beads-dolt-pilot.sh enable`
   - `./scripts/beads-dolt-pilot.sh review`
3. Execute a representative issue lifecycle in the pilot.
4. Confirm legacy-only surfaces are blocked or redirected with explicit messaging.
5. Confirm the new operator/review surface is usable without legacy JSONL-first reasoning.

Expected result:

- Pilot either passes cleanly, fails cleanly, or blocks cleanly.
- No silent fallback to the legacy JSONL-first workflow occurs.

Current captured result from the live worktree:

- `pilot_gate=blocked`
- `pilot_mode_enabled=false`

Validated by fixtures:

- `bash tests/unit/test_beads_dolt_pilot.sh`

## Scenario 3: Controlled Rollout

1. Start from a verified pilot pass.
2. Run rollout in staged mode:
   - `./scripts/beads-dolt-rollout.sh report-only --format json`
   - `./scripts/beads-dolt-rollout.sh cutover --worktree <ready-worktree>`
   - `./scripts/beads-dolt-rollout.sh verify --worktree <ready-worktree>`
3. Confirm only ready worktrees enter cutover.
4. Confirm blocked worktrees remain blocked with explicit reasons.

Expected result:

- No hidden mixed mode remains after the stage completes.
- Docs and operator guidance align with the active contract.

Validated by fixtures:

- ready and blocked worktrees appear together in report-only output
- eligible worktrees receive `.beads/cutover-mode.json`
- blocked worktrees remain visible and do not silently cut over
- mixed mode fails verification

## Scenario 4: Rollback

1. Start from a pilot or partial rollout state with a saved rollback package.
2. Trigger rollback: `./scripts/beads-dolt-rollout.sh rollback --package-id <id> --worktree <cutover-worktree>`.
3. Confirm snapshots and evidence are preserved.
4. Confirm operator usability is restored.

Expected result:

- Rollback restores a coherent operator path.
- Issue-state evidence and migration journals remain available.

Validated by fixtures:

- rollback restores the saved pre-cutover snapshot
- `.beads/rollback-state.json` records the reversal
- post-rollback verification remains explicit instead of silently re-entering mixed mode

## Focused Validation Run

This iteration was validated with:

- `bash tests/unit/test_beads_dolt_rollout.sh`
- `bash tests/unit/test_beads_dolt_inventory.sh`
- `bash tests/unit/test_bd_dispatch.sh`
- `bash tests/unit/test_beads_worktree_audit.sh`
- `bash tests/unit/test_beads_dolt_pilot.sh`
- `bash tests/unit/test_worktree_ready.sh`
- `bash tests/unit/test_beads_normalize_issues_jsonl.sh`
- `bash tests/static/test_beads_worktree_ownership.sh`
- `bash tests/static/test_beads_dolt_docs_alignment.sh`
