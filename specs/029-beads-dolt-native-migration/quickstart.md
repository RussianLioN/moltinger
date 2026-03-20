# Quickstart: Beads Dolt-Native Migration

## Goal

Validate the migration design without applying a full repository cutover.

## Scenario 1: Inventory / Report-Only

1. Start from the `029-beads-dolt-native-migration` worktree.
2. Run the inventory/report-only workflow.
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

## Scenario 2: Pilot Worktree Cutover

1. Prepare one isolated pilot worktree that passes readiness checks.
2. Run the pilot cutover workflow.
3. Execute a representative issue lifecycle in the pilot.
4. Confirm legacy-only surfaces are blocked or redirected with explicit messaging.
5. Confirm the new operator/review surface is usable without legacy JSONL-first reasoning.

Expected result:

- Pilot either passes cleanly, fails cleanly, or blocks cleanly.
- No silent fallback to the legacy JSONL-first workflow occurs.

## Scenario 3: Controlled Rollout

1. Start from a verified pilot pass.
2. Run rollout in staged mode.
3. Confirm only ready worktrees enter cutover.
4. Confirm blocked worktrees remain blocked with explicit reasons.

Expected result:

- No hidden mixed mode remains after the stage completes.
- Docs and operator guidance align with the active contract.

## Scenario 4: Rollback

1. Start from a pilot or partial rollout state with a saved rollback package.
2. Trigger rollback.
3. Confirm snapshots and evidence are preserved.
4. Confirm operator usability is restored.

Expected result:

- Rollback restores a coherent operator path.
- Issue-state evidence and migration journals remain available.
