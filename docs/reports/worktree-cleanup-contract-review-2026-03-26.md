# Worktree Cleanup Contract Review

Date: 2026-03-26
Branch: `feat/worktree-cleanup-contract-hardening`

## Trigger Facts

- `command-worktree` documented `cleanup`, but `scripts/worktree-ready.sh` previously had no `cleanup`/`remove` mode.
- Canonical root blocked plain `bd worktree remove ...`, even though the documented cleanup path depended on it.
- A real merged branch (`030-rebase-conflict-tail-audit`) failed `git merge-base --is-ancestor ... origin/main`, so git-only merge proof was too weak for squash/rebase merged PRs.
- `bd worktree remove` reported success before the worktree entry fully disappeared, so a single tool exit code was not strong enough as cleanup proof.
- The new lane creation also exposed that cleanup/docs/testing drift was large enough to hide side defects during ordinary worktree operations.

## External Practice Summary

Primary references reviewed:

- Git `worktree` documentation for `list --porcelain`, `prunable`, `locked`, `remove`, and `prune`
- Git `merge-base --is-ancestor` documentation for strict ancestry semantics
- GitHub CLI/API behavior for merged PR metadata and repository `deleteBranchOnMerge`
- Git mailing-list discussions around cross-worktree safety and repair expectations

Practical takeaway:

- use live `git worktree list --porcelain` as the authoritative topology surface
- treat ancestry proof as necessary but not sufficient for squash/rebase merged PR flows
- keep destructive cleanup fail-closed unless the proof chain is explicit and machine-verifiable

## Implemented Improvements

1. Added real helper-backed `cleanup` mode to `scripts/worktree-ready.sh`.
2. Added `remove` as an alias to `cleanup` instead of prose-only support.
3. Added lifecycle env contract `worktree-cleanup/v1` with stable status/action fields.
4. Enforced canonical-root-only cleanup mutations with exact retry commands when invoked from a linked worktree.
5. Narrowed canonical-root `bd` passthrough to only `bd worktree remove <absolute-path>` for linked worktrees.
6. Verified worktree removal against `git worktree list --porcelain` instead of trusting the first `bd` success alone.
7. Made stale or already-missing worktree/branch states idempotent instead of opaque failures.
8. Added stale `prunable` handling so cleanup can reconcile dead worktree entries safely.
9. Added git-first merge proof with optional GitHub merged-PR fallback for the same branch, base branch, and head SHA.
10. Switched local branch deletion to `git branch -D` only when GitHub merged-PR proof confirms a squash/rebase merged branch that `git branch -d` would reject.
11. Updated source command docs, spec contracts, quickstart, validation log, and static checks so the documented cleanup path matches the real helper flow.
12. Added regression coverage for canonical-root admin allowlist, cleanup success, stale entry cleanup, GitHub fallback success, and degraded GitHub-auth failure.

## Residual Risks

- The helper still depends on `gh` + `jq` for the GitHub fallback path; without them, remote deletion remains intentionally blocked.
- The separate `--bootstrap-source requires a value` create-path defect observed during lane creation was not reproduced by `tests/unit/test_worktree_phase_a.sh`; if it reappears in a real worktree-create session, it should be investigated as a hook/runtime integration follow-up rather than a cleanup-contract regression.
