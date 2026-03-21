# Rule: Beads Post-Migration Local Runtime State

## Problem

After the Beads Dolt migration and local-only cleanup, some preserved sibling
worktrees intentionally no longer track `.beads/issues.jsonl` in git. Agents
must not misread that as backlog loss or as an unexpected deletion that should
be restored from `HEAD`.

## Rule

Treat the following combination as an expected post-migration local-runtime
state:

- `.beads/config.yaml` exists
- a local Beads runtime exists (`.beads/beads.db` or `.beads/dolt/`)
- tracked `.beads/issues.jsonl` is absent

In that state:

1. The backlog source of truth is the worktree-local Beads runtime.
2. Read-only inspection should continue via local `bd` first:
   - `bd status`
   - `bd list --limit <n>`
   - `bd ready`
   - `bd show <id>`
3. Do not restore `.beads/issues.jsonl` from `HEAD` just to silence tooling.
4. If local Beads access fails, describe it as a local Beads repair problem.
5. Run read-only diagnostics first:
   - `/usr/local/bin/bd doctor --json`
6. Only then use repair helpers such as:
   - `./scripts/beads-worktree-localize.sh --path .`
   - `bd bootstrap`

## Implementation Notes

- `scripts/beads-worktree-localize.sh` and `scripts/beads-worktree-audit.sh`
  must recognize this state explicitly.
- Compatibility wrappers such as `scripts/bd-local.sh` must defer to the same
  resolver semantics as `bin/bd`.
- Prompt/instruction layers must explicitly say that missing tracked JSONL does
  not imply that the backlog is unavailable.
