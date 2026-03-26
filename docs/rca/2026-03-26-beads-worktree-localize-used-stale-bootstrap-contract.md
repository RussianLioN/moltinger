---
title: "Beads worktree localization used stale bootstrap contracts and recreated the failure during Phase A"
date: 2026-03-26
severity: P1
category: process
tags: [beads, dolt, git-worktree, bootstrap, phase-a, rca]
root_cause: "The localization helper still relied on outdated Beads CLI assumptions: `bd --db ... info` was treated as a runtime-materialization probe even though it now creates a half-initialized Dolt shell with no named `beads` DB, and the first repair attempt (`bd init --from-jsonl`) was too heavy for Phase A because it moves HEAD by committing tracked files."
---

# RCA: Beads worktree localization used stale bootstrap contracts and recreated the failure during Phase A

Date: 2026-03-26  
Context: follow-up `moltinger-fng` after `032-post-close-task-classifier` was created from `main` but could not use local Beads state

## Error

Fresh worktrees created through `scripts/worktree-phase-a.sh create-from-base` could immediately fail with:

```text
database "beads" not found on Dolt server
```

The broken worktree ended up with `.beads/dolt/.dolt` but without `.beads/dolt/beads/.dolt` and without a healthy named `beads` database. A first repair attempt using `bd init --from-jsonl` proved that the runtime could be rebuilt, but it also committed tracked files and moved `HEAD`, which is incompatible with Phase A's base-anchored contract.

## Lessons Pre-Check

Before this RCA, the lessons index already contained the related incident [Half-initialized Beads Dolt runtime was misclassified as a healthy local worktree state](./2026-03-24-beads-half-initialized-dolt-runtime-misclassified-as-healthy.md). That RCA covered how helpers should classify an **existing** broken `.beads/dolt/` shell.

What it did **not** yet cover:

1. the localization helper itself still used an outdated CLI bootstrap probe that could **create** the broken shell during `partial_foundation` repair;
2. a seemingly correct repair path (`bd init --from-jsonl`) was incompatible with `worktree-phase-a` because it mutated git history inside the fresh worktree.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Why did fresh Phase A worktrees fail on `database "beads" not found`? | Because localization created `.beads/dolt/.dolt` but never materialized the named `beads` DB inside that runtime. |
| 2 | Why did localization create only the shell? | Because `scripts/beads-worktree-localize.sh` still treated `system bd --db <path> info` as a safe materialization probe. |
| 3 | Why was that probe wrong? | Because newer Beads CLI behavior no longer treats `info` as a lightweight bootstrap; it can create a Dolt shell and then fail closed if the named DB does not exist. |
| 4 | Why didn't the first repair attempt become the final fix? | Because `bd init --from-jsonl` rebuilt the runtime but also committed tracked files, which changed the fresh worktree `HEAD` and broke the Phase A invariant. |
| 5 | Why did both wrong paths remain in the repo? | Because repo-local helper logic had not been revalidated against the current official Beads CLI contract, and regression coverage checked only helper-local artifacts, not the full `worktree-phase-a -> localize -> live bd status` flow. |

## Root Cause

Repo-local localization logic depended on stale Beads CLI contracts. The old `bd info` bootstrap probe was no longer a safe way to materialize a local runtime, and the first replacement (`bd init --from-jsonl`) was not compatible with Phase A because it mutates git history. The correct non-committing path for this repository is: quarantine any stale incomplete shell, run `bd bootstrap` to materialize the named runtime, then run `bd --db .beads/beads.db import .beads/issues.jsonl`.

## Fixes Applied

1. Updated `scripts/beads-worktree-localize.sh` to quarantine incomplete `.beads/dolt` shells under `.beads/recovery/` before repair.
2. Replaced the stale materialization probe with the non-committing official path:
   - `bd bootstrap`
   - `bd --db .beads/beads.db import .beads/issues.jsonl`
3. Updated the legacy `scripts/beads-resolve-db.sh localize` path to use the same non-committing bootstrap/import flow.
4. Added a regression test covering stale-shell repair before re-init in `tests/unit/test_bd_dispatch.sh`.
5. Updated `tests/unit/test_worktree_phase_a.sh` so Phase A proves both invariants:
   - healthy named local runtime is created;
   - `HEAD` still matches the requested base SHA.
6. Re-ran a live disposable repro against the real system `bd` binary and confirmed:
   - `worktree-phase-a` exits `0`;
   - the new worktree contains `.beads/dolt/beads/.dolt`;
   - `bd info` points to the worktree-local `.beads/dolt`;
   - `bd status` no longer fails on `database "beads" not found`.

## Prevention

1. Do not use `bd --db ... info` as a bootstrap/materialization probe for worktree localization.
2. Do not use `bd init --from-jsonl` inside Phase A or other base-anchored worktree create flows unless git mutation is explicitly allowed.
3. For `partial_foundation` worktrees, use the official non-committing sequence:
   - `bd bootstrap`
   - `bd --db .beads/beads.db import .beads/issues.jsonl`
4. Any Beads bootstrap change must be validated against a real disposable `worktree-phase-a` repro, not only fake-bin unit tests.

## Related Updates

- [x] Helper fixed in [scripts/beads-worktree-localize.sh](/Users/rl/coding/moltinger/moltinger-main-032-post-close-task-classifier/scripts/beads-worktree-localize.sh)
- [x] Legacy localize path aligned in [scripts/beads-resolve-db.sh](/Users/rl/coding/moltinger/moltinger-main-032-post-close-task-classifier/scripts/beads-resolve-db.sh)
- [x] Phase A regression updated in [tests/unit/test_worktree_phase_a.sh](/Users/rl/coding/moltinger/moltinger-main-032-post-close-task-classifier/tests/unit/test_worktree_phase_a.sh)
- [x] Localization regressions updated in [tests/unit/test_bd_dispatch.sh](/Users/rl/coding/moltinger/moltinger-main-032-post-close-task-classifier/tests/unit/test_bd_dispatch.sh) and [tests/unit/test_beads_worktree_audit.sh](/Users/rl/coding/moltinger/moltinger-main-032-post-close-task-classifier/tests/unit/test_beads_worktree_audit.sh)
- [x] Guard check updated in [tests/static/test_beads_worktree_ownership.sh](/Users/rl/coding/moltinger/moltinger-main-032-post-close-task-classifier/tests/static/test_beads_worktree_ownership.sh)

## Уроки

- **Worktree bootstrap нельзя валидировать только fake-bin тестами** — нужен хотя бы один disposable repro на реальном CLI.
- **Официальный CLI path должен проверяться не только на “чинит”, но и на побочные эффекты** — `bd init --from-jsonl` восстановил runtime, но оказался несовместим с Phase A из-за git commit.
- **Broken runtime shell нужно не только распознавать, но и не создавать заново** — helper, который лечит `partial_foundation`, сам не должен превращать его в `database "beads" not found`.
