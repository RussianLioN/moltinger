# Beads Dolt-Native Cutover Notes

## Initial Inventory Baseline

This document records the first report-only baseline for `029-beads-dolt-native-migration`. It exists to capture readiness evidence before any pilot or rollout work starts.

## Boundary

- This is not a pilot run.
- This is not a cutover run.
- This is not a rollback run.
- The baseline is only the inventory/readiness verdict plus the initial blocker set.

## Baseline Command

```bash
./scripts/beads-dolt-migration-inventory.sh --format json
```

## Baseline Summary

- Verdict: `blocked`
- Pilot Gate: `blocked`
- Observed surfaces: `25/25`
- Worktrees discovered: `22`
- Blocking items: `32`
- Warning items: `14`

## Baseline Findings

- `bd --no-daemon info` already resolves to the current worktree-local database at `/Users/rl/coding/moltinger/029-beads-dolt-native-migration/.beads/beads.db`.
- `bd backend show` still reports `sqlite` and points at the canonical root `/Users/rl/coding/moltinger/moltinger-main/.beads`.
- The repo still carries the tracked legacy truth surface `.beads/issues.jsonl`.
- The repo still carries the dedicated JSONL normalizer and a pre-commit hook path that enforces JSONL-first behavior.
- Root `AGENTS.md`, `.beads/AGENTS.md`, Beads quickstarts, and Beads skill resources still prescribe legacy sync behavior.
- Every currently discovered live worktree classifies as `legacy_jsonl_first`, so the pilot gate remains blocked even before cutover logic exists.

## Initial Blocker Classes

- runtime backend mismatch and canonical-root coupling
- tracked `.beads/issues.jsonl`
- legacy JSONL normalizer and hook surfaces
- legacy docs, AGENTS, and skill guidance
- live worktrees still in `legacy_jsonl_first`

## Review Use

Use this baseline to answer only:

- what legacy surfaces still exist
- which blockers prevent pilot cutover
- whether repeated report-only runs remain deterministic

Do not interpret this baseline as permission to start pilot or rollout.
