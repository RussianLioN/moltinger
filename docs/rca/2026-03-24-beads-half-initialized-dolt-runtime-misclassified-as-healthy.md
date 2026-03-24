---
title: "Half-initialized Beads Dolt runtime was misclassified as a healthy local worktree state"
date: 2026-03-24
severity: P1
category: process
tags: [beads, dolt, git-worktree, runtime, bootstrap, rca]
root_cause: "Repo-local Beads helpers treated the existence of `.beads/dolt/` as proof of a healthy runtime, so a half-initialized Dolt store without the named `beads` database was misclassified as a valid post-migration state and recovery guidance drifted toward the wrong path."
---

# RCA: Half-initialized Beads Dolt runtime was misclassified as a healthy local worktree state

Date: 2026-03-24
Context: recovery of `030-rebase-conflict-tail-audit` after a preserved sibling worktree reported a Beads/Dolt blocker even though git state was clean

## Error

In `/Users/rl/coding/moltinger/moltinger-main-030-rebase-conflict-tail-audit`, Beads commands failed with `database "beads" not found` while `.beads/dolt/` already existed. The worktree therefore looked like it had a local Dolt runtime, but the named `beads` database inside that store was absent. Existing helper logic and some operator guidance were too willing to treat this as a normal post-migration runtime-only state or to steer operators toward the wrong recovery path.

Before this RCA, the lessons index already contained a related but narrower incident: [Beads wrapper path pollution caused stale tracker export](./2026-03-20-beads-wrapper-path-pollution-caused-stale-jsonl-export.md). That lesson covered wrapper dispatch/path pollution; it did **not** cover half-initialized Dolt stores being misclassified as healthy runtime.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Why did the sibling worktree still block on Beads even after earlier migration fixes? | Because the local Dolt store existed, but the named `beads` database inside it did not, so `bd` failed at runtime with `database "beads" not found`. |
| 2 | Why did the repo-local helpers not catch that state earlier? | Because `beads_resolve_has_local_runtime()` treated the existence of `.beads/dolt/` as enough evidence that the local runtime was healthy. |
| 3 | Why was that classification dangerous? | Because it collapsed two different states into one: `healthy post-migration runtime-only` and `half-initialized Dolt shell with no named DB`, which require different operator actions. |
| 4 | Why did operators drift into the wrong recovery path? | Because the helper messaging for `config + missing issues.jsonl + broken runtime` still implied generic missing foundation / localize-style recovery, instead of explicitly saying `runtime repair drift -> bd bootstrap -> do not restore JSONL`. |
| 5 | Why was this allowed to persist after migration work? | Because migration hardening focused on ownership, redirect, JSONL retirement, and wrapper path selection, but it did not add a regression test for `config + .beads/dolt shell + missing named beads DB`. |

## Root Cause

Repo-local Beads helpers used an overly weak health signal for Dolt-backed worktrees: a bare `.beads/dolt/` directory counted as a valid local runtime. That misclassified half-initialized Dolt stores as healthy post-migration state and sent operators toward the wrong repair semantics.

## Fixes Applied

1. Hardened `scripts/beads-resolve-db.sh` so a local Dolt runtime is considered healthy only when the named `beads` DB is actually materialized or another concrete local runtime artifact exists.
2. Added a dedicated runtime-only failure path that says `Tracked .beads/issues.jsonl is retired here; repair the local runtime instead of restoring JSONL.` and points operators to `/usr/local/bin/bd doctor --json && bd bootstrap`.
3. Updated `scripts/beads-worktree-localize.sh` to expose `runtime_bootstrap_required` for this exact state instead of reporting a generic missing-foundation diagnosis.
4. Added regression coverage in `tests/unit/test_bd_dispatch.sh` and `tests/unit/test_bd_local.sh`.
5. Updated shared Beads/Codex operator guidance and added rule [docs/rules/beads-dolt-runtime-shell-is-not-a-healthy-runtime.md](/Users/rl/coding/moltinger/moltinger-main/docs/rules/beads-dolt-runtime-shell-is-not-a-healthy-runtime.md).

## Prevention

1. Do not classify `.beads/dolt/` alone as a healthy runtime.
2. Treat `config + retired JSONL + missing named beads DB` as local runtime repair drift, not backlog loss.
3. When a preserved sibling worktree cannot read Beads after JSONL retirement, prefer `/usr/local/bin/bd doctor --json` and `bd bootstrap` before any manual `.beads` surgery.
4. Any new Beads runtime-state vocabulary must ship with a regression test for the broken state that motivated it.

## Related Updates

- [x] Rule added in [docs/rules/beads-dolt-runtime-shell-is-not-a-healthy-runtime.md](/Users/rl/coding/moltinger/moltinger-main/docs/rules/beads-dolt-runtime-shell-is-not-a-healthy-runtime.md)
- [x] Resolver hardened in [scripts/beads-resolve-db.sh](/Users/rl/coding/moltinger/moltinger-main/scripts/beads-resolve-db.sh)
- [x] Localization helper clarified in [scripts/beads-worktree-localize.sh](/Users/rl/coding/moltinger/moltinger-main/scripts/beads-worktree-localize.sh)
- [x] Regression tests added in [tests/unit/test_bd_dispatch.sh](/Users/rl/coding/moltinger/moltinger-main/tests/unit/test_bd_dispatch.sh) and [tests/unit/test_bd_local.sh](/Users/rl/coding/moltinger/moltinger-main/tests/unit/test_bd_local.sh)

## Уроки

- **`.beads/dolt/` сам по себе не означает здоровый runtime** — проверяй, что named DB `beads` действительно materialized.
- **Retired JSONL не должен возвращаться как repair crutch** — broken runtime-only state нужно чинить через `bd doctor`/`bd bootstrap`, а не через восстановление `.beads/issues.jsonl`.
- **Новый класс Beads runtime drift обязан получать отдельный regression-тест** — иначе helpers продолжат смешивать “healthy runtime-only” и “broken Dolt shell”.
