# UAT Registry Snapshot Preservation (RCA-010)

**Status:** Active
**Effective date:** 2026-03-09
**Scope:** All UAT worktrees and maintainers working with `docs/GIT-TOPOLOGY-REGISTRY.md`

## Problem This Rule Prevents

Blindly resetting, rebasing, or fast-forwarding a UAT worktree can discard a newer branch-local topology snapshot before it is promoted into the owning branch.

## Mandatory Protocol

Before updating or resetting any UAT worktree that contains `docs/GIT-TOPOLOGY-REGISTRY.md`:

1. Check whether UAT has a local diff:
   - `git -C <uat-worktree> status --short -- docs/GIT-TOPOLOGY-REGISTRY.md`
2. If yes, compare it to the owning branch snapshot:
   - `diff -u <owning-branch>/docs/GIT-TOPOLOGY-REGISTRY.md <uat-worktree>/docs/GIT-TOPOLOGY-REGISTRY.md`
3. If UAT contains newer or additional topology evidence, promote that snapshot into the owning branch first:
   - either by copying the snapshot and landing it there
   - or by running `scripts/git-topology-registry.sh refresh --write-doc` from the owning branch and landing the result there
4. Only after the owning branch has absorbed the snapshot may the UAT worktree be reset, rebased, or fast-forwarded.

## Ownership Rule

- `live git` remains the source of truth for topology
- `docs/GIT-TOPOLOGY-REGISTRY.md` remains the branch-local audit trail
- UAT may generate newer audit evidence during testing
- that evidence belongs in the owning branch before UAT is treated as disposable

## Expected Behavior

- First: inspect UAT for a local registry diff
- Second: preserve/promote the snapshot into the owning branch if it is newer
- Third: update or reset UAT only after the owning branch is safe
