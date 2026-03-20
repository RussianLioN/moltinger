# Beads Dolt-Native Cutover Notes

## Current Boundary

- The live repository is still blocked for pilot and cutover.
- No live-repo pilot enable, staged cutover, or rollback was executed from this worktree.
- Pilot and rollout behavior below is validated in hermetic fixture worktrees only.
- Canonical-root cleanup remains out of scope.

## Initial Inventory Baseline

This is the report-only baseline captured from the real `029-beads-dolt-native-migration` worktree before any live cutover.

### Baseline Command

```bash
./scripts/beads-dolt-migration-inventory.sh --format json
```

### Baseline Summary

- Verdict: `blocked`
- Pilot Gate: `blocked`
- Observed surfaces: `25/25`
- Worktrees discovered: `22`
- Blocking items: `32`
- Warning items: `14`

### Baseline Findings

- `bd --no-daemon info` already resolves to the current worktree-local database at `/Users/rl/coding/moltinger/029-beads-dolt-native-migration/.beads/beads.db`.
- `bd backend show` still reports `sqlite` and points at the canonical root `/Users/rl/coding/moltinger/moltinger-main/.beads`.
- The repo still carries the tracked legacy truth surface `.beads/issues.jsonl`.
- The repo still carries the dedicated JSONL normalizer and a pre-commit hook path that enforces JSONL-first behavior.
- Root `AGENTS.md`, `.beads/AGENTS.md`, Beads quickstarts, and Beads skill resources still prescribe legacy sync behavior.
- Every currently discovered live worktree classifies as `legacy_jsonl_first`, so the pilot gate remains blocked even before cutover logic exists.

### Initial Blocker Classes

- runtime backend mismatch and canonical-root coupling
- tracked `.beads/issues.jsonl`
- legacy JSONL normalizer and hook surfaces
- legacy docs, AGENTS, and skill guidance
- live worktrees still in `legacy_jsonl_first`

## Pilot Contract

Pilot mode is an isolated single-worktree bridge, not a repo-wide cutover.

Commands:

```bash
./scripts/beads-dolt-pilot.sh status --format json
./scripts/beads-dolt-pilot.sh enable
./scripts/beads-dolt-pilot.sh review
```

Pilot guarantees:

- `.beads/pilot-mode.json` is the explicit local marker.
- `bd sync` fails closed while pilot mode is active.
- staged `.beads/issues.jsonl` is blocked in pre-commit.
- the documented review surface is `./scripts/beads-dolt-pilot.sh review`.

Scoped-gate semantics:

- `pilot_gate` is current-worktree scoped.
- `full_cutover_gate` is current-worktree or explicit-target scoped.
- `fleet_residual_gate` reports legacy sibling worktrees outside the active scope.

## Hermetic Rollout And Rollback Proof

Validated through `bash tests/unit/test_beads_dolt_rollout.sh`.

Covered outcomes:

- `report-only` shows both ready and blocked worktrees in one deterministic report.
- `cutover` writes `.beads/cutover-mode.json` only for eligible worktrees and emits a rollback package manifest.
- blocked worktrees remain visible and do not silently enter mixed mode.
- `verify` fails when mixed mode is reintroduced and expects legacy `bd sync` to stay blocked.
- `rollback` restores the saved snapshot, removes cutover-only state, and writes `.beads/rollback-state.json`.

Operator commands:

```bash
./scripts/beads-dolt-rollout.sh report-only --format json
./scripts/beads-dolt-rollout.sh cutover --worktree .
./scripts/beads-dolt-rollout.sh verify --worktree .
./scripts/beads-dolt-rollout.sh rollback --package-id <id> --worktree .
```

## Review Use

Use this document to answer:

- whether the active worktree passed pilot and cutover
- what residual fleet cleanup still remains outside the active scope
- what review surface applies in inventory, pilot, and cutover modes
- what the hermetic rollout and rollback proof already covers

Do not interpret the hermetic rollout proof as permission to start live repo cutover.
