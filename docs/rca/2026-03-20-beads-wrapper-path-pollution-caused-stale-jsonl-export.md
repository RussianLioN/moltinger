---
title: "Beads wrapper delegated into a sibling worktree wrapper and left stale JSONL export"
date: 2026-03-20
severity: P2
category: shell
tags: [beads, git-worktree, path, shell, rca]
root_cause: "The repo-local Beads wrapper treated the first non-self `bd` on PATH as the system binary, so a sibling worktree wrapper earlier on PATH could be selected and break normal sync/export flow."
---

# RCA: Beads wrapper path pollution caused stale tracker export

Date: 2026-03-20
Context: canonical `main` worktree cleanup after `.beads/issues.jsonl` was left dirty

## Error

`main` contained an unexpected local diff in tracked [`.beads/issues.jsonl`](/Users/rl/coding/moltinger/moltinger-main/.beads/issues.jsonl). The file was not random noise: the local Beads DB had newer issue state than the tracked JSONL export. During investigation, repo-local `bd` wrapper commands such as `bd info` could hang, while direct `/usr/local/bin/bd --db ... --no-daemon ...` worked immediately.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Why did `main` end up with a dirty `.beads/issues.jsonl`? | Because local Beads issue mutations existed in `.beads/beads.db`, but the tracked JSONL export was not reliably refreshed through the normal wrapper path. |
| 2 | Why was the normal wrapper path unreliable? | Because repo-local `bin/bd` could hang instead of reaching the real system `bd`, so operators fell back to direct commands or left the export stale. |
| 3 | Why could `bin/bd` hang? | Because `scripts/beads-resolve-db.sh` resolved the "system" `bd` as the first executable named `bd` on `PATH` that was not the current wrapper file. |
| 4 | Why was that wrong in this repository? | Because `PATH` can legitimately contain `bin/bd` from another sibling worktree; in the incident environment it resolved `/Users/rl/coding/moltinger/moltinger-028-beads-issues-jsonl-rca/bin/bd` before `/usr/local/bin/bd`. |
| 5 | Why was this not prevented earlier? | Because the resolver assumed `first non-self bd on PATH == system bd`, and the test suite did not cover sibling-worktree wrapper pollution ahead of the real binary. |

## Root Cause

The Beads wrapper used an unsafe system-binary discovery rule: it skipped only its own `bin/bd`, but it did not skip other repo-local wrappers from sibling worktrees. In a multi-worktree shell with leaked `PATH` entries, wrapper-to-wrapper delegation could recurse or hang, which in turn left tracker export state stale and produced dirty `.beads/issues.jsonl` diffs.

## Fixes Applied

1. Hardened `scripts/beads-resolve-db.sh` so `beads_resolve_find_system_bd` skips any candidate that still looks like a repo-local wrapper (`../scripts/beads-resolve-db.sh` sibling marker).
2. Added a unit regression test covering a polluted `PATH` where a sibling worktree wrapper appears before the real system `bd`.
3. Re-synced the tracker export on `main` only after confirming the issue state in the local DB and then pushed the cleanup commit.

## Prevention

1. Repo-local wrapper dispatch must never delegate into another repo-local wrapper from `PATH`.
2. Multi-worktree Beads tests must cover `PATH` pollution, not only self-wrapper skipping.
3. When Beads commands hang or tracked JSONL becomes dirty unexpectedly, inspect `whence -a bd` before assuming the DB or JSONL layer is at fault.

## Related Updates

- [x] Rule added in [docs/rules/beads-system-bd-resolution.md](/Users/rl/coding/moltinger/moltinger-main/docs/rules/beads-system-bd-resolution.md)
- [x] Unit test added in [tests/unit/test_bd_dispatch.sh](/Users/rl/coding/moltinger/moltinger-main/tests/unit/test_bd_dispatch.sh)
- [x] Resolver hardened in [scripts/beads-resolve-db.sh](/Users/rl/coding/moltinger/moltinger-main/scripts/beads-resolve-db.sh)

## Уроки

- **`PATH` в multi-worktree нельзя считать чистым** — sibling worktree wrappers могут легально оказаться раньше системного бинаря.
- **Wrapper должен уметь распознавать "своих" среди кандидатов** — правило "первый non-self executable" недостаточно для repo-local CLI shims.
- **Грязный tracked artifact часто вторичен** — сначала нужно проверять dispatch path и фактический исполняемый бинарь, а не лечить только экспортированный файл.
