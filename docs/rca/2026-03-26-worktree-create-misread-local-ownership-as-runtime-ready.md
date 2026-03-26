---
title: "Managed worktree creation misread local Beads ownership as runtime readiness"
date: 2026-03-26
severity: P1
category: process
tags: [beads, dolt, git-worktree, runtime, readiness, bootstrap, rca]
root_cause: "Managed worktree flows treated `beads_state=local` as sufficient proof that a new worktree was ready, but they did not run a bounded local runtime-health probe. As a result, freshly created worktrees with local ownership but no named `beads` DB were handed off as ready and agents burned iterations on ad-hoc recovery."
---

# RCA: Managed worktree creation misread local Beads ownership as runtime readiness

Date: 2026-03-26
Context: creation of `032-post-close-task-classifier` from `031-moltis-reliability-diagnostics`

## Lessons Pre-check

Before writing this RCA, the lessons index was queried for related incidents. Relevant prior lessons were:

1. [2026-03-20: Beads wrapper path pollution caused stale tracker export](./2026-03-20-beads-wrapper-path-pollution-caused-stale-jsonl-export.md)
2. [2026-03-24: Half-initialized Beads Dolt runtime was misclassified as a healthy local worktree state](./2026-03-24-beads-half-initialized-dolt-runtime-misclassified-as-healthy.md)
3. [2026-03-26: Beads inventory doctor probe can hang landing](./2026-03-26-beads-inventory-doctor-probe-can-hang-landing.md)

Those lessons covered wrapper selection, half-initialized Dolt shells, and bounded probing. They did **not** yet close the gap between `ownership is local` and `runtime is actually ready` in the managed worktree create/doctor/handoff flow.

## Error

During creation of a new dedicated worktree, the workflow reported Beads ownership as local and allowed the agent to continue, but the new worktree could not actually open its Beads runtime because the named `beads` DB was missing. The session then spent multiple iterations bouncing between `bd doctor`, `bd init`, donor copies, and manual recovery reasoning before returning to the original feature work.

This was not a git problem and not a backlog-loss problem. It was a **runtime readiness** problem that the managed worktree flow failed to stop early.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Why did the agent spend too many iterations on Beads while creating a new worktree? | Because the new worktree was handed off even though its local Beads runtime was not healthy. |
| 2 | Why was it handed off as ready? | Because the workflow trusted `beads_state=local` / local ownership signals as proof of readiness. |
| 3 | Why was that trust incorrect? | Because local ownership and local runtime health are different facts: a worktree can own its `.beads/` state locally while still missing the named `beads` DB. |
| 4 | Why did the workflow not catch the missing DB before handoff? | Because `worktree-phase-a.sh` did not run a fail-closed runtime preparation loop, and `worktree-ready.sh` did not maintain a separate `beads_runtime_state` verdict. |
| 5 | Why did operators still drift into stale recovery guidance? | Because some worktree command/skill guidance still mentioned retired `bd sync` semantics or generic localize guidance instead of routing broken local runtime to `bd doctor --json` and `bd bootstrap`. |

## Root Cause

Managed worktree orchestration used a split-brain Beads contract. Ownership discovery (`beads_state=local`) and runtime health were collapsed into one “Beads is local/ready” notion. That let freshly created worktrees pass readiness checks even when the local Dolt runtime had not materialized the named `beads` DB yet.

## Fixes Applied

1. Hardened `scripts/worktree-phase-a.sh` so worktree creation now performs bounded runtime preparation and one sanctioned automatic `bd bootstrap` attempt for fresh worktrees before handoff.
2. Hardened `scripts/worktree-ready.sh` so it now reports a separate `Beads Runtime:` verdict and blocks `doctor` / `finish` when the runtime is `runtime_bootstrap_required` or `partial_foundation`.
3. Hardened `scripts/beads-resolve-db.sh` so plain `bd` fails closed for bare runtime shells without the named `beads` DB, while still allowing explicit runtime repair commands.
4. Clarified `scripts/beads-worktree-localize.sh` so ownership repair and runtime repair are no longer described as the same recovery step.
5. Retired stale `bd sync` guidance in `.claude/commands/worktree.md` and `.claude/skills/beads/SKILL.md`.
6. Added regression coverage in:
   - `tests/unit/test_bd_dispatch.sh`
   - `tests/unit/test_worktree_phase_a.sh`
   - `tests/unit/test_worktree_ready.sh`
   - `tests/static/test_beads_worktree_ownership.sh`

## Prevention

1. Treat Beads ownership and Beads runtime as separate health dimensions in all managed worktree flows.
2. Never hand off a newly created worktree until runtime health is either `healthy` or explicitly blocked with a single sanctioned next step.
3. Route `runtime_bootstrap_required` only to `/usr/local/bin/bd doctor --json` and `bd bootstrap`.
4. Keep `./scripts/beads-worktree-localize.sh --path <worktree>` for missing, redirected, or legacy ownership state only.
5. Keep retired `.beads/issues.jsonl` retired; do not use JSONL restoration as a recovery crutch for broken local runtime.

## Related Updates

- [x] Runtime-ready gating added to [scripts/worktree-phase-a.sh](/Users/rl/coding/moltinger/029-beads-dolt-native-migration/scripts/worktree-phase-a.sh)
- [x] Separate runtime verdict added to [scripts/worktree-ready.sh](/Users/rl/coding/moltinger/029-beads-dolt-native-migration/scripts/worktree-ready.sh)
- [x] Resolver hardened in [scripts/beads-resolve-db.sh](/Users/rl/coding/moltinger/029-beads-dolt-native-migration/scripts/beads-resolve-db.sh)
- [x] Ownership-vs-runtime guidance clarified in [docs/CODEX-OPERATING-MODEL.md](/Users/rl/coding/moltinger/029-beads-dolt-native-migration/docs/CODEX-OPERATING-MODEL.md)
- [x] Rule retained in [docs/rules/beads-dolt-runtime-shell-is-not-a-healthy-runtime.md](/Users/rl/coding/moltinger/029-beads-dolt-native-migration/docs/rules/beads-dolt-runtime-shell-is-not-a-healthy-runtime.md)

## Уроки

- **`Beads: local` не равно `runtime healthy`** — ownership и runtime readiness надо проверять отдельно.
- **Create flow обязан быть fail-closed** — новый worktree нельзя отдавать агенту, пока runtime не стал здоровым или не выдан один точный blocker.
- **Generic localize guidance вредна для broken Dolt runtime** — ownership repair и runtime repair должны идти разными путями.
- **Retired `bd sync` нельзя оставлять в живых skills/commands** — иначе агенты продолжают идти по устаревшему operator path.
