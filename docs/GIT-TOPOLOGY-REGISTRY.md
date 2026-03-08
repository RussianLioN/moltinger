# Git Topology Registry

**Status**: Seed artifact, to be auto-maintained  
**Captured**: 2026-03-08  
**Purpose**: Single reference for current git worktrees, active branches, and branches that still require a decision.

## Current Worktrees

| Worktree Path | Branch | HEAD | Notes |
|---|---|---|---|
| `/Users/rl/coding/moltinger` | `main` | `3662467` | Primary operational worktree |
| `/Users/rl/.codex/worktrees/da4f/moltinger` | `codex/full-review` | `38114a6` | Parallel Codex session; do not touch without explicit coordination |
| `/Users/rl/coding/moltinger-codex-gitops-metrics-fix` | `codex/gitops-metrics-fix` | `b0e242f` | Replacement branch for closed PR `#3`; current open PR `#18` |
| `/Users/rl/coding/moltinger-gpt-5-moltis` | `feat/gpt-5-moltis` | `59f432a` | Separate research/documentation worktree |
| `/tmp/moltinger-codex-gpt54-agents-split` | `codex/gpt54-agents-split` | `3662467` | Dedicated rollout worktree for gpt-5.4 policy and Codex operating model |

## Active Local Branches

| Branch | Tracking | Status |
|---|---|---|
| `main` | `origin/main` | Canonical source of truth |
| `codex/full-review` | `origin/codex/full-review` | Open parallel branch; separate worktree exists |
| `codex/gitops-metrics-fix` | `origin/codex/gitops-metrics-fix` | Fresh replacement branch with open PR `#18` |
| `codex/gpt54-agents-split` | `origin/codex/gpt54-agents-split` | Active rollout branch for Codex operating model |
| `feat/gpt-5-moltis` | `origin/feat/gpt-5-moltis` | Active documentation/research branch |
| `codex/004-telegram-e2e-harness` | `origin/codex/004-telegram-e2e-harness` | Unmerged source branch; treat as extraction source, not merge target |
| `codex/fix-bot` | `origin/codex/fix-bot` | PR `#8` already merged, but branch still contains extra commits; do not merge raw |
| `codex/webhook-moltinger` | `origin/codex/webhook-moltinger` | Valuable but broad operational branch; extract selectively |
| `001-docker-deploy-improvements` | `origin/001-docker-deploy-improvements` | Historical branch |
| `001-fallback-llm-ollama` | `origin/001-fallback-llm-ollama` | Historical branch |
| `001-moltis-docker-deploy` | `origin/001-moltis-docker-deploy` | Historical branch with local drift |
| `003-testing-infrastructure` | `origin/003-testing-infrastructure` | Historical planning branch |
| `test/rca-guard-uat-20260307-0004` | none | Local-only test branch |
| `test/rca-guard-uat-20260307-0015` | gone | Local-only stale test branch |

## Remote Branches Not Merged Into `origin/main`

| Remote Branch | Current Intent |
|---|---|
| `origin/001-frontend` | Review later; currently dangling |
| `origin/001-moltis-docker-deploy` | Historical; review before cleanup |
| `origin/003-testing-infrastructure` | Historical planning branch |
| `origin/codex/004-telegram-e2e-harness` | Source for future Telegram consolidation |
| `origin/codex/fix-bot` | Source for future Telegram consolidation |
| `origin/codex/full-review` | Active parallel session; exclude from automated cleanup |
| `origin/codex/gpt54-agents-split` | Active rollout branch for Codex operating model |
| `origin/codex/gitops-metrics-fix` | Active replacement PR `#18` |
| `origin/codex/webhook-moltinger` | Source for future Telegram consolidation |
| `origin/feat/gpt-5-moltis` | Active feature branch |

## Operating Rules

1. `main` remains the only operational source of truth.
2. If a branch has a dedicated worktree, treat that worktree as the authoritative place for edits.
3. Before deleting or merging branches, verify this registry and then verify live `git` state again.
4. If branch/worktree state changes, this artifact must be refreshed in the same session or at the next session boundary.

## Source Commands

```bash
git worktree list --porcelain
git branch -vv
git branch -r --no-merged origin/main
```
