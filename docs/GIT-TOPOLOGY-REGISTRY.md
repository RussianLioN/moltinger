# Git Topology Registry

**Status**: Generated artifact from live git topology and reviewed intent sidecar
**Scope**: Canonical maintainer workstation snapshot
**Purpose**: Single reference for current git worktrees, active branches, and branches that still require a decision.
**Refresh**: `scripts/git-topology-registry.sh refresh --write-doc`
**Privacy Note**: This committed artifact is sanitized. Absolute local paths stay in live git state, not in tracked docs.

## Current Worktrees

| Worktree ID | Branch | Location Class | Status |
|---|---|---|---|
| `primary-feature-011` | `011-worktree-skill-extraction` | `dedicated-feature-worktree` | Needs decision |
| `primary-root` | `main` | `primary` | Canonical root worktree; neutral base for triage, cleanup, and merges. |

## Active Local Branches

| Branch | Tracking | Status |
|---|---|---|
| `main` | `origin/main` | Canonical source of truth; checked out in the primary root worktree. |
| `011-worktree-skill-extraction` | `none` | Needs decision |

## Remote Branches Not Merged Into `origin/main`

| Remote Branch | Current Intent |
|---|---|
| `origin/001-frontend` | Review later; currently dangling. |
| `origin/001-moltis-docker-deploy` | Historical; review before cleanup. |
| `origin/003-testing-infrastructure` | Historical planning branch. |
| `origin/007-codex-update-monitor` | Needs decision |
| `origin/008-codex-update-advisor` | Needs decision |
| `origin/009-codex-update-delivery-ux` | Needs decision |
| `origin/010-beads-recovery-batch` | Needs decision |
| `origin/012-codex-upstream-watcher` | Needs decision |
| `origin/beads-sync` | Needs decision |
| `origin/codex/004-telegram-e2e-harness` | Source for future Telegram consolidation. |
| `origin/codex/fix-bot` | Source for future Telegram consolidation. |
| `origin/codex/webhook-moltinger` | Source for future Telegram consolidation. |
| `origin/feat/molt-2-codex-update-monitor-new` | Needs decision |
| `origin/feat/moltinger-ejy-beads-redirect-fix` | Needs decision |
| `origin/feat/moltinger-jb6-gpt54-primary` | Needs decision |

## Reviewed Intent Awaiting Reconciliation

| Subject Type | Subject Key | Intent | Note | PR |
|---|---|---|---|---|
| `branch` | `001-clawdiy-agent-platform` | `active` | Active permanent-agent platform rollout branch; dedicated worktree exists. | - |
| `branch` | `001-clawdiy-agent-platform` | `active` | Active permanent-agent platform rollout branch; dedicated worktree exists. | - |
| `branch` | `001-docker-deploy-improvements` | `historical` | Historical branch. | - |
| `branch` | `001-fallback-llm-ollama` | `historical` | Historical branch. | - |
| `branch` | `001-moltis-docker-deploy` | `historical` | Historical branch with local drift. | - |
| `branch` | `003-testing-infrastructure` | `historical` | Historical planning branch. | - |
| `branch` | `005-worktree-ready-flow` | `active` | Valid parallel local feature branch; dedicated worktree exists. | - |
| `branch` | `006-git-topology-registry` | `active` | Active Speckit feature branch; dedicated authoritative worktree exists. | - |
| `branch` | `codex/004-telegram-e2e-harness` | `extract-only` | Unmerged source branch; treat as extraction source, not merge target. | - |
| `branch` | `codex/fix-bot` | `extract-only` | PR #8 already merged, but branch still contains extra commits; do not merge raw. | 8 |
| `branch` | `codex/full-review` | `protected` | Open parallel branch; separate worktree exists. | 6 |
| `branch` | `codex/gitops-metrics-fix` | `active` | Fresh replacement branch with open PR #18. | 18 |
| `branch` | `codex/webhook-moltinger` | `extract-only` | Valuable but broad operational branch; extract selectively. | - |
| `branch` | `feat/gpt-5-moltis` | `active` | Active documentation and research branch; dedicated worktree exists. | - |
| `branch` | `feat/moltinger-jb6-gpt54-primary` | `active` | Active parallel task branch for GPT-5.4 primary provider-chain evaluation. | - |
| `branch` | `test/rca-guard-uat-20260307-0004` | `needs-decision` | Local-only test branch. | - |
| `branch` | `test/rca-guard-uat-20260307-0015` | `cleanup-candidate` | Local-only stale test branch with gone upstream. | - |
| `remote` | `origin/001-clawdiy-agent-platform` | `active` | Active rollout branch for Clawdiy permanent-agent platform. | - |
| `remote` | `origin/001-clawdiy-agent-platform` | `active` | Active rollout branch for Clawdiy permanent-agent platform. | - |
| `remote` | `origin/005-worktree-ready-flow` | `active` | Active parallel feature branch. | - |
| `remote` | `origin/006-git-topology-registry` | `active` | Active topology-registry feature branch. | - |
| `remote` | `origin/codex/full-review` | `protected` | Active parallel session; exclude from automated cleanup. | 6 |
| `remote` | `origin/codex/gitops-metrics-fix` | `active` | Active replacement PR #18. | 18 |
| `remote` | `origin/feat/gpt-5-moltis` | `active` | Active feature branch. | - |
| `worktree` | `codex-full-review` | `protected` | Parallel Codex session; protect from cleanup. | 6 |
| `worktree` | `codex-gitops-metrics-fix` | `active` | Active replacement branch for closed PR #3; open PR #18. | 18 |
| `worktree` | `gpt-5-moltis` | `active` | Active research and documentation worktree. | - |
| `worktree` | `moltinger-jb6-gpt54-primary` | `active` | Active sibling worktree for the GPT-5.4 primary provider-chain task. | - |
| `worktree` | `primary-feature-001` | `active` | Active dedicated feature worktree for the Clawdiy permanent-agent platform. | - |
| `worktree` | `primary-feature-001` | `active` | Active dedicated feature worktree for the Clawdiy permanent-agent platform. | - |
| `worktree` | `primary-feature-005` | `active` | Active parallel Speckit feature worktree. | - |
| `worktree` | `primary-feature-006` | `active` | Active authoritative worktree for topology-registry automation. | - |

## Registry Warnings

- Reviewed intent contains 32 orphan record(s); keep them until topology catches up or the sidecar is reviewed.

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
