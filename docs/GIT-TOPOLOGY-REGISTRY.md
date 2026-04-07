# Git Topology Registry

**Status**: Generated artifact from live git topology and reviewed intent sidecar
**Scope**: Canonical maintainer workstation snapshot
**Purpose**: Single reference for current git worktrees, active branches, and branches that still require a decision.
**Publish**: From the dedicated non-main topology publish branch `chore/topology-registry-publish` run `scripts/git-topology-registry.sh refresh --write-doc`
**Privacy Note**: This committed artifact is sanitized. Absolute local paths stay in live git state, not in tracked docs.

## Current Worktrees

| Worktree ID | Branch | Location Class | Status |
|---|---|---|---|
| `codex-full-review` | `codex/full-review` | `codex-managed` | Parallel Codex session; protect from cleanup. |
| `moltinger-chore-topology-registry-publish` | `chore/topology-registry-publish` | `sibling-worktree` | Dedicated single-writer publish worktree for topology snapshots. |
| `moltinger-fix-telegram-uat-output-gitops-safe` | `fix/telegram-uat-output-gitops-safe` | `sibling-worktree` | Active sibling worktree for the Telegram UAT output GitOps-safe lane. |
| `moltinger-storage-maintenance-json-report` | `fix/storage-maintenance-json-report` | `sibling-worktree` | Active sibling worktree for the storage maintenance JSON report lane. |
| `moltinger-telegram-safe-guard-consolidated` | `fix/telegram-safe-guard-consolidated` | `sibling-worktree` | Active sibling worktree for the Telegram safe-guard consolidated lane. |
| `primary-root` | `main` | `primary` | Canonical root worktree; neutral base for triage, cleanup, and merges. |

## Active Local Branches

| Branch | Tracking | Status |
|---|---|---|
| `main` | `origin/main` | Canonical source of truth; checked out in the primary root worktree. |
| `chore/topology-registry-publish` | `origin/chore/topology-registry-publish` | Dedicated single-writer publish lane for topology snapshots; keep out of ordinary cleanup. |
| `codex/full-review` | `origin/codex/full-review` | Protected parallel Codex review lane; keep out of automated cleanup. |
| `fix/storage-maintenance-json-report` | `origin/fix/storage-maintenance-json-report` | Active survivor lane for storage maintenance JSON report follow-up; keep until PR #135 lands or closes. |
| `fix/telegram-safe-guard-consolidated` | `origin/fix/telegram-safe-guard-consolidated` | Active consolidated survivor lane for Telegram safe-guard hardening; keep until landed or closed. |
| `fix/telegram-uat-output-gitops-safe` | `origin/fix/telegram-uat-output-gitops-safe` | Active survivor lane for Telegram UAT output GitOps-safe delivery; keep until PR #149 lands or closes. |

## Remote Branches Not Merged Into `origin/main`

| Remote Branch | Current Intent |
|---|---|
| `origin/chore/topology-registry-publish` | Dedicated publish remote for topology snapshot publication. |
| `origin/fix/storage-maintenance-json-report` | Remote survivor lane for open PR #135. |
| `origin/fix/telegram-safe-guard-consolidated` | Remote survivor lane for Telegram safe-guard hardening. |
| `origin/fix/telegram-uat-output-gitops-safe` | Remote survivor lane for open PR #149. |

## Operating Rules

1. `main` remains the only operational source of truth.
2. If a branch has a dedicated worktree, treat that worktree as the authoritative place for edits.
3. Before deleting or merging branches, verify this registry and then verify live `git` state again.
4. If branch/worktree state changes, this artifact must be refreshed in the same session or at the next session boundary.
5. Live `git` state wins over this document if they diverge; refresh the registry instead of forcing git to match the doc.

## Source Commands

```bash
git worktree list --porcelain
git for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads
git for-each-ref --format='%(refname:short)' refs/remotes/origin
```
