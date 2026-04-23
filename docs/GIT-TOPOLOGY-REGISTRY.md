# Git Topology Registry

**Status**: Generated artifact from shared remote-governance topology and reviewed intent sidecar
**Scope**: Shared remote governance snapshot
**Purpose**: Single reference for unmerged remote branches and reviewed topology intent that still require merge or cleanup decisions.
**Publish**: Dispatch `scripts/git-topology-registry.sh publish`; the workflow updates dedicated branch `chore/topology-registry-publish` and opens or updates a PR to `main`
**Local Note**: Local worktrees and local-only branches remain live-only via `scripts/git-topology-registry.sh status` and `check`
**Privacy Note**: This committed artifact is sanitized. Absolute local paths stay in live git state, not in tracked docs.

## Remote Branches Not Merged Into `origin/main`

| Remote Branch | Current Intent |
|---|---|
| `origin/chore/moltis-update-20260420.02` | Needs decision |
| `origin/chore/moltis-update-20260421.05` | Needs decision |
| `origin/chore/moltis-update-20260422.01` | Needs decision |
| `origin/chore/topology-registry-publish` | Needs decision |
| `origin/codex/ai-ide-workflow-handoff` | Needs decision |
| `origin/codex/fix-deploy-heredoc` | Needs decision |
| `origin/fix/moltis-20260423-telegram-runtime` | Needs decision |
| `origin/fix/telegram-skill-detail-terminalize` | Needs decision |

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
| `remote` | `origin/001-frontend` | `cleanup-candidate` | Review later; currently dangling. | - |
| `remote` | `origin/001-moltis-docker-deploy` | `historical` | Historical; review before cleanup. | - |
| `remote` | `origin/003-testing-infrastructure` | `historical` | Historical planning branch. | - |
| `remote` | `origin/005-worktree-ready-flow` | `active` | Active parallel feature branch. | - |
| `remote` | `origin/006-git-topology-registry` | `active` | Active topology-registry feature branch. | - |
| `remote` | `origin/codex/004-telegram-e2e-harness` | `extract-only` | Source for future Telegram consolidation. | - |
| `remote` | `origin/codex/fix-bot` | `extract-only` | Source for future Telegram consolidation. | 8 |
| `remote` | `origin/codex/full-review` | `protected` | Active parallel session; exclude from automated cleanup. | 6 |
| `remote` | `origin/codex/gitops-metrics-fix` | `active` | Active replacement PR #18. | 18 |
| `remote` | `origin/codex/webhook-moltinger` | `extract-only` | Source for future Telegram consolidation. | - |
| `remote` | `origin/feat/gpt-5-moltis` | `active` | Active feature branch. | - |

## Registry Warnings

- Reviewed intent contains 30 orphan record(s); keep them until topology catches up or the sidecar is reviewed.

## Operating Rules

1. `main` remains the only operational source of truth.
2. This tracked document covers shared remote-governance state only; local worktree and local-only branch topology stay live-only.
3. Before deleting or merging branches, verify this registry and then verify live `git` state again.
4. If remote topology or reviewed intent changes, dispatch the publish flow to refresh this snapshot.
5. Live `git` state wins over this document if they diverge; refresh the registry instead of forcing git to match the doc.

## Source Commands

```bash
git for-each-ref --format='%(refname:short)' refs/remotes/origin
cat docs/GIT-TOPOLOGY-INTENT.yaml
```
