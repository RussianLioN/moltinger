# Git Topology Registry

**Status**: Generated artifact from live git topology and reviewed intent sidecar
**Scope**: Canonical maintainer workstation snapshot
**Purpose**: Single reference for current git worktrees, active branches, and branches that still require a decision.
**Publish**: From the dedicated non-main topology publish branch `chore/topology-registry-publish` run `scripts/git-topology-registry.sh refresh --write-doc`
**Privacy Note**: This committed artifact is sanitized. Absolute local paths stay in live git state, not in tracked docs.

## Current Worktrees

| Worktree ID | Branch | Location Class | Status |
|---|---|---|---|
| `activity-log-llm-tool-logging-fix` | `feat/activity-log-llm-tool-logging-fix` | `sibling-worktree` | Needs decision |
| `codex-full-review` | `codex/full-review` | `codex-managed` | Parallel Codex session; protect from cleanup. |
| `moltinger-120-gitops-check-latency` | `fix/gitops-check-latency` | `sibling-worktree` | Needs decision |
| `moltinger-121-bd-landing-contract` | `fix/bd-landing-contract` | `sibling-worktree` | Needs decision |
| `moltinger-248-telegram-e2e-default-branch` | `feat/moltinger-248-telegram-e2e-default-branch` | `sibling-worktree` | Needs decision |
| `moltinger-browser-main-profile-contract` | `pr-browser-main-moltis-profile-contract` | `sibling-worktree` | Needs decision |
| `moltinger-chore-retire-001-clawdiy-topology` | `chore/retire-001-clawdiy-topology` | `sibling-worktree` | Needs decision |
| `moltinger-chore-topology-registry-publish` | `chore/topology-registry-publish` | `sibling-worktree` | Needs decision |
| `moltinger-dmi-telegram-webhook-rollout` | `feat/moltinger-dmi-telegram-webhook-rollout` | `sibling-worktree` | Needs decision |
| `moltinger-ewde-codex-advisory-rollout` | `feat/moltinger-ewde-codex-advisory-rollout` | `sibling-worktree` | Needs decision |
| `moltinger-fix-codex-skill-discovery` | `fix/moltis-repo-skill-sync-trap` | `sibling-worktree` | Needs decision |
| `moltinger-fix-memory-search-bridge` | `fix/memory-search-bridge` | `sibling-worktree` | Needs decision |
| `moltinger-fix-moltis-deploy-verification-stability` | `fix/moltis-deploy-verification-stability` | `sibling-worktree` | Needs decision |
| `moltinger-fix-server-storage-reclamation` | `fix/server-storage-reclamation` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-clean-delivery-after-tavily` | `fix/telegram-clean-delivery-after-tavily` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-clean-delivery-numeric-to` | `fix/telegram-clean-delivery-numeric-to` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-memory-and-deploy-cleanup` | `fix/telegram-memory-and-deploy-cleanup` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-memory-search-clean-delivery` | `fix/telegram-memory-search-clean-delivery` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-memory-search-delivery-clean` | `fix/telegram-memory-search-delivery-clean` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-project-hook-guard-rescue` | `fix/telegram-project-hook-guard-rescue` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-tavily-activitylog-clean-delivery` | `fix/telegram-tavily-activitylog-clean-delivery` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-tavily-clean-delivery` | `fix/telegram-tavily-clean-delivery` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-tavily-delivery-cleanup` | `fix/telegram-tavily-delivery-cleanup` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-tavily-delivery-hardening` | `fix/telegram-tavily-delivery-hardening` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-tavily-delivery-scrub` | `fix/telegram-tavily-delivery-scrub` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-tavily-mcp-passthrough` | `fix/telegram-tavily-mcp-passthrough` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-tavily-validation-activity-leak` | `fix/telegram-beforetool-telemetry-scope` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-uat-artifact-drift` | `fix/telegram-uat-artifact-drift` | `sibling-worktree` | Needs decision |
| `moltinger-fix-telegram-uat-output-gitops-safe` | `fix/telegram-uat-output-gitops-safe` | `sibling-worktree` | Needs decision |
| `moltinger-hotfix-telegram-runtime-hook-sync` | `hotfix/telegram-runtime-hook-sync` | `sibling-worktree` | Needs decision |
| `moltinger-main` | `DETACHED` | `sibling-worktree` | Needs decision |
| `moltinger-main-browser-canary-session-timeout-contract` | `fix/moltis-browser-canary-session-timeout-contract` | `sibling-worktree` | Needs decision |
| `moltinger-main-browser-profile-hotfix` | `fix/main-browser-profile-hotfix` | `sibling-worktree` | Needs decision |
| `moltinger-main-browser-sandbox-wrapper-ownership` | `fix/moltis-browser-sandbox-wrapper-ownership` | `sibling-worktree` | Needs decision |
| `moltinger-main-browser-timeout-contract` | `fix/moltis-browser-timeout-contract` | `sibling-worktree` | Needs decision |
| `moltinger-main-gpt54-integration` | `integration/gpt54-main` | `sibling-worktree` | Needs decision |
| `moltinger-main-hotfix-deploy` | `hotfix/telegram-skill-fix-main` | `sibling-worktree` | Needs decision |
| `moltinger-main-hotfix-telegram-skill-authoring-main-carrier` | `hotfix/telegram-skill-authoring-main-carrier` | `sibling-worktree` | Needs decision |
| `moltinger-main-landing-telegram-template-fix.jsfzuc` | `landing/telegram-template-fix-main` | `sibling-worktree` | Needs decision |
| `moltinger-main-postdeploy-verification-drift` | `fix/moltis-postdeploy-verification-drift` | `sibling-worktree` | Needs decision |
| `moltinger-main-prod-fix-20260401` | `tmp/telegram-skill-fix-main-20260401` | `sibling-worktree` | Needs decision |
| `moltinger-main-prod-fix-20260401b` | `tmp/telegram-skill-fix-main-20260401b` | `sibling-worktree` | Needs decision |
| `moltinger-main-prod-hotfix-20260401` | `DETACHED` | `sibling-worktree` | Needs decision |
| `moltinger-main-prod-hotfix-merge` | `merge/031-to-main-telegram-skill-fix` | `sibling-worktree` | Needs decision |
| `moltinger-main-prod-telegram-fix` | `tmp/telegram-prod-fix-land` | `sibling-worktree` | Needs decision |
| `moltinger-main-prod-telegram-skill-merge` | `tmp/telegram-skill-prod-merge-20260401` | `sibling-worktree` | Needs decision |
| `moltinger-main-telegram-activity-leak-main-landing` | `fix/runtime-attestation-refreshable-oauth` | `sibling-worktree` | Needs decision |
| `moltinger-main-telegram-prod-land-20260401` | `tmp/telegram-prod-land-20260401` | `sibling-worktree` | Needs decision |
| `moltinger-main-telegram-runtime-hotfix-landing` | `tmp/telegram-runtime-hotfix-landing` | `sibling-worktree` | Needs decision |
| `moltinger-main-telegram-skill-fix-land` | `tmp/telegram-skill-fix-land-20260401` | `sibling-worktree` | Needs decision |
| `moltinger-main-telegram-skill-fix-land-20260401` | `DETACHED` | `sibling-worktree` | Needs decision |
| `moltinger-main-telegram-skill-land-clean` | `tmp/main-telegram-skill-land` | `sibling-worktree` | Needs decision |
| `moltinger-main-telegram-skills-main-landing` | `tmp/telegram-skills-main-landing` | `sibling-worktree` | Needs decision |
| `moltinger-ollama-retention-policy` | `fix/ainetic-ollama-retention-policy` | `sibling-worktree` | Needs decision |
| `moltinger-server-storage-followups` | `fix/server-storage-followups` | `sibling-worktree` | Needs decision |
| `moltinger-server-storage-hardening` | `followup/server-storage-hardening` | `sibling-worktree` | Needs decision |
| `moltinger-storage-hardening-followups` | `fix/storage-hardening-followups` | `sibling-worktree` | Needs decision |
| `moltinger-storage-maintenance-json-report` | `fix/storage-maintenance-json-report` | `sibling-worktree` | Needs decision |
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
| `primary-feature-031` | `031-moltis-reliability-diagnostics` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-033` | `033-moltis-browser-session-logbook-fix` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-034` | `034-moltis-skill-discovery-and-telegram-leak-regressions` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-036` | `036-moltis-telegram-longrun-research` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-037` | `037-topology-publish-beads-runtime-repair` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-038` | `038-telegram-cloneable-agent` | `dedicated-feature-worktree` | Needs decision |
| `primary-feature-039` | `039-telegram-project-hook-guard` | `dedicated-feature-worktree` | Needs decision |
| `primary-root` | `main` | `primary` | Canonical root worktree; neutral base for triage, cleanup, and merges. |
| `telegram-browser-tavily-timeout` | `feat/telegram-browser-tavily-timeout` | `sibling-worktree` | Needs decision |
| `telegram-channel-model-id-fix` | `feat/telegram-channel-model-id-fix` | `sibling-worktree` | Needs decision |
| `telegram-hard-disable-tools-status-contract` | `feat/telegram-hard-disable-tools-status-contract` | `sibling-worktree` | Needs decision |
| `telegram-project-local-hook-guard` | `feat/telegram-project-local-hook-guard` | `sibling-worktree` | Needs decision |
| `telegram-status-determinism-fix` | `feat/telegram-status-determinism-fix` | `sibling-worktree` | Needs decision |
| `telegram-status-guardrail-and-runtime-skill-prune` | `feat/telegram-status-guardrail-and-runtime-skill-prune` | `sibling-worktree` | Needs decision |

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
| `031-moltis-reliability-diagnostics` | `origin/031-moltis-reliability-diagnostics` | Needs decision |
| `033-moltis-browser-session-logbook-fix` | `origin/033-moltis-browser-session-logbook-fix` | Needs decision |
| `034-moltis-skill-discovery-and-telegram-leak-regressions` | `origin/034-moltis-skill-discovery-and-telegram-leak-regressions` | Needs decision |
| `036-moltis-telegram-longrun-research` | `origin/036-moltis-telegram-longrun-research` | Needs decision |
| `037-topology-publish-beads-runtime-repair` | `origin/037-topology-publish-beads-runtime-repair` | Needs decision |
| `038-telegram-cloneable-agent` | `origin/038-telegram-cloneable-agent` | Needs decision |
| `039-telegram-project-hook-guard` | `origin/039-telegram-project-hook-guard` | Needs decision |
| `chore/retire-001-clawdiy-topology` | `origin/main` | Needs decision |
| `chore/topology-registry-publish` | `origin/main` | Needs decision |
| `codex/full-review` | `origin/codex/full-review` | Open parallel branch; separate worktree exists. |
| `feat/activity-log-llm-tool-logging-fix` | `origin/feat/activity-log-llm-tool-logging-fix` | Needs decision |
| `feat/moltinger-248-telegram-e2e-default-branch` | `none` | Needs decision |
| `feat/moltinger-dmi-telegram-webhook-rollout` | `none` | Needs decision |
| `feat/moltinger-ewde-codex-advisory-rollout` | `origin/feat/moltinger-ewde-codex-advisory-rollout` | Needs decision |
| `feat/moltinger-z8m-1-moltis-backup-rollback-baseline` | `origin/feat/moltinger-z8m-1-moltis-backup-rollback-baseline` | Needs decision |
| `feat/moltinger-z8m-2-moltis-skills-subagents-abilities-expansion` | `none` | Needs decision |
| `feat/telegram-browser-tavily-timeout` | `origin/feat/telegram-browser-tavily-timeout` | Needs decision |
| `feat/telegram-channel-model-id-fix` | `origin/feat/telegram-channel-model-id-fix` | Needs decision |
| `feat/telegram-hard-disable-tools-status-contract` | `origin/feat/telegram-hard-disable-tools-status-contract` | Needs decision |
| `feat/telegram-project-local-hook-guard` | `origin/feat/telegram-project-local-hook-guard` | Needs decision |
| `feat/telegram-status-determinism-fix` | `origin/feat/telegram-status-determinism-fix` | Needs decision |
| `feat/telegram-status-guardrail-and-runtime-skill-prune` | `origin/feat/telegram-status-guardrail-and-runtime-skill-prune` | Needs decision |
| `fix/ainetic-ollama-retention-policy` | `origin/main` | Needs decision |
| `fix/bd-landing-contract` | `gone` | Tracking ref is gone; needs decision |
| `fix/gitops-check-latency` | `gone` | Tracking ref is gone; needs decision |
| `fix/main-browser-profile-hotfix` | `origin/main` | Needs decision |
| `fix/memory-search-bridge` | `origin/main` | Needs decision |
| `fix/moltis-browser-canary-session-timeout-contract` | `origin/fix/moltis-browser-canary-session-timeout-contract` | Needs decision |
| `fix/moltis-browser-sandbox-wrapper-ownership` | `origin/fix/moltis-browser-sandbox-wrapper-ownership` | Needs decision |
| `fix/moltis-browser-timeout-contract` | `origin/fix/moltis-browser-timeout-contract` | Needs decision |
| `fix/moltis-deploy-verification-stability` | `origin/main` | Needs decision |
| `fix/moltis-postdeploy-verification-drift` | `origin/fix/moltis-postdeploy-verification-drift` | Needs decision |
| `fix/moltis-repo-skill-sync-trap` | `origin/fix/moltis-repo-skill-sync-trap` | Needs decision |
| `fix/runtime-attestation-refreshable-oauth` | `origin/fix/runtime-attestation-refreshable-oauth` | Needs decision |
| `fix/server-storage-followups` | `origin/main` | Needs decision |
| `fix/server-storage-reclamation` | `origin/fix/server-storage-reclamation` | Needs decision |
| `fix/storage-hardening-followups` | `origin/main` | Needs decision |
| `fix/storage-maintenance-json-report` | `origin/fix/storage-maintenance-json-report` | Needs decision |
| `fix/telegram-beforetool-telemetry-scope` | `none` | Needs decision |
| `fix/telegram-clean-delivery-after-tavily` | `origin/fix/telegram-clean-delivery-after-tavily` | Needs decision |
| `fix/telegram-clean-delivery-numeric-to` | `origin/fix/telegram-clean-delivery-numeric-to` | Needs decision |
| `fix/telegram-memory-and-deploy-cleanup` | `origin/main` | Needs decision |
| `fix/telegram-memory-search-clean-delivery` | `origin/main` | Needs decision |
| `fix/telegram-memory-search-delivery-clean` | `origin/main` | Needs decision |
| `fix/telegram-project-hook-guard-rescue` | `origin/fix/telegram-project-hook-guard-rescue` | Needs decision |
| `fix/telegram-tavily-activitylog-clean-delivery` | `origin/fix/telegram-tavily-activitylog-clean-delivery` | Needs decision |
| `fix/telegram-tavily-clean-delivery` | `origin/fix/telegram-tavily-clean-delivery` | Needs decision |
| `fix/telegram-tavily-delivery-cleanup` | `origin/fix/telegram-tavily-delivery-cleanup` | Needs decision |
| `fix/telegram-tavily-delivery-hardening` | `origin/fix/telegram-tavily-delivery-hardening` | Needs decision |
| `fix/telegram-tavily-delivery-scrub` | `origin/fix/telegram-tavily-delivery-scrub` | Needs decision |
| `fix/telegram-tavily-mcp-passthrough` | `origin/fix/telegram-tavily-mcp-passthrough` | Needs decision |
| `fix/telegram-uat-artifact-drift` | `origin/main` | Needs decision |
| `fix/telegram-uat-output-gitops-safe` | `origin/fix/telegram-uat-output-gitops-safe` | Needs decision |
| `fix/worktree-topology-registry-single-writer-publish` | `origin/fix/worktree-topology-registry-single-writer-publish` | Needs decision |
| `followup/server-storage-hardening` | `origin/main` | Needs decision |
| `hotfix/telegram-runtime-hook-sync` | `origin/hotfix/telegram-runtime-hook-sync` | Needs decision |
| `hotfix/telegram-skill-authoring-main-carrier` | `origin/main` | Needs decision |
| `hotfix/telegram-skill-fix-main` | `origin/main` | Needs decision |
| `integration/gpt54-main` | `origin/integration/gpt54-main` | Needs decision |
| `landing/telegram-template-fix-main` | `none` | Needs decision |
| `merge/031-to-main-telegram-skill-fix` | `origin/merge/031-to-main-telegram-skill-fix` | Needs decision |
| `pr-browser-main-moltis-profile-contract` | `origin/pr-browser-main-moltis-profile-contract` | Needs decision |
| `tmp/main-telegram-skill-land` | `origin/main` | Needs decision |
| `tmp/telegram-prod-fix-land` | `origin/main` | Needs decision |
| `tmp/telegram-prod-land-20260401` | `origin/main` | Needs decision |
| `tmp/telegram-runtime-hotfix-landing` | `origin/main` | Needs decision |
| `tmp/telegram-skill-fix-land-20260401` | `none` | Needs decision |
| `tmp/telegram-skill-fix-main-20260401` | `origin/main` | Needs decision |
| `tmp/telegram-skill-fix-main-20260401b` | `origin/main` | Needs decision |
| `tmp/telegram-skill-prod-merge-20260401` | `origin/main` | Needs decision |
| `tmp/telegram-skills-main-landing` | `origin/main` | Needs decision |
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
| `backup/031-moltis-reliability-diagnostics-pre-main-align-20260402` | `none` | Needs decision |
| `backup/chore-topology-registry-publish-pre-20260402` | `none` | Needs decision |
| `backup/chore-topology-registry-publish-pre-normalize-20260331` | `none` | Needs decision |
| `chore/topology-registry-after-cleanup-20260312` | `origin/chore/topology-registry-after-cleanup-20260312` | Needs decision |
| `chore/topology-registry-snapshot-contract` | `origin/chore/topology-registry-snapshot-contract` | Needs decision |
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
| `fix/moltis-codex-skill-discovery-contract` | `origin/fix/moltis-codex-skill-discovery-contract` | Needs decision |
| `fix/moltis-deploy-recreate-watchdog` | `origin/main` | Needs decision |
| `fix/moltis-prod-0-10-18-gitops-guard` | `gone` | Tracking ref is gone; needs decision |
| `fix/moltis-rollout-watchdog-hardening` | `origin/fix/moltis-rollout-watchdog-hardening` | Needs decision |
| `fix/moltis-update-proposal-stability` | `gone` | Tracking ref is gone; needs decision |
| `fix/moltis-verify-failure-contract` | `origin/fix/moltis-verify-failure-contract` | Needs decision |
| `fix/moltis-version-regression-guard` | `gone` | Tracking ref is gone; needs decision |
| `fix/moltis-workflows-node24-readiness` | `gone` | Tracking ref is gone; needs decision |
| `fix/prod-mutation-guard-actions-token` | `origin/fix/prod-mutation-guard-actions-token` | Needs decision |
| `fix/telegram-activity-leak-main-landing` | `origin/fix/telegram-activity-leak-main-landing` | Needs decision |
| `fix/telegram-monitor-noise-guards` | `gone` | Tracking ref is gone; needs decision |
| `fix/telegram-monitor-polling-contract` | `gone` | Tracking ref is gone; needs decision |
| `fix/telegram-uat-false-pass-node24` | `gone` | Tracking ref is gone; needs decision |
| `fix/tracked-deploy-ci-context` | `gone` | Tracking ref is gone; needs decision |
| `fix/tracked-deploy-container-conflict` | `gone` | Tracking ref is gone; needs decision |
| `pr-130-review` | `none` | Needs decision |
| `pr2-main-moltis-docs-carrier` | `origin/pr2-main-moltis-docs-carrier` | Needs decision |
| `preserve/fix-moltis-update-proposal-telegram-notify-legacy` | `gone` | Tracking ref is gone; needs decision |
| `recovery/root-worktree-main-20260402T130646Z` | `none` | Needs decision |
| `test/rca-guard-uat-20260307-0004` | `none` | Local-only test branch. |
| `test/rca-guard-uat-20260307-0015` | `gone` | Local-only stale test branch with gone upstream. |
| `tmp-merge-023-main-20260314195036` | `origin/main` | Needs decision |
| `tmp-pr35-fix` | `gone` | Tracking ref is gone; needs decision |
| `tmp-pr38-verify` | `origin/015-clawdiy-smoke-mount-resolution` | Needs decision |
| `tmp-pr39-fix` | `origin/012-codex-upstream-watcher` | Needs decision |
| `tmp-pr40-fix` | `origin/012-clawdiy-live-runtime-fix` | Needs decision |
| `tmp-pr41-fix` | `gone` | Tracking ref is gone; needs decision |
| `tmp-pr42-fix` | `gone` | Tracking ref is gone; needs decision |
| `tmp/fng-repro-2` | `none` | Needs decision |
| `tmp/telegram-skill-fix-main-20260401c` | `none` | Needs decision |

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
| `origin/036-moltis-telegram-longrun-research` | Needs decision |
| `origin/037-topology-publish-beads-runtime-repair` | Needs decision |
| `origin/038-telegram-cloneable-agent` | Needs decision |
| `origin/chore/topology-registry-after-cleanup-20260312` | Needs decision |
| `origin/chore/topology-registry-publish` | Needs decision |
| `origin/chore/topology-registry-snapshot-contract` | Needs decision |
| `origin/codex/004-telegram-e2e-harness` | Source for future Telegram consolidation. |
| `origin/codex/fix-bot` | Source for future Telegram consolidation. |
| `origin/codex/webhook-moltinger` | Source for future Telegram consolidation. |
| `origin/feat/activity-log-llm-tool-logging-fix` | Needs decision |
| `origin/feat/molt-2-codex-update-monitor-new` | Needs decision |
| `origin/feat/moltinger-ewde-codex-advisory-rollout` | Needs decision |
| `origin/feat/moltinger-z8m-1-moltis-backup-rollback-baseline` | Needs decision |
| `origin/feat/moltis-pin-v0-10-18-prod` | Needs decision |
| `origin/feat/moltis-regular-update-proposal` | Needs decision |
| `origin/feat/telegram-project-local-hook-guard` | Needs decision |
| `origin/fix/beads-recovery-audit-localization` | Needs decision |
| `origin/fix/moltis-postdeploy-verification-drift` | Needs decision |
| `origin/fix/moltis-rollout-watchdog-hardening` | Needs decision |
| `origin/fix/server-storage-reclamation` | Needs decision |
| `origin/fix/storage-maintenance-json-report` | Needs decision |
| `origin/fix/telegram-clean-delivery-after-tavily` | Needs decision |
| `origin/fix/telegram-project-hook-guard-rescue` | Needs decision |
| `origin/fix/telegram-tavily-activitylog-clean-delivery` | Needs decision |
| `origin/fix/telegram-tavily-clean-delivery` | Needs decision |
| `origin/fix/telegram-tavily-delivery-cleanup` | Needs decision |
| `origin/fix/telegram-tavily-delivery-hardening` | Needs decision |
| `origin/fix/telegram-tavily-delivery-scrub` | Needs decision |
| `origin/fix/telegram-tavily-mcp-passthrough` | Needs decision |
| `origin/fix/telegram-uat-output-gitops-safe` | Needs decision |
| `origin/fix/worktree-topology-registry-single-writer-publish` | Needs decision |
| `origin/hotfix/telegram-runtime-hook-sync` | Needs decision |
| `origin/merge/031-to-main-telegram-skill-fix` | Needs decision |

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
