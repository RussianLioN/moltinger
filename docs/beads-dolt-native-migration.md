# Beads Dolt-Native Migration

## Status

Phase B now covers three bounded layers:

- live-repo inventory/readiness and an explicit blocking gate
- one-worktree pilot-prep contract and review surface
- hermetic staged rollout/rollback proof

The live repository is still blocked. No live pilot enable or live rollout was executed from this worktree.

Do not start pilot or rollout from this step unless the readiness gate is explicitly clean for the target worktree.

## Target Contract Summary

- One active Beads operating model for everyday work.
- Direction aligned with upstream Dolt-native Beads.
- Tracked `.beads/issues.jsonl` must leave the primary truth flow before full cutover.
- Human and agent review must use one documented operator surface.

## Current Boundary

- Live inventory/readiness is the only active path on the real repository state.
- Pilot and rollout logic exist, but live execution stays blocked until the readiness gate clears.
- Rollout and rollback proof currently comes from hermetic fixtures, not from the shared repo state.
- Canonical-root cleanup is out of scope here.
- The existing `.beads/issues.jsonl` RCA stream remains separate.

## Inventory Model

The inventory runner covers these surface groups:

- runtime observations
- tracked artifacts
- repo-local scripts and wrappers
- git hooks
- docs, AGENTS, and skills guidance
- bootstrap paths
- legacy tests
- live worktree states

Every detected surface is classified as one of:

- `must-migrate`
- `can-bridge`
- `can-remove`
- `already-compatible`
- `blocked`

The readiness report emits:

- verdict: `ready`, `warning`, or `blocked`
- pilot gate: `pass` or `blocked`
- deterministic blocker list
- machine-readable JSON for human and agent review

## Commands

Human-readable report:

```bash
./scripts/beads-dolt-migration-inventory.sh
```

Machine-readable report:

```bash
./scripts/beads-dolt-migration-inventory.sh --format json
```

Explicit pilot gate:

```bash
./scripts/beads-dolt-migration-inventory.sh --format env --gate pilot
```

Pilot status / enable / review:

```bash
./scripts/beads-dolt-pilot.sh status
./scripts/beads-dolt-pilot.sh enable
./scripts/beads-dolt-pilot.sh review
```

Rollout report / cutover / verify / rollback:

```bash
./scripts/beads-dolt-rollout.sh report-only --format json
./scripts/beads-dolt-rollout.sh cutover --worktree .
./scripts/beads-dolt-rollout.sh verify --worktree .
./scripts/beads-dolt-rollout.sh rollback --package-id <id> --worktree .
```

## Migration Review Surfaces

The migration review surfaces are command-first, not JSONL-first.

- Enable pilot mode only in one isolated dedicated worktree.
- When `.beads/pilot-mode.json` exists, legacy-only paths such as `bd sync` are expected to fail closed.
- Review pilot state through `./scripts/beads-dolt-pilot.sh review`.
- When `.beads/cutover-mode.json` exists, legacy-only paths such as `bd sync`, JSONL normalization, and localization helpers are expected to fail closed.
- Verify cutover state through `./scripts/beads-dolt-rollout.sh verify --worktree .`.

These commands are meant to stay:

- human-readable
- agent-readable
- deterministic
- independent from tracked `.beads/issues.jsonl` as the primary review surface

## Local Runtime Notes

- Keep this phase report-only even if local `bd` exposes `migrate dolt`, `backend`, `branch`, or `vc`.
- Known local divergence matters: repo-local wrapper `bd sync` may hang, while direct system `bd --no-daemon` behavior differs. The inventory flow therefore prefers the legacy `bd --no-daemon info` / `bd backend show` probes when available, but falls back to `bd info` and `bd doctor --json` on newer official CLIs. It still does not call `sync`.
- For ordinary non-migration sync on this branch, use direct system `bd --no-daemon --db "$PWD/.beads/beads.db" sync` if the repo-local wrapper path hangs.
