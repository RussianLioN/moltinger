# Git Topology Registry

**Status**: Manual reference snapshot; live `git` state wins  
**Captured**: 2026-03-09  
**Purpose**: Single reference for current git worktrees, active branches, and branches that still require a decision.
**Portability**: Contains machine-local absolute paths; sanitize before sharing outside the core repo team.

## Current Worktrees

| Worktree Path | Branch | HEAD | Notes |
|---|---|---|---|
| `/Users/rl/coding/moltinger` | `main` | `91689c5` | Primary operational worktree |
| `/private/tmp/moltinger-codex-gpt54-agents-split` | `codex/gpt54-agents-split` | `3e03f7a` | Disposable rollout worktree for Codex operating model and GPT-5.4 policy |
| `/Users/rl/.codex/worktrees/da4f/moltinger` | `codex/full-review` | `1cf8579` | Parallel Codex session; do not touch without explicit coordination |
| `/Users/rl/coding/moltinger-006-git-topology-registry` | `006-git-topology-registry` | `06701a4` | Dedicated git-topology-registry feature worktree |
| `/Users/rl/coding/moltinger-0308-005-worktree-ready-flow` | `005-worktree-ready-flow` | `450e97e` | Dedicated worktree-ready-flow feature worktree |
| `/Users/rl/coding/moltinger-248-telegram-e2e-default-branch` | `feat/moltinger-248-telegram-e2e-default-branch` | `79394c4` | Telegram E2E default-branch lane |
| `/Users/rl/coding/moltinger-dmi-telegram-webhook-rollout` | `feat/moltinger-dmi-telegram-webhook-rollout` | `79394c4` | Telegram webhook rollout lane |
| `/Users/rl/coding/moltinger-gpt-5-moltis` | `feat/gpt-5-moltis` | `786079a` | Separate research/documentation worktree |
| `/Users/rl/coding/moltinger-jb6-gpt54-primary` | `feat/moltinger-jb6-gpt54-primary` | `9bdecfd` | GPT-5.4 primary-model planning lane |
| `/Users/rl/coding/moltinger-molt-2-codex-update-monitor-new` | `007-codex-update-monitor` | `c529023` | Speckit package and implementation-prep lane for Codex CLI update monitor |
| `/Users/rl/coding/moltinger-openclaw-control-plane` | `001-clawdiy-agent-platform` | `3bbc4c8` | OpenClaw control-plane feature lane |
| `/Users/rl/coding/moltinger-pr17-webhook-extraction` | `feat/pr17-webhook-extraction` | `e17a956` | PR17 webhook extraction lane |
| `/Users/rl/coding/moltinger-uat-006-git-topology-registry` | `uat/006-git-topology-registry` | `06701a4` | UAT mirror for git-topology-registry |

## Active Local Branches

| Branch | Tracking | Status |
|---|---|---|
| `main` | `origin/main` | Canonical source of truth |
| `007-codex-update-monitor` | `origin/007-codex-update-monitor` | Active Speckit-aligned branch for Codex update monitor |
| `feat/molt-2-codex-update-monitor-new` | `origin/feat/molt-2-codex-update-monitor-new` | Legacy issue-named branch retained as the pre-alignment source for `007-codex-update-monitor` |
| `006-git-topology-registry` | `origin/006-git-topology-registry` | Active feature branch; dedicated worktree exists |
| `uat/006-git-topology-registry` | `origin/006-git-topology-registry` | UAT mirror branch for the same feature package |
| `005-worktree-ready-flow` | `origin/005-worktree-ready-flow` | Active feature branch; dedicated worktree exists |
| `001-clawdiy-agent-platform` | `origin/001-clawdiy-agent-platform` | Active OpenClaw control-plane branch; dedicated worktree exists |
| `feat/moltinger-248-telegram-e2e-default-branch` | `origin/feat/moltinger-248-telegram-e2e-default-branch` | Active Telegram E2E operational branch |
| `feat/moltinger-dmi-telegram-webhook-rollout` | `origin/feat/moltinger-dmi-telegram-webhook-rollout` | Active Telegram rollout branch |
| `feat/moltinger-jb6-gpt54-primary` | `origin/feat/moltinger-jb6-gpt54-primary` | Active GPT-5.4 planning branch |
| `feat/pr17-webhook-extraction` | `origin/feat/pr17-webhook-extraction` | Active extraction branch; dedicated worktree exists |
| `codex/full-review` | `origin/codex/full-review` | Open parallel branch; separate worktree exists |
| `codex/gpt54-agents-split` | `origin/codex/gpt54-agents-split` | Active rollout branch for Codex operating model |
| `feat/gpt-5-moltis` | `origin/feat/gpt-5-moltis` | Active documentation/research branch |
| `codex/004-telegram-e2e-harness` | `origin/codex/004-telegram-e2e-harness` | Unmerged source branch; treat as extraction source, not merge target |
| `codex/fix-bot` | `origin/codex/fix-bot` | PR `#8` already merged, but branch still contains extra commits; do not merge raw |
| `codex/webhook-main-backfill` | `origin/codex/webhook-main-backfill` | Historical backfill branch; inspect before cleanup |
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
| `origin/007-codex-update-monitor` | Active Speckit-aligned branch for Codex update monitor |
| `origin/001-clawdiy-agent-platform` | Active OpenClaw control-plane feature branch |
| `origin/001-frontend` | Review later; currently dangling |
| `origin/001-moltis-docker-deploy` | Historical; review before cleanup |
| `origin/005-worktree-ready-flow` | Active worktree-ready-flow feature branch |
| `origin/006-git-topology-registry` | Active git-topology-registry feature branch |
| `origin/003-testing-infrastructure` | Historical planning branch |
| `origin/codex/004-telegram-e2e-harness` | Source for future Telegram consolidation |
| `origin/codex/fix-bot` | Source for future Telegram consolidation |
| `origin/codex/webhook-moltinger` | Source for future Telegram consolidation |
| `origin/feat/molt-2-codex-update-monitor-new` | Legacy issue-named branch preserved as a compatibility pointer to the new Speckit lane |
| `origin/feat/gpt-5-moltis` | Active feature branch |
| `origin/feat/moltinger-jb6-gpt54-primary` | Active GPT-5.4 planning branch |

## Operating Rules

1. `main` remains the only operational source of truth.
2. If a branch has a dedicated worktree, treat that worktree as the authoritative place for edits.
3. Before deleting or merging branches, verify this registry and then verify live `git` state again.
4. If branch/worktree state changes, refresh this artifact in the same session or at the next session boundary.
5. HEAD hashes here are snapshot values, not a live guarantee.
6. If this document and live `git` disagree, trust live `git`.

## Source Commands

```bash
git worktree list --porcelain
git branch -vv
git branch -r --no-merged origin/main
```
