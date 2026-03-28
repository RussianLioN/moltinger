---
title: "Managed worktree creation mixed up the create executor and hook bootstrap-source contract"
date: 2026-03-28
severity: P1
category: process
tags: [beads, dolt, git-worktree, hooks, skills, bootstrap, rca]
root_cause: "The worktree workflow exposed `worktree-ready create` as if it could allocate a new worktree, while stale tracked git hooks eval'd helper env output into the shell and clobbered the requested bootstrap source for follow-up localization."
---

# RCA: Managed worktree creation mixed up the create executor and hook bootstrap-source contract

Date: 2026-03-28
Context: repeated `031 -> 034` creation attempts for `034-moltis-skill-discovery-and-telegram-leak-regressions`

## Lessons Pre-check

Before writing this RCA, the lessons index was queried for related incidents:

```bash
./scripts/query-lessons.sh --all | rg -n "bootstrap-source|worktree-ready|beads-worktree-localize|database \"beads\" not found|runtime_bootstrap_required|worktree create"
```

Relevant prior lessons:

1. [2026-03-24: Half-initialized Beads Dolt runtime was misclassified as healthy](./2026-03-24-beads-half-initialized-dolt-runtime-misclassified-as-healthy.md)
2. [2026-03-26: Managed worktree creation misread local Beads ownership as runtime readiness](./2026-03-26-worktree-create-misread-local-ownership-as-runtime-ready.md)
3. [2026-03-26: Beads inventory doctor probe can hang landing](./2026-03-26-beads-inventory-doctor-probe-can-hang-landing.md)

Those lessons covered runtime readiness and bounded probing. They did **not** yet close two remaining gaps:

1. `worktree-ready create` still looked like a mutating create entrypoint in live operator usage.
2. Tracked git hooks still contained an env-eval pattern that could erase the requested `--bootstrap-source` value.

## Error

The agent tried to create a new worktree by calling `scripts/worktree-ready.sh create ...` directly, got a vague blocked response, then fell back into manual `git worktree add` recovery. During that manual fallback, tracked hooks invoked `beads-worktree-localize.sh` with an empty `--bootstrap-source`, producing:

```text
[beads-worktree-localize] --bootstrap-source requires a value
```

The session then burned multiple iterations on Beads/bootstrap recovery instead of progressing the actual incident work.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Why did the session spend too many iterations before starting the real feature work? | Because new worktree creation hit a misleading blocked helper path and then a hook-localization error. |
| 2 | Why did the helper path mislead the operator? | Because `worktree-ready create` was treated as if it could create the branch/worktree, even though it is only a post-Phase-A readiness/handoff helper. |
| 3 | Why did the fallback hook path break? | Because the tracked hooks `eval`'d helper env output that exported `bootstrap_source=''`, overwriting the shell variable that still needed the originally requested source ref. |
| 4 | Why was that overwrite possible? | Because the hook used the same variable name for the requested source and for helper-exported env fields, with no `unset` barrier before `eval`. |
| 5 | Why did this survive until a live incident? | Because the contract split was not pinned in high-traffic worktree docs/skills, and there was no regression test exercising hook env-eval clobbering or the exact create-path guidance. |

## Root Cause

Two process defects overlapped:

1. The worktree workflow did not make the Phase A boundary explicit enough, so operators could still read `worktree-ready create` as the creator rather than the post-create handoff helper.
2. The tracked git hooks reused `bootstrap_source` across shell state and helper env output, so a safe `eval` path could accidentally blank the requested bootstrap source before auto-localization.

## Fixes Applied

1. Hardened tracked hooks:
   - `.githooks/post-checkout`
   - `.githooks/post-merge`
   - switched to `requested_bootstrap_source`
   - added `unset state action bootstrap_source` before `eval`
2. Hardened `scripts/worktree-ready.sh` create-mode guidance:
   - create-mode now emits the exact `scripts/worktree-phase-a.sh create-from-base ...` command
   - create-mode explicitly warns that it is a post-Phase-A handoff helper, not the mutating executor
3. Clarified the source worktree skill/command surface in `.claude/commands/worktree.md`
4. Added regression coverage:
   - `tests/unit/test_beads_git_hooks.sh`
   - `tests/unit/test_worktree_ready.sh`
   - `tests/static/test_beads_worktree_ownership.sh`

## Prevention

1. Keep mutating worktree creation and post-create handoff as separate named contracts.
2. Never `eval` helper env output into shell variables that also carry operator-supplied control values unless those exported names are unset first.
3. Treat hook-assisted Beads localization as automation sugar only; the requested bootstrap source must remain stable across the whole hook path.
4. Keep the command-worktree skill and tracked hook implementation under shared regression tests, not only live operator memory.

## Related Updates

- [x] Hook bootstrap-source preservation fixed in [post-checkout](/Users/rl/coding/moltinger/moltinger-main/.githooks/post-checkout)
- [x] Hook bootstrap-source preservation fixed in [post-merge](/Users/rl/coding/moltinger/moltinger-main/.githooks/post-merge)
- [x] Exact Phase A executor guidance added to [worktree-ready.sh](/Users/rl/coding/moltinger/moltinger-main/scripts/worktree-ready.sh)
- [x] Worktree command contract clarified in [worktree.md](/Users/rl/coding/moltinger/moltinger-main/.claude/commands/worktree.md)
- [x] Hook regression retained in [test_beads_git_hooks.sh](/Users/rl/coding/moltinger/moltinger-main/tests/unit/test_beads_git_hooks.sh)
- [x] Create-path regression added in [test_worktree_ready.sh](/Users/rl/coding/moltinger/moltinger-main/tests/unit/test_worktree_ready.sh)

## Уроки

- **`worktree-ready create` не создаёт worktree**: это handoff/readiness helper, а не mutating executor.
- **`eval` helper env требует изоляции переменных**: exported поля не должны затирать operator-supplied control values.
- **Hook automation должна быть deterministic**: `--bootstrap-source` нельзя терять по пути из-за локального shell state.
- **Если create-path двусмысленен, агент уходит в лишнюю recovery-цепочку**: такие двусмысленности надо закрывать текстом контракта и regression-тестами.
