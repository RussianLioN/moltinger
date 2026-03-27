---
title: "Git hooks clobbered their own bootstrap-source contract after eval of helper env output"
date: 2026-03-27
severity: P1
category: process
tags: [beads, git-hooks, worktree, bootstrap, rca]
root_cause: "The tracked git hooks reused the variable name `bootstrap_source` both for the operator-requested source ref and for helper-emitted env output. After `eval` of `scripts/beads-worktree-localize.sh --format env`, the hook overwrote its own requested source ref with `bootstrap_source=''` from helper output and then called the mutating localize step with an empty required argument."
---

# RCA: Git hooks clobbered their own bootstrap-source contract after eval of helper env output

Date: 2026-03-27  
Context: fresh managed worktree creation emitted `[beads-worktree-localize] --bootstrap-source requires a value` even though the hook source looked like it always passed `origin/main`

## Error

Fresh worktree creation through `scripts/worktree-phase-a.sh create-from-base` produced a false bootstrap error during `post-checkout`:

```text
[beads-worktree-localize] --bootstrap-source requires a value
```

The worktree could still end up healthy, which made the failure noisy, misleading, and hard to trust.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Why did the hook claim `--bootstrap-source` was missing? | Because the mutating localize call was made with an empty `--bootstrap-source` value. |
| 2 | Why was that value empty if the hook initialized it to `origin/main`? | Because the hook later ran `eval` on helper env output that included `bootstrap_source=''`. |
| 3 | Why did `eval` overwrite the hook's own variable? | Because both the hook and the helper used the same variable name, `bootstrap_source`, in the same shell scope. |
| 4 | Why did that turn into a user-visible worktree error? | Because the hook reused the clobbered variable for the second localize call instead of preserving the operator-requested source ref separately. |
| 5 | Why did this survive earlier hardening? | Because tests covered the helper contract and runtime repair paths, but did not cover hook behavior when helper env output reused operator-facing variable names. |

## Root Cause

The git hook implementation mixed two different data channels into one shell variable name:

- operator intent: the requested bootstrap source ref (`origin/main`)
- helper env contract: `bootstrap_source` emitted by `beads-worktree-localize.sh`

Once `eval` imported the helper output, the hook lost its requested source ref and passed an empty required value into the next localize call.

## Fixes Applied

1. Renamed the hook-owned variable to `requested_bootstrap_source` in:
   - `.githooks/post-checkout`
   - `.githooks/post-merge`
2. Explicitly `unset` helper-owned env variable names before `eval` to keep the hook state predictable.
3. Added unit regression coverage in `tests/unit/test_beads_git_hooks.sh`.
4. Registered the new regression in `tests/run.sh` under the `component` lane.

## Prevention

1. Do not reuse helper env keys as operator-owned shell variables in hooks or shell orchestration.
2. Treat `eval` of helper `key=value` output as a contract boundary and namespace caller-owned variables separately.
3. Any hook that reuses helper env output must have at least one regression that proves a required caller argument survives the `eval` step.

## Related Lessons

- `docs/rca/2026-03-26-worktree-create-misread-local-ownership-as-runtime-ready.md`
- `docs/rca/2026-03-26-beads-worktree-localize-used-stale-bootstrap-contract.md`
