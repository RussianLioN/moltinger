# Beads Worktree Localization Must Bootstrap And Import Without Moving HEAD

## Rule

When repo-local helpers materialize Beads state for a dedicated worktree in `partial_foundation` or legacy-localize mode:

1. Do not use `bd --db ... info` as a bootstrap/materialization probe.
2. Do not use `bd init --from-jsonl` inside Phase A or other base-anchored create flows.
3. If a stale incomplete `.beads/dolt/` shell exists, quarantine it under `.beads/recovery/` first.
4. Use the non-committing official path instead:
   - `bd bootstrap`
   - `bd --db .beads/beads.db import .beads/issues.jsonl`

## Why

- `bd --db ... info` can create a half-initialized Dolt shell without the named `beads` database.
- `bd init --from-jsonl` can commit tracked files and move `HEAD`, which violates Phase A's deterministic base-anchored contract.
- `bd bootstrap` plus explicit `import` materializes the named runtime and loads tracked issue state without changing git history.

## Required Guardrails

1. `tests/unit/test_worktree_phase_a.sh` must prove that `HEAD` remains equal to the requested base SHA after localization.
2. `tests/unit/test_bd_dispatch.sh` must cover stale-shell repair before re-materialization.
3. `tests/static/test_beads_worktree_ownership.sh` must ensure the helper still uses the bootstrap+import path and not the stale probe.
