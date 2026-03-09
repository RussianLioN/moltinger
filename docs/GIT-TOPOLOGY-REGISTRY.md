# Git Topology Registry

**Status**: Generated artifact from live git topology and reviewed intent sidecar
**Scope**: Canonical maintainer workstation snapshot
**Purpose**: Single reference for current git worktrees, active branches, and branches that still require a decision.
**Refresh**: `scripts/git-topology-registry.sh refresh --write-doc`
**Privacy Note**: This committed artifact is sanitized. Absolute local paths stay in live git state, not in tracked docs.

## Current Worktrees

| Worktree ID | Branch | Location Class | Status |
|---|---|---|---|
| `codex-full-review` | `codex/full-review` | `codex-managed` | Parallel Codex session; protect from cleanup. |
| `codex-gpt54-agents-split` | `codex/gpt54-agents-split` | `sibling-worktree` | Needs decision |
| `gpt-5-moltis` | `feat/gpt-5-moltis` | `sibling-worktree` | Active research and documentation worktree. |
| `molt-2-codex-update-monitor-new` | `feat/molt-2-codex-update-monitor-new` | `sibling-worktree` | Needs decision |
| `moltinger-248-telegram-e2e-default-branch` | `feat/moltinger-248-telegram-e2e-default-branch` | `sibling-worktree` | Needs decision |
| `moltinger-dmi-telegram-webhook-rollout` | `feat/moltinger-dmi-telegram-webhook-rollout` | `sibling-worktree` | Needs decision |
| `moltinger-jb6-gpt54-primary` | `feat/moltinger-jb6-gpt54-primary` | `sibling-worktree` | Active sibling worktree for the GPT-5.4 primary provider-chain task. |
| `moltinger-uat-006-git-topology-registry` | `uat/006-git-topology-registry` | `sibling-worktree` | Needs decision |
| `pr17-webhook-extraction` | `feat/pr17-webhook-extraction` | `sibling-worktree` | Needs decision |
| `primary-feature-001` | `001-clawdiy-agent-platform` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-005` | `005-worktree-ready-flow` | `dedicated-feature-worktree` | Active parallel Speckit feature worktree. |
| `primary-feature-006` | `006-git-topology-registry` | `dedicated-feature-worktree` | Active authoritative worktree for topology-registry automation. |
| `primary-root` | `main` | `primary` | Canonical root worktree; neutral base for triage, cleanup, and merges. |

## Active Local Branches

| Branch | Tracking | Status |
|---|---|---|
| `main` | `origin/main` | Canonical source of truth; checked out in the primary root worktree. |
| `001-clawdiy-agent-platform` | `origin/001-clawdiy-agent-platform` | Needs decision |
| `005-worktree-ready-flow` | `origin/005-worktree-ready-flow` | Valid parallel local feature branch; dedicated worktree exists. |
| `006-git-topology-registry` | `origin/006-git-topology-registry` | Active Speckit feature branch; dedicated authoritative worktree exists. |
| `codex/full-review` | `origin/codex/full-review` | Open parallel branch; separate worktree exists. |
| `codex/gpt54-agents-split` | `origin/codex/gpt54-agents-split` | Needs decision |
| `feat/gpt-5-moltis` | `origin/feat/gpt-5-moltis` | Active documentation and research branch; dedicated worktree exists. |
| `feat/molt-2-codex-update-monitor-new` | `none` | Needs decision |
| `feat/moltinger-248-telegram-e2e-default-branch` | `none` | Needs decision |
| `feat/moltinger-dmi-telegram-webhook-rollout` | `none` | Needs decision |
| `feat/moltinger-jb6-gpt54-primary` | `origin/feat/moltinger-jb6-gpt54-primary` | Active parallel task branch for GPT-5.4 primary provider-chain evaluation. |
| `feat/pr17-webhook-extraction` | `origin/feat/pr17-webhook-extraction` | Needs decision |
| `uat/006-git-topology-registry` | `origin/006-git-topology-registry` | Needs decision |
| `001-docker-deploy-improvements` | `origin/001-docker-deploy-improvements` | Historical branch. |
| `001-fallback-llm-ollama` | `origin/001-fallback-llm-ollama` | Historical branch. |
| `001-moltis-docker-deploy` | `origin/001-moltis-docker-deploy` | Historical branch with local drift. |
| `003-testing-infrastructure` | `origin/003-testing-infrastructure` | Historical planning branch. |
| `codex/004-telegram-e2e-harness` | `origin/codex/004-telegram-e2e-harness` | Unmerged source branch; treat as extraction source, not merge target. |
| `codex/fix-bot` | `origin/codex/fix-bot` | PR #8 already merged, but branch still contains extra commits; do not merge raw. |
| `codex/webhook-main-backfill` | `origin/codex/webhook-main-backfill` | Needs decision |
| `codex/webhook-moltinger` | `origin/codex/webhook-moltinger` | Valuable but broad operational branch; extract selectively. |
| `feat/openclaw-control-plane` | `none` | Needs decision |
| `test/rca-guard-uat-20260307-0004` | `none` | Local-only test branch. |
| `test/rca-guard-uat-20260307-0015` | `gone` | Local-only stale test branch with gone upstream. |

## Remote Branches Not Merged Into `origin/main`

| Remote Branch | Current Intent |
|---|---|
| `origin/001-clawdiy-agent-platform` | Needs decision |
| `origin/001-frontend` | Review later; currently dangling. |
| `origin/001-moltis-docker-deploy` | Historical; review before cleanup. |
| `origin/003-testing-infrastructure` | Historical planning branch. |
| `origin/005-worktree-ready-flow` | Active parallel feature branch. |
| `origin/006-git-topology-registry` | Active topology-registry feature branch. |
| `origin/codex/004-telegram-e2e-harness` | Source for future Telegram consolidation. |
| `origin/codex/fix-bot` | Source for future Telegram consolidation. |
| `origin/codex/webhook-moltinger` | Source for future Telegram consolidation. |
| `origin/feat/moltinger-jb6-gpt54-primary` | Needs decision |

## Reviewed Intent Awaiting Reconciliation

| Subject Type | Subject Key | Intent | Note | PR |
|---|---|---|---|---|
| `branch` | `codex/gitops-metrics-fix` | `active` | Fresh replacement branch with open PR #18. | 18 |
| `remote` | `origin/codex/full-review` | `protected` | Active parallel session; exclude from automated cleanup. | 6 |
| `remote` | `origin/codex/gitops-metrics-fix` | `active` | Active replacement PR #18. | 18 |
| `remote` | `origin/feat/gpt-5-moltis` | `active` | Active feature branch. | - |
| `worktree` | `codex-gitops-metrics-fix` | `active` | Active replacement branch for closed PR #3; open PR #18. | 18 |

## Registry Warnings

- Reviewed intent contains 5 orphan record(s); keep them until topology catches up or the sidecar is reviewed.

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
