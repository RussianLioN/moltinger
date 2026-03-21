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
| `moltinger-248-telegram-e2e-default-branch` | `feat/moltinger-248-telegram-e2e-default-branch` | `sibling-worktree` | Needs decision |
| `moltinger-chore-topology-registry-publish` | `chore/topology-registry-publish` | `sibling-worktree` | Needs decision |
| `moltinger-dmi-telegram-webhook-rollout` | `feat/moltinger-dmi-telegram-webhook-rollout` | `sibling-worktree` | Needs decision |
| `moltinger-ewde-codex-advisory-rollout` | `feat/moltinger-ewde-codex-advisory-rollout` | `sibling-worktree` | Needs decision |
| `moltinger-main-gpt54-integration` | `integration/gpt54-main` | `sibling-worktree` | Needs decision |
| `moltinger-moltis-pin-v0-10-18-prod` | `fix/moltis-update-proposal-telegram-notify` | `sibling-worktree` | Needs decision |
| `moltinger-worktree-topology-registry-publish` | `fix/worktree-topology-registry-single-writer-publish` | `sibling-worktree` | Needs decision |
| `moltinger-z8m-1-moltis-backup-rollback-baseline` | `feat/moltinger-z8m-1-moltis-backup-rollback-baseline` | `sibling-worktree` | Needs decision |
| `moltinger-z8m-2-moltis-skills-subagents-abilities-expansion` | `feat/moltinger-z8m-2-moltis-skills-subagents-abilities-expansion` | `sibling-worktree` | Needs decision |
| `primary-feature-008` | `008-codex-update-advisor` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-009` | `009-codex-update-delivery-ux` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-012` | `012-codex-upstream-watcher` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-016` | `016-worktree-skill-bug-fix` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-021` | `021-moltis-native-codex-update-advisory` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-023` | `023-beads-dolt-pilot-prep` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-023` | `023-full-moltis-codex-update-skill` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-024` | `024-clawdiy-oauth-store-drift-fix` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-024` | `024-web-factory-demo-adapter` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-026` | `026-clawteam-framework-research` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-028` | `028-beads-issues-jsonl-rca` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-029` | `029-beads-dolt-native-migration` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-030` | `030-rebase-conflict-tail-audit` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-031` | `031-moltis-reliability-diagnostics` | `dedicated-feature-worktree` | Needs decision |
| `primary-root` | `main` | `primary` | Canonical root worktree; neutral base for triage, cleanup, and merges. |

## Active Local Branches

| Branch | Tracking | Status |
|---|---|---|
| `main` | `origin/main` | Canonical source of truth; checked out in the primary root worktree. |
| `008-codex-update-advisor` | `origin/008-codex-update-advisor` | Needs decision |
| `009-codex-update-delivery-ux` | `origin/009-codex-update-delivery-ux` | Needs decision |
| `012-codex-upstream-watcher` | `origin/012-codex-upstream-watcher` | Needs decision |
| `016-worktree-skill-bug-fix` | `none` | Needs decision |
| `021-moltis-native-codex-update-advisory` | `none` | Needs decision |
| `023-beads-dolt-pilot-prep` | `origin/023-beads-dolt-pilot-prep` | Needs decision |
| `023-full-moltis-codex-update-skill` | `origin/023-full-moltis-codex-update-skill` | Needs decision |
| `024-clawdiy-oauth-store-drift-fix` | `origin/024-clawdiy-oauth-store-drift-fix` | Needs decision |
| `024-web-factory-demo-adapter` | `origin/024-web-factory-demo-adapter` | Needs decision |
| `026-clawteam-framework-research` | `origin/main` | Needs decision |
| `028-beads-issues-jsonl-rca` | `origin/028-beads-issues-jsonl-rca` | Needs decision |
| `029-beads-dolt-native-migration` | `origin/029-beads-dolt-native-migration` | Needs decision |
| `030-rebase-conflict-tail-audit` | `origin/030-rebase-conflict-tail-audit` | Needs decision |
| `031-moltis-reliability-diagnostics` | `none` | Needs decision |
| `chore/topology-registry-publish` | `origin/chore/topology-registry-publish` | Needs decision |
| `codex/full-review` | `origin/codex/full-review` | Open parallel branch; separate worktree exists. |
| `feat/moltinger-248-telegram-e2e-default-branch` | `none` | Needs decision |
| `feat/moltinger-dmi-telegram-webhook-rollout` | `none` | Needs decision |
| `feat/moltinger-ewde-codex-advisory-rollout` | `origin/feat/moltinger-ewde-codex-advisory-rollout` | Needs decision |
| `feat/moltinger-z8m-1-moltis-backup-rollback-baseline` | `origin/feat/moltinger-z8m-1-moltis-backup-rollback-baseline` | Needs decision |
| `feat/moltinger-z8m-2-moltis-skills-subagents-abilities-expansion` | `none` | Needs decision |
| `fix/moltis-update-proposal-telegram-notify` | `gone` | Tracking ref is gone; needs decision |
| `fix/worktree-topology-registry-single-writer-publish` | `origin/fix/worktree-topology-registry-single-writer-publish` | Needs decision |
| `integration/gpt54-main` | `origin/integration/gpt54-main` | Needs decision |
| `001-clawdiy-agent-platform` | `origin/001-clawdiy-agent-platform` | Active permanent-agent platform rollout branch; dedicated worktree exists. |
| `001-docker-deploy-improvements` | `origin/001-docker-deploy-improvements` | Historical branch. |
| `001-fallback-llm-ollama` | `origin/001-fallback-llm-ollama` | Historical branch. |
| `001-moltis-docker-deploy` | `origin/001-moltis-docker-deploy` | Historical branch with local drift. |
| `003-testing-infrastructure` | `origin/003-testing-infrastructure` | Historical planning branch. |
| `007-codex-update-monitor` | `origin/007-codex-update-monitor` | Needs decision |
| `008-clawdiy-rollout-bootstrap-fix` | `gone` | Tracking ref is gone; needs decision |
| `011-clawdiy-openclaw-runtime-fix` | `origin/011-clawdiy-openclaw-runtime-fix` | Needs decision |
| `012-clawdiy-live-runtime-fix` | `origin/012-clawdiy-live-runtime-fix` | Needs decision |
| `012-codex-upstream-watcher-writable` | `origin/012-codex-upstream-watcher` | Needs decision |
| `013-clawdiy-state-hardening` | `origin/013-clawdiy-state-hardening` | Needs decision |
| `014-clawdiy-smoke-jq-fix` | `origin/014-clawdiy-smoke-jq-fix` | Needs decision |
| `015-clawdiy-smoke-mount-resolution` | `origin/015-clawdiy-smoke-mount-resolution` | Needs decision |
| `016-clawdiy-restore-readiness-fix` | `origin/016-clawdiy-restore-readiness-fix` | Needs decision |
| `017-clawdiy-remote-oauth-lifecycle` | `origin/017-clawdiy-remote-oauth-lifecycle` | Needs decision |
| `017-clawdiy-workspace-mount-fix` | `origin/017-clawdiy-workspace-mount-fix` | Needs decision |
| `018-clawdiy-gateway-password-ui-fix` | `origin/018-clawdiy-gateway-password-ui-fix` | Needs decision |
| `019-asc-fabrique-prototype` | `none` | Needs decision |
| `019-clawdiy-ui-onboarding-doc-correction` | `origin/019-clawdiy-ui-onboarding-doc-correction` | Needs decision |
| `020-agent-factory-prototype` | `origin/020-agent-factory-prototype` | Needs decision |
| `021-moltis-native-codex-update-advisory-writable` | `origin/021-moltis-native-codex-update-advisory` | Needs decision |
| `022-clawdiy-wizard-writability-fix` | `origin/022-clawdiy-wizard-writability-fix` | Needs decision |
| `022-telegram-ba-intake` | `origin/022-telegram-ba-intake` | Needs decision |
| `023-clawdiy-ci-preflight-runtime-home-fix` | `origin/023-clawdiy-ci-preflight-runtime-home-fix` | Needs decision |
| `023-telegram-factory-adapter` | `origin/023-telegram-factory-adapter` | Needs decision |
| `chore/topology-registry-after-cleanup-20260312` | `origin/chore/topology-registry-after-cleanup-20260312` | Needs decision |
| `codex/004-telegram-e2e-harness` | `origin/codex/004-telegram-e2e-harness` | Unmerged source branch; treat as extraction source, not merge target. |
| `codex/fix-bot` | `origin/codex/fix-bot` | PR #8 already merged, but branch still contains extra commits; do not merge raw. |
| `codex/gpt54-agents-split` | `origin/codex/gpt54-agents-split` | Needs decision |
| `codex/remote-uat-hardening` | `none` | Needs decision |
| `codex/webhook-main-backfill` | `origin/codex/webhook-main-backfill` | Needs decision |
| `codex/webhook-moltinger` | `origin/codex/webhook-moltinger` | Valuable but broad operational branch; extract selectively. |
| `docs/rca-moltis-0-10-18-stabilization` | `origin/main` | Needs decision |
| `feat/exploration-clawteam-framework-research` | `none` | Needs decision |
| `feat/molt-2-codex-update-monitor-new` | `origin/feat/molt-2-codex-update-monitor-new` | Needs decision |
| `feat/moltis-official-docker-update-v0-10-18` | `origin/feat/moltis-official-docker-update-v0-10-18` | Needs decision |
| `feat/moltis-pin-v0-10-18-mainline` | `origin/main` | Needs decision |
| `feat/moltis-pin-v0-10-18-prod` | `origin/feat/moltis-pin-v0-10-18-prod` | Needs decision |
| `feat/moltis-regular-update-proposal` | `origin/feat/moltis-regular-update-proposal` | Needs decision |
| `feat/openclaw-control-plane` | `none` | Needs decision |
| `fix/beads-recovery-audit-localization` | `origin/fix/beads-recovery-audit-localization` | Needs decision |
| `fix/deploy-codex-delivery-execbit` | `gone` | Tracking ref is gone; needs decision |
| `fix/deploy-tag-main-head-guard` | `gone` | Tracking ref is gone; needs decision |
| `fix/moltis-prod-0-10-18-gitops-guard` | `gone` | Tracking ref is gone; needs decision |
| `fix/moltis-update-proposal-stability` | `gone` | Tracking ref is gone; needs decision |
| `fix/moltis-version-regression-guard` | `gone` | Tracking ref is gone; needs decision |
| `fix/moltis-workflows-node24-readiness` | `gone` | Tracking ref is gone; needs decision |
| `fix/telegram-monitor-noise-guards` | `gone` | Tracking ref is gone; needs decision |
| `fix/telegram-monitor-polling-contract` | `gone` | Tracking ref is gone; needs decision |
| `fix/telegram-uat-false-pass-node24` | `gone` | Tracking ref is gone; needs decision |
| `fix/tracked-deploy-ci-context` | `gone` | Tracking ref is gone; needs decision |
| `fix/tracked-deploy-container-conflict` | `gone` | Tracking ref is gone; needs decision |
| `test/rca-guard-uat-20260307-0004` | `none` | Local-only test branch. |
| `test/rca-guard-uat-20260307-0015` | `gone` | Local-only stale test branch with gone upstream. |
| `tmp-merge-023-main-20260314195036` | `origin/main` | Needs decision |
| `tmp-pr35-fix` | `gone` | Tracking ref is gone; needs decision |
| `tmp-pr38-verify` | `origin/015-clawdiy-smoke-mount-resolution` | Needs decision |
| `tmp-pr39-fix` | `origin/012-codex-upstream-watcher` | Needs decision |
| `tmp-pr40-fix` | `origin/012-clawdiy-live-runtime-fix` | Needs decision |
| `tmp-pr41-fix` | `gone` | Tracking ref is gone; needs decision |
| `tmp-pr42-fix` | `gone` | Tracking ref is gone; needs decision |

## Remote Branches Not Merged Into `origin/main`

| Remote Branch | Current Intent |
|---|---|
| `origin/001-frontend` | Review later; currently dangling. |
| `origin/001-moltis-docker-deploy` | Historical; review before cleanup. |
| `origin/003-testing-infrastructure` | Historical planning branch. |
| `origin/007-codex-update-monitor` | Needs decision |
| `origin/008-codex-update-advisor` | Needs decision |
| `origin/009-codex-update-delivery-ux` | Needs decision |
| `origin/011-worktree-skill-extraction` | Needs decision |
| `origin/013-clawdiy-state-hardening` | Needs decision |
| `origin/014-clawdiy-smoke-jq-fix` | Needs decision |
| `origin/015-clawdiy-smoke-mount-resolution` | Needs decision |
| `origin/019-clawdiy-ui-onboarding-doc-correction` | Needs decision |
| `origin/020-agent-factory-prototype` | Needs decision |
| `origin/022-telegram-ba-intake` | Needs decision |
| `origin/023-beads-dolt-pilot-prep` | Needs decision |
| `origin/023-telegram-factory-adapter` | Needs decision |
| `origin/024-clawdiy-oauth-store-drift-fix` | Needs decision |
| `origin/024-web-factory-demo-adapter` | Needs decision |
| `origin/028-beads-issues-jsonl-rca` | Needs decision |
| `origin/029-beads-dolt-native-migration` | Needs decision |
| `origin/030-rebase-conflict-tail-audit` | Needs decision |
| `origin/chore/topology-registry-after-cleanup-20260312` | Needs decision |
| `origin/chore/topology-registry-publish` | Needs decision |
| `origin/codex/004-telegram-e2e-harness` | Source for future Telegram consolidation. |
| `origin/codex/fix-bot` | Source for future Telegram consolidation. |
| `origin/codex/webhook-moltinger` | Source for future Telegram consolidation. |
| `origin/feat/molt-2-codex-update-monitor-new` | Needs decision |
| `origin/feat/moltinger-ewde-codex-advisory-rollout` | Needs decision |
| `origin/feat/moltinger-z8m-1-moltis-backup-rollback-baseline` | Needs decision |
| `origin/feat/moltis-pin-v0-10-18-prod` | Needs decision |
| `origin/feat/moltis-regular-update-proposal` | Needs decision |
| `origin/fix/beads-recovery-audit-localization` | Needs decision |
| `origin/fix/worktree-topology-registry-single-writer-publish` | Needs decision |

## Reviewed Intent Awaiting Reconciliation

| Subject Type | Subject Key | Intent | Note | PR |
|---|---|---|---|---|
| `branch` | `005-worktree-ready-flow` | `active` | Valid parallel local feature branch; dedicated worktree exists. | - |
| `branch` | `006-git-topology-registry` | `active` | Active Speckit feature branch; dedicated authoritative worktree exists. | - |
| `branch` | `codex/gitops-metrics-fix` | `active` | Fresh replacement branch with open PR #18. | 18 |
| `branch` | `feat/gpt-5-moltis` | `active` | Active documentation and research branch; dedicated worktree exists. | - |
| `branch` | `feat/moltinger-jb6-gpt54-primary` | `active` | Active parallel task branch for GPT-5.4 primary provider-chain evaluation. | - |
| `remote` | `origin/001-clawdiy-agent-platform` | `active` | Active rollout branch for Clawdiy permanent-agent platform. | - |
| `remote` | `origin/001-clawdiy-agent-platform` | `active` | Active rollout branch for Clawdiy permanent-agent platform. | - |
| `remote` | `origin/005-worktree-ready-flow` | `active` | Active parallel feature branch. | - |
| `remote` | `origin/006-git-topology-registry` | `active` | Active topology-registry feature branch. | - |
| `remote` | `origin/codex/full-review` | `protected` | Active parallel session; exclude from automated cleanup. | 6 |
| `remote` | `origin/codex/gitops-metrics-fix` | `active` | Active replacement PR #18. | 18 |
| `remote` | `origin/feat/gpt-5-moltis` | `active` | Active feature branch. | - |
| `worktree` | `codex-gitops-metrics-fix` | `active` | Active replacement branch for closed PR #3; open PR #18. | 18 |
| `worktree` | `gpt-5-moltis` | `active` | Active research and documentation worktree. | - |
| `worktree` | `moltinger-jb6-gpt54-primary` | `active` | Active sibling worktree for the GPT-5.4 primary provider-chain task. | - |
| `worktree` | `primary-feature-001` | `active` | Active dedicated feature worktree for the Clawdiy permanent-agent platform. | - |
| `worktree` | `primary-feature-001` | `active` | Active dedicated feature worktree for the Clawdiy permanent-agent platform. | - |
| `worktree` | `primary-feature-005` | `active` | Active parallel Speckit feature worktree. | - |
| `worktree` | `primary-feature-006` | `active` | Active authoritative worktree for topology-registry automation. | - |

## Registry Warnings

- Reviewed intent contains 19 orphan record(s); keep them until topology catches up or the sidecar is reviewed.

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
