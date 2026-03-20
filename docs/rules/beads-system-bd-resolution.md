# Beads System `bd` Resolution

**Status:** Active  
**Effective date:** 2026-03-20  
**Scope:** repo-local `bin/bd`, `scripts/beads-resolve-db.sh`, `scripts/beads-worktree-localize.sh`, and any flow that delegates from a repo-local Beads wrapper to the installed system `bd`

## Problem This Rule Prevents

In a multi-worktree shell, `PATH` may contain `bin/bd` from a sibling worktree before the real installed `bd` binary. If wrapper resolution treats "first non-self `bd` on PATH" as the system binary, wrapper-to-wrapper delegation can recurse, hang, or route commands through the wrong worktree contract.

## Mandatory Policy

1. `beads_resolve_find_system_bd` must skip:
   - the current wrapper itself
   - any candidate that still looks like a repo-local wrapper, not a real installed `bd`
2. A candidate counts as repo-local wrapper if it lives under `bin/bd` and its repo root contains `scripts/beads-resolve-db.sh`.
3. Tests must cover a polluted `PATH` where a sibling worktree wrapper appears before the real system binary.
4. `BEADS_SYSTEM_BD` remains the explicit escape hatch for troubleshooting or unusual installations.

## Operational Meaning

- `whence -a bd` is a required diagnostic when Beads commands hang, recurse, or produce unexpected tracker drift.
- Do not assume that the shell's first `bd` after the current worktree is the installed system binary.
- If the wrapper and direct `/usr/local/bin/bd --no-daemon ...` behave differently, fix wrapper resolution before treating the JSONL export as the primary problem.

## Related RCA

- [RCA: Beads wrapper path pollution caused stale tracker export](/Users/rl/coding/moltinger/moltinger-main/docs/rca/2026-03-20-beads-wrapper-path-pollution-caused-stale-jsonl-export.md)
