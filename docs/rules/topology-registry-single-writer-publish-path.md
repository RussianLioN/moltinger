# Topology Registry Single-Writer Publish Path

**Status:** Active  
**Effective date:** 2026-03-14  
**Scope:** `command-worktree`, `command-session-summary`, `command-git-topology`, and any manual workflow touching `docs/GIT-TOPOLOGY-REGISTRY.md`

## Problem This Rule Prevents

`docs/GIT-TOPOLOGY-REGISTRY.md` is a generated snapshot of global git topology.
If ordinary feature branches, UAT branches, or the canonical `main` worktree all publish it opportunistically, parallel sessions create:

- docs-only churn unrelated to the feature under work
- repeated rebase/push conflicts on one shared file
- misleading pressure to edit global topology state from the wrong branch

## Source Of Truth

- `live git` is the topology source of truth
- `docs/GIT-TOPOLOGY-INTENT.yaml` is the reviewed intent sidecar
- `docs/GIT-TOPOLOGY-REGISTRY.md` is a sanitized branch-local audit snapshot

## Mandatory Policy

1. Default to read-only topology inspection:
   - `scripts/git-topology-registry.sh status`
   - `scripts/git-topology-registry.sh check`
   - `scripts/git-topology-registry.sh doctor --prune`
2. Do **not** auto-run `refresh --write-doc` from:
   - canonical `main`
   - the invoking ordinary feature branch
   - disposable UAT/reset/rebase branches
   - ordinary `command-worktree start|attach|cleanup` flows
3. Publish the tracked snapshot only through an explicit topology publish step from a **dedicated non-main topology-publish worktree/branch**.
4. Ordinary worktree flows may report `stale`, but they must treat live `git` as authoritative for collision detection and continue without publishing the markdown snapshot.
5. If a UAT or child worktree holds newer registry evidence, preserve/promote that evidence into the owning branch before reset/update, per `docs/rules/uat-registry-snapshot-preservation.md`.

## Expected Publish Path

Use a dedicated topology publish lane, for example:

```bash
git worktree add ../moltinger-topology-publish -b chore/topology-registry-publish-<slug> main
cd ../moltinger-topology-publish
scripts/git-topology-registry.sh refresh --write-doc
git add docs/GIT-TOPOLOGY-REGISTRY.md docs/GIT-TOPOLOGY-INTENT.yaml
git commit -m "docs(topology): publish registry snapshot"
git pull --rebase
git push
```

The exact branch name may vary, but it must be:

- dedicated to topology publication
- outside ordinary feature work
- not the canonical `main` worktree

If this publish lane also needs Beads synchronization, use the localized repo wrapper from a managed worktree session. Do not assume a bare `bd sync` belongs in an ad-hoc manual topology-publish lane.

## Operational Meaning

- `stale` during ordinary work is an inspection signal, not a reason to inject a docs commit into the current feature branch
- publishing the snapshot is an explicit maintenance checkpoint, not a side effect of every worktree mutation
