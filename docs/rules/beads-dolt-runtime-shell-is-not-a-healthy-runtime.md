# Beads Dolt Runtime Shell Is Not a Healthy Runtime

## Rule

Do not classify a worktree as having a healthy local Beads runtime just because `.beads/dolt/` exists.

The runtime counts as healthy only when at least one of these is true:

1. A usable local `beads.db` runtime artifact is present.
2. The Dolt data dir contains the named `beads` database.

If `.beads/config.yaml` exists, tracked `.beads/issues.jsonl` is already retired, and `.beads/dolt/` exists without the named `beads` DB:

1. Treat the state as **local runtime repair drift**.
2. Run `/usr/local/bin/bd doctor --json` first.
3. Recover with `./scripts/beads-worktree-localize.sh --path .` so stale runtime artifacts are quarantined before bootstrap is retried.
4. Import the newest compatibility issues backup (`issues*.jsonl`) found across `.beads/backup/` and `.beads/legacy-jsonl-backup/` when one exists.
5. Do **not** restore `.beads/issues.jsonl`.

## Why

A bare Dolt data directory can exist after a failed or partial bootstrap while the actual named `beads` database is still missing. That state is not backlog loss and must not be treated as proof that JSONL or canonical-root fallback should return.

## Required Guardrails

1. Repo-local Beads helpers must not report `post_migration_runtime_only` from a bare `.beads/dolt/` shell alone.
2. Recovery hints for runtime-only failures must point to the managed runtime-repair helper, not to raw `bd bootstrap` or JSONL restoration.
3. Regression tests must cover `config + .beads/dolt shell + missing named beads DB`, including the current Beads CLI behavior where raw `bd bootstrap` can no-op on that stale shell.
