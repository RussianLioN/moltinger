# UAT Registry Drift Handling

**Status:** Active
**Effective date:** 2026-04-09
**Scope:** All UAT worktrees and maintainers working with `docs/GIT-TOPOLOGY-REGISTRY.md`

## Problem This Rule Prevents

After the remote-governance scope change, `docs/GIT-TOPOLOGY-REGISTRY.md` is no longer a branch-local or workstation-local audit trail.
If a UAT worktree carries local modifications to that file, treating them as authoritative evidence can promote accidental drift into the tracked publish lane.

## Mandatory Protocol

Before updating, resetting, rebasing, or fast-forwarding any UAT worktree that contains local changes to `docs/GIT-TOPOLOGY-REGISTRY.md`:

1. Inspect whether the diff is real:
   - `git -C <uat-worktree> status --short -- docs/GIT-TOPOLOGY-REGISTRY.md`
2. If the file is dirty, compare it to the current tracked snapshot:
   - `diff -u docs/GIT-TOPOLOGY-REGISTRY.md <uat-worktree>/docs/GIT-TOPOLOGY-REGISTRY.md`
3. Treat any UAT-local diff as **drift to inspect**, not as authoritative branch-local evidence.
4. If live remote topology or reviewed intent truly changed, refresh the official tracked snapshot through:
   - `scripts/git-topology-registry.sh publish`
   - or the emergency low-level publish path on `chore/topology-registry-publish`
5. Only after the tracked publish path is safe may the UAT worktree be reset, rebased, or fast-forwarded.

## Ownership Rule

- `live git` remains the source of truth for topology
- `docs/GIT-TOPOLOGY-REGISTRY.md` is the shared remote-governance snapshot
- local UAT topology remains live-only and must not be promoted blindly into the tracked markdown
- UAT is not an authoritative publication lane for the tracked snapshot

## Expected Behavior

- First: inspect a UAT registry diff as possible drift
- Second: decide whether there is real shared remote-governance change or just local snapshot noise
- Third: use the official publish flow if the tracked snapshot really needs refresh
- Fourth: reset or update UAT only after the shared publish path is safe
