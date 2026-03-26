# RCA: Beads inventory doctor probe can hang landing flows

- Date: 2026-03-26
- Scope: `scripts/beads-dolt-migration-inventory.sh`, `scripts/beads-dolt-pilot.sh`, `scripts/beads-dolt-rollout.sh`
- Pre-check: `./scripts/query-lessons.sh --all | grep -iE 'doctor --json|bd doctor|hang|timeout|backend show|no-daemon info'`
- Result: no exact prior lesson for hanging `bd doctor --json` inside migration inventory probes

## Summary

`bd doctor --json` could hang indefinitely during Beads migration inventory fallback. Because pilot review and rollout verify both depend on the inventory report, one hung doctor probe could stall otherwise healthy landing flows even after code and runtime state were already correct.

## Impact

- `./scripts/beads-dolt-rollout.sh verify --worktree .` could stall in cutover worktrees
- `./scripts/beads-dolt-pilot.sh review` could stall in pilot worktrees
- Landing sequence became non-deterministic and blocked `git push`

## 5 Whys

1. Why did landing stall?
   Because the migration verify/review surface waited forever inside inventory generation.
2. Why did inventory generation wait forever?
   Because the backend fallback called `bd doctor --json` without a bounded runtime.
3. Why was the fallback path unbounded?
   Because inventory assumed failed probes would return quickly with an exit code, not hang.
4. Why was that assumption wrong?
   Because some worktrees can enter a runtime state where `bd doctor --json` blocks while trying to resolve or connect local Dolt metadata.
5. Why was this not caught earlier?
   Because inventory tests covered success and error fallbacks, but not a hanging fallback probe.

## Root Cause

Migration inventory probes used blocking `bd` subprocess calls without a timeout budget. A hung `bd doctor --json` fallback could freeze pilot/cutover review surfaces and therefore the whole landing workflow.

## Fix

- Added bounded `bd` probe execution in `scripts/beads-dolt-migration-inventory.sh`
- Normalized timed-out probes to explicit timeout signals instead of indefinite waits
- Added regression coverage in `tests/unit/test_beads_dolt_inventory.sh` for hanging `bd doctor --json`

## Preventive Actions

- Treat all operational `bd` probes used in review/verify surfaces as bounded probes
- Add timeout-specific regression cases whenever a new fallback probe is introduced
- Prefer explicit timeout signals in machine-readable outputs over silent hangs

## Lessons

1. Read-only or diagnostic probes still need time budgets in landing-critical paths.
2. A fallback path is part of the operator contract and must be tested for hangs, not only for failures.
3. Landing workflows should degrade to explicit blocked verdicts, never to infinite waits.
