# Beads Dolt-Native Migration

## Status

Phase B, iteration 1 is intentionally limited to the inventory/readiness path. This step is report-only: it inventories legacy Beads surfaces, emits a deterministic readiness report, and places a blocking gate in front of pilot cutover.

Do not start pilot or rollout from this step. Pilot, controlled cutover, and rollback remain separate later phases after the inventory gate is clean.

## Target Contract Summary

- One active Beads operating model for everyday work.
- Direction aligned with upstream Dolt-native Beads.
- Tracked `.beads/issues.jsonl` must leave the primary truth flow before full cutover.
- Human and agent review must use one documented operator surface.

## Current Boundary

- Inventory/readiness is the only active migration path in this phase.
- Full cutover is out of scope here.
- Rollout and rollback are out of scope here.
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

## Local Runtime Notes

- Keep this phase report-only even if local `bd` exposes `migrate dolt`, `backend`, `branch`, or `vc`.
- Known local divergence matters: repo-local wrapper `bd sync` may hang, while direct system `bd --no-daemon` behavior differs. The inventory flow therefore inspects `bd --no-daemon info` and `bd backend show`, but does not call `sync`.
