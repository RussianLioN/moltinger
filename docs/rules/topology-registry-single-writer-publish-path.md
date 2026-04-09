# Topology Registry Single-Writer Publish Path

**Status:** Active
**Effective date:** 2026-04-09
**Scope:** `command-worktree`, `command-session-summary`, `command-git-topology`, GitHub workflow automation, and any manual workflow touching `docs/GIT-TOPOLOGY-REGISTRY.md`

## Problem This Rule Prevents

`docs/GIT-TOPOLOGY-REGISTRY.md` is a generated **shared remote-governance snapshot**.
If ordinary feature branches, UAT branches, or canonical `main` publish it opportunistically, parallel sessions create:

- docs-only churn unrelated to the active slice
- repeated rebase/push conflicts on one shared file
- false authority for branch-local or workstation-local topology evidence

## Source Of Truth

- `live git` is the topology source of truth
- `docs/GIT-TOPOLOGY-INTENT.yaml` is the reviewed intent sidecar
- `docs/GIT-TOPOLOGY-REGISTRY.md` is the tracked shared remote-governance snapshot
- local worktrees and local-only branches remain live-only through `scripts/git-topology-registry.sh status` / `check`

## Mandatory Policy

1. Default to non-publishing topology inspection and maintenance:
   - `scripts/git-topology-registry.sh status`
   - `scripts/git-topology-registry.sh check`
   - `scripts/git-topology-registry.sh doctor --prune`
   - `doctor --prune` may rewrite shared draft/cache state, but it must not publish the tracked markdown snapshot.
2. Do **not** auto-run `refresh --write-doc` from:
   - canonical `main`
   - the invoking ordinary feature branch
   - disposable UAT/reset/rebase branches
   - ordinary `command-worktree start|attach|finish|cleanup` flows
3. Publish the tracked snapshot through the official shared publish flow:
   - preferred path: `scripts/git-topology-registry.sh publish`
   - execution surface: `.github/workflows/topology-registry-publish.yml`
   - publication lane: dedicated non-main branch **`chore/topology-registry-publish`**
4. The tracked snapshot must cover only shared remote-governance state:
   - unmerged remote branches
   - reviewed intent awaiting reconciliation for tracked branch/remote subjects
   - registry warnings and operating rules
5. Ordinary worktree flows may report `stale`, but they must treat live `git` as authoritative for collision detection and continue without publishing the markdown snapshot.
6. `refresh --write-doc` remains a low-level manual path only for emergency/manual publication from the exact dedicated branch `chore/topology-registry-publish` in its own publish worktree.

## Preferred Publish Path

Dispatch the workflow:

```bash
scripts/git-topology-registry.sh publish
```

The workflow must:

- checkout or create `chore/topology-registry-publish`
- run `scripts/git-topology-registry.sh refresh --write-doc`
- allow changes only to `docs/GIT-TOPOLOGY-REGISTRY.md`
- push the dedicated publish branch
- create or update a PR from `chore/topology-registry-publish` to `main`

## Low-Level Manual Recovery Path

Use this only when the workflow path is unavailable and a human must repair publication manually:

```bash
git worktree add ../moltinger-topology-publish -b chore/topology-registry-publish main
cd ../moltinger-topology-publish
scripts/git-topology-registry.sh refresh --write-doc
git add docs/GIT-TOPOLOGY-REGISTRY.md
git commit -m "docs(topology): publish remote-governance snapshot"
git push -u origin chore/topology-registry-publish
```

The manual publish lane must be:

- the exact branch `chore/topology-registry-publish`
- isolated from ordinary feature work
- not the canonical `main` worktree

## Operational Meaning

- `stale` during ordinary work is an inspection signal, not a reason to inject a docs commit into the current feature branch
- local workstation topology is still real and still matters for live operations, but it is not the tracked markdown contract anymore
- publishing the snapshot is an explicit shared maintenance checkpoint, not a side effect of every worktree mutation
