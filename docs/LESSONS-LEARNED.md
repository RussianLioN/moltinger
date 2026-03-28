# Lessons Learned (Auto-generated)

**Generated**: 2026-03-28
**Total Lessons**: 57

---

## Quick Reference Card


### By Severity


#### P0 (1 lessons)
- [Unauthorized File Deletion Attempt](../docs/rca/2026-03-04-unauthorized-file-deletion-attempt.md)

#### P1 (25 lessons)
- [Tracked Moltis deploy failed because the repo skill sync helper crashed in its EXIT trap under set -u](../docs/rca/2026-03-28-moltis-repo-skill-sync-trap-broke-deploy-verification.md)
- [Tracked Moltis deploy failed because auto-rollback reused an unsafe recreate path while health-monitor mutated Docker state during the same incident](../docs/rca/2026-03-28-moltis-deploy-auto-rollback-recreate-and-health-monitor-interference.md)
- [Moltis repo-managed codex-update skill existed in git but never became a live runtime skill](../docs/rca/2026-03-27-moltis-repo-skill-discovery-contract-drift.md)
- [Tracked Moltis deploy failed when docker compose force-recreate hit a slow-stop container race](../docs/rca/2026-03-27-moltis-deploy-force-recreate-race-on-slow-stop.md)
- [Managed worktree creation misread local Beads ownership as runtime readiness](../docs/rca/2026-03-26-worktree-create-misread-local-ownership-as-runtime-ready.md)
- [Beads worktree localization used stale bootstrap contracts and recreated the failure during Phase A](../docs/rca/2026-03-26-beads-worktree-localize-used-stale-bootstrap-contract.md)
- [Half-initialized Beads Dolt runtime was misclassified as a healthy local worktree state](../docs/rca/2026-03-24-beads-half-initialized-dolt-runtime-misclassified-as-healthy.md)
- [Tracked Moltis deploy cancelled by manual GitOps confirmation guard during CI workflow](../docs/rca/2026-03-20-tracked-moltis-deploy-cancelled-by-manual-gitops-guard.md)
- [Tracked Moltis deploy failed because backup restore-check logs polluted deploy.sh JSON stdout contract](../docs/rca/2026-03-20-tracked-deploy-json-contract-broken-by-restore-check-stdout.md)
- [Tracked Moltis deploy failed on legacy prometheus container-name conflict and opaque non-JSON failure envelope](../docs/rca/2026-03-20-tracked-deploy-failed-on-legacy-prometheus-container-name-conflict.md)
- [Telegram authoritative UAT could pass on provider/model resolution errors](../docs/rca/2026-03-20-telegram-uat-false-pass-on-model-not-found.md)
- [SSH heredoc runner-side expansion in deploy workflow](../docs/rca/2026-03-20-ssh-heredoc-runner-expansion-in-deploy.md)
- [Deploy workflow allowed tracked-version regression risk against newer running Moltis baseline](../docs/rca/2026-03-20-moltis-tracked-version-regression-guard.md)
- [Moltis stayed on 0.9.10 because pinned GHCR tag format was wrong and production deploy gate allowed bypass semantics](../docs/rca/2026-03-20-moltis-ghcr-tag-normalization-and-production-deploy-gate-hardening.md)
- [Moltis deploy blocked by unmanaged host-level Prometheus port conflict during full-stack compose up](../docs/rca/2026-03-20-moltis-deploy-blocked-by-unmanaged-prometheus-host-port-conflict.md)
- [Push deploy blocked by GitOps drift from exec-bit mismatch on codex-cli-update-delivery.sh](../docs/rca/2026-03-20-gitops-drift-on-codex-delivery-script-exec-bit.md)
- [Deploy collision and active-root symlink guard](../docs/rca/2026-03-20-deploy-collision-and-active-root-symlink-guard.md)
- [Clawdiy lost gpt-5.4 as default model after redeploy because runtime wizard state was not captured in tracked config](../docs/rca/2026-03-14-clawdiy-runtime-model-state-was-not-in-gitops.md)
- [Clawdiy deploy treated transient OpenClaw startup unhealthy as a hard latest-upgrade failure](../docs/rca/2026-03-14-clawdiy-latest-startup-warmup-was-treated-as-hard-failure.md)
- [Clawdiy upgrade to official Docker latest regressed live health and required baseline rollback](../docs/rca/2026-03-14-clawdiy-latest-channel-regressed-live-health.md)
- [Moltis deploy rollback to 0.9.10 after non-official image pin and missing GitOps checkout repair](../docs/rca/2026-03-13-moltis-official-docker-channel-and-gitops-repair.md)
- [GitOps repair workflow failed before execution because inline heredoc was not parse-safe in GitHub Actions](../docs/rca/2026-03-13-gitops-repair-heredoc-parse-failure.md)
- [Официальный мастер настройки Clawdiy не мог завершить OAuth из-за неверного контракта домашнего каталога OpenClaw](../docs/rca/2026-03-13-clawdiy-official-wizard-runtime-home-contract-mismatch.md)
- [Topology refresh misclassified permission boundary as a held lock](../docs/rca/2026-03-09-topology-lock-permission-boundary.md)
- [Self-inflicted GitOps drift from deployment audit markers](../docs/rca/2026-03-08-gitops-audit-markers-self-drift.md)

#### P2 (21 lessons)
- [Deploy stall watchdog self-failed on oversized GitHub Actions payloads](../docs/rca/2026-03-28-deploy-stall-watchdog-argjson-overflow.md)
- [Deploy hardening follow-up introduced a latent verify failure-path regression and queue-blind watchdog alerts](../docs/rca/2026-03-28-deploy-hardening-follow-up-verify-failure-and-watchdog-queue-semantics.md)
- [Test Suite gate failed again because sqlite3 was installed on host runner but missing in test-runner container runtime](../docs/rca/2026-03-20-test-suite-gate-failed-on-sqlite3-runtime-context-mismatch.md)
- [Telegram webhook monitor default expected webhook while production stayed in polling mode](../docs/rca/2026-03-20-telegram-webhook-monitor-webhook-requirement-drift.md)
- [Telegram monitor generated unsolicited user-facing traffic by default](../docs/rca/2026-03-20-telegram-monitor-default-noise-via-cron-and-probe-fallback.md)
- [Moltis update proposal workflow failed with workflow-file issue due to forbidden secrets context in step if](../docs/rca/2026-03-20-moltis-update-proposal-workflow-file-issue-on-secrets-context.md)
- [Moltis update proposal failed on perl replacement ambiguity and GitHub PR permission assumption](../docs/rca/2026-03-20-moltis-update-proposal-perl-backreference-and-pr-permission-fallback.md)
- [Moltis update proposal had contract drift: manual compare fallback existed in code but was not formalized as governance contract](../docs/rca/2026-03-20-moltis-update-proposal-manual-compare-contract-governance.md)
- [Beads wrapper delegated into a sibling worktree wrapper and left stale JSONL export](../docs/rca/2026-03-20-beads-wrapper-path-pollution-caused-stale-jsonl-export.md)
- [Deploy Clawdiy блокировался на dirty checkout без auditable repair path](../docs/rca/2026-03-14-clawdiy-deploy-missing-gitops-repair-path.md)
- [CI preflight ошибочно требовал materialized Clawdiy runtime home до deploy/render шага](../docs/rca/2026-03-14-clawdiy-ci-preflight-materialization-assumption.md)
- [Clawdiy UI bootstrap был задокументирован как Settings/OAuth flow вместо реального browser bootstrap](../docs/rca/2026-03-12-clawdiy-ui-bootstrap-doc-drift.md)
- [Hosted Clawdiy Control UI был развернут с password auth вместо token auth](../docs/rca/2026-03-12-clawdiy-hosted-control-ui-password-auth-mismatch.md)
- [UAT registry snapshots were treated as disposable during UAT maintenance](../docs/rca/2026-03-09-uat-registry-snapshot-loss.md)
- [Диагностика remote rollout началась без повторного применения Traefik-first уроков](../docs/rca/2026-03-09-remote-rollout-diagnosis-skipped-traefik-lessons.md)
- [Command-worktree follow-up UAT exposed preview, sync, and lock edge-case gaps](../docs/rca/2026-03-09-command-worktree-followup-uat.md)
- [Child worktree reconciliation renames authoritative feature worktree](../docs/rca/2026-03-08-topology-child-worktree-identity-drift.md)
- [Локальный runtime был поднят вместо работы с удалённым сервисом](../docs/rca/2026-03-08-remote-target-boundary-before-local-runtime.md)
- [Повторяющиеся падения GitHub Actions workflow (Drift + Deploy)](../docs/rca/2026-03-07-github-workflows-recurring-failures.md)
- [Повторный запрос уже документированных секретов](../docs/rca/2026-03-07-context-discovery-before-user-questions.md)
- [Token Bloat в инструкциях — повторяющаяся проблема](../docs/rca/2026-03-04-token-bloat-recurring.md)

#### P3 (9 lessons)
- [Test Suite gate failed because CI runner missed sqlite3 dependency for component_codex_session_path_repair](../docs/rca/2026-03-20-test-suite-gate-failed-on-missing-sqlite3-dependency.md)
- [Codex monitor threshold coupled to tomllib availability](../docs/rca/2026-03-15-codex-monitor-threshold-coupled-to-tomllib.md)
- [False GitHub Auth Failure During Codex Push](../docs/rca/2026-03-08-codex-github-auth-false-failure.md)
- [Ложные error-сигналы в успешных GitHub workflow](../docs/rca/2026-03-07-workflow-alert-severity-mismatch.md)
- [2026-03-06-browser-compat-speckit-desync](../docs/rca/2026-03-06-browser-compat-speckit-desync.md)
- [2026-03-03-sample-enhanced-rca](../docs/rca/2026-03-03-sample-enhanced-rca.md)
- [2026-03-03-rca-skill-creation](../docs/rca/2026-03-03-rca-skill-creation.md)
- [2026-03-03-rca-comprehensive-test](../docs/rca/2026-03-03-rca-comprehensive-test.md)
- [2026-03-03-git-branch-confusion](../docs/rca/2026-03-03-git-branch-confusion.md)

#### P4 (1 lessons)
- [Команда false завершилась с кодом 1](../docs/rca/2026-03-07-false-command-exit-code.md)


### By Category


#### cicd (27 lessons)
- [Tracked Moltis deploy failed because the repo skill sync helper crashed in its EXIT trap under set -u](../docs/rca/2026-03-28-moltis-repo-skill-sync-trap-broke-deploy-verification.md)
- [Tracked Moltis deploy failed because auto-rollback reused an unsafe recreate path while health-monitor mutated Docker state during the same incident](../docs/rca/2026-03-28-moltis-deploy-auto-rollback-recreate-and-health-monitor-interference.md)
- [Deploy stall watchdog self-failed on oversized GitHub Actions payloads](../docs/rca/2026-03-28-deploy-stall-watchdog-argjson-overflow.md)
- [Deploy hardening follow-up introduced a latent verify failure-path regression and queue-blind watchdog alerts](../docs/rca/2026-03-28-deploy-hardening-follow-up-verify-failure-and-watchdog-queue-semantics.md)
- [Tracked Moltis deploy failed when docker compose force-recreate hit a slow-stop container race](../docs/rca/2026-03-27-moltis-deploy-force-recreate-race-on-slow-stop.md)
- [Tracked Moltis deploy cancelled by manual GitOps confirmation guard during CI workflow](../docs/rca/2026-03-20-tracked-moltis-deploy-cancelled-by-manual-gitops-guard.md)
- [Tracked Moltis deploy failed because backup restore-check logs polluted deploy.sh JSON stdout contract](../docs/rca/2026-03-20-tracked-deploy-json-contract-broken-by-restore-check-stdout.md)
- [Tracked Moltis deploy failed on legacy prometheus container-name conflict and opaque non-JSON failure envelope](../docs/rca/2026-03-20-tracked-deploy-failed-on-legacy-prometheus-container-name-conflict.md)
- [Test Suite gate failed again because sqlite3 was installed on host runner but missing in test-runner container runtime](../docs/rca/2026-03-20-test-suite-gate-failed-on-sqlite3-runtime-context-mismatch.md)
- [Test Suite gate failed because CI runner missed sqlite3 dependency for component_codex_session_path_repair](../docs/rca/2026-03-20-test-suite-gate-failed-on-missing-sqlite3-dependency.md)
- [Telegram authoritative UAT could pass on provider/model resolution errors](../docs/rca/2026-03-20-telegram-uat-false-pass-on-model-not-found.md)
- [SSH heredoc runner-side expansion in deploy workflow](../docs/rca/2026-03-20-ssh-heredoc-runner-expansion-in-deploy.md)
- [Moltis update proposal workflow failed with workflow-file issue due to forbidden secrets context in step if](../docs/rca/2026-03-20-moltis-update-proposal-workflow-file-issue-on-secrets-context.md)
- [Moltis update proposal failed on perl replacement ambiguity and GitHub PR permission assumption](../docs/rca/2026-03-20-moltis-update-proposal-perl-backreference-and-pr-permission-fallback.md)
- [Deploy workflow allowed tracked-version regression risk against newer running Moltis baseline](../docs/rca/2026-03-20-moltis-tracked-version-regression-guard.md)
- [Moltis stayed on 0.9.10 because pinned GHCR tag format was wrong and production deploy gate allowed bypass semantics](../docs/rca/2026-03-20-moltis-ghcr-tag-normalization-and-production-deploy-gate-hardening.md)
- [Moltis deploy blocked by unmanaged host-level Prometheus port conflict during full-stack compose up](../docs/rca/2026-03-20-moltis-deploy-blocked-by-unmanaged-prometheus-host-port-conflict.md)
- [Push deploy blocked by GitOps drift from exec-bit mismatch on codex-cli-update-delivery.sh](../docs/rca/2026-03-20-gitops-drift-on-codex-delivery-script-exec-bit.md)
- [Deploy collision and active-root symlink guard](../docs/rca/2026-03-20-deploy-collision-and-active-root-symlink-guard.md)
- [Codex monitor threshold coupled to tomllib availability](../docs/rca/2026-03-15-codex-monitor-threshold-coupled-to-tomllib.md)
- [Clawdiy deploy treated transient OpenClaw startup unhealthy as a hard latest-upgrade failure](../docs/rca/2026-03-14-clawdiy-latest-startup-warmup-was-treated-as-hard-failure.md)
- [Clawdiy upgrade to official Docker latest regressed live health and required baseline rollback](../docs/rca/2026-03-14-clawdiy-latest-channel-regressed-live-health.md)
- [Deploy Clawdiy блокировался на dirty checkout без auditable repair path](../docs/rca/2026-03-14-clawdiy-deploy-missing-gitops-repair-path.md)
- [Moltis deploy rollback to 0.9.10 after non-official image pin and missing GitOps checkout repair](../docs/rca/2026-03-13-moltis-official-docker-channel-and-gitops-repair.md)
- [Self-inflicted GitOps drift from deployment audit markers](../docs/rca/2026-03-08-gitops-audit-markers-self-drift.md)
- [Ложные error-сигналы в успешных GitHub workflow](../docs/rca/2026-03-07-workflow-alert-severity-mismatch.md)
- [Повторяющиеся падения GitHub Actions workflow (Drift + Deploy)](../docs/rca/2026-03-07-github-workflows-recurring-failures.md)

#### generic (5 lessons)
- [2026-03-06-browser-compat-speckit-desync](../docs/rca/2026-03-06-browser-compat-speckit-desync.md)
- [2026-03-03-sample-enhanced-rca](../docs/rca/2026-03-03-sample-enhanced-rca.md)
- [2026-03-03-rca-skill-creation](../docs/rca/2026-03-03-rca-skill-creation.md)
- [2026-03-03-rca-comprehensive-test](../docs/rca/2026-03-03-rca-comprehensive-test.md)
- [2026-03-03-git-branch-confusion](../docs/rca/2026-03-03-git-branch-confusion.md)

#### process (18 lessons)
- [Moltis repo-managed codex-update skill existed in git but never became a live runtime skill](../docs/rca/2026-03-27-moltis-repo-skill-discovery-contract-drift.md)
- [Managed worktree creation misread local Beads ownership as runtime readiness](../docs/rca/2026-03-26-worktree-create-misread-local-ownership-as-runtime-ready.md)
- [Beads worktree localization used stale bootstrap contracts and recreated the failure during Phase A](../docs/rca/2026-03-26-beads-worktree-localize-used-stale-bootstrap-contract.md)
- [Half-initialized Beads Dolt runtime was misclassified as a healthy local worktree state](../docs/rca/2026-03-24-beads-half-initialized-dolt-runtime-misclassified-as-healthy.md)
- [Telegram webhook monitor default expected webhook while production stayed in polling mode](../docs/rca/2026-03-20-telegram-webhook-monitor-webhook-requirement-drift.md)
- [Telegram monitor generated unsolicited user-facing traffic by default](../docs/rca/2026-03-20-telegram-monitor-default-noise-via-cron-and-probe-fallback.md)
- [Moltis update proposal had contract drift: manual compare fallback existed in code but was not formalized as governance contract](../docs/rca/2026-03-20-moltis-update-proposal-manual-compare-contract-governance.md)
- [Clawdiy lost gpt-5.4 as default model after redeploy because runtime wizard state was not captured in tracked config](../docs/rca/2026-03-14-clawdiy-runtime-model-state-was-not-in-gitops.md)
- [CI preflight ошибочно требовал materialized Clawdiy runtime home до deploy/render шага](../docs/rca/2026-03-14-clawdiy-ci-preflight-materialization-assumption.md)
- [Официальный мастер настройки Clawdiy не мог завершить OAuth из-за неверного контракта домашнего каталога OpenClaw](../docs/rca/2026-03-13-clawdiy-official-wizard-runtime-home-contract-mismatch.md)
- [Clawdiy UI bootstrap был задокументирован как Settings/OAuth flow вместо реального browser bootstrap](../docs/rca/2026-03-12-clawdiy-ui-bootstrap-doc-drift.md)
- [Hosted Clawdiy Control UI был развернут с password auth вместо token auth](../docs/rca/2026-03-12-clawdiy-hosted-control-ui-password-auth-mismatch.md)
- [UAT registry snapshots were treated as disposable during UAT maintenance](../docs/rca/2026-03-09-uat-registry-snapshot-loss.md)
- [Диагностика remote rollout началась без повторного применения Traefik-first уроков](../docs/rca/2026-03-09-remote-rollout-diagnosis-skipped-traefik-lessons.md)
- [Локальный runtime был поднят вместо работы с удалённым сервисом](../docs/rca/2026-03-08-remote-target-boundary-before-local-runtime.md)
- [False GitHub Auth Failure During Codex Push](../docs/rca/2026-03-08-codex-github-auth-false-failure.md)
- [Повторный запрос уже документированных секретов](../docs/rca/2026-03-07-context-discovery-before-user-questions.md)
- [Token Bloat в инструкциях — повторяющаяся проблема](../docs/rca/2026-03-04-token-bloat-recurring.md)

#### security (1 lessons)
- [Unauthorized File Deletion Attempt](../docs/rca/2026-03-04-unauthorized-file-deletion-attempt.md)

#### shell (6 lessons)
- [Beads wrapper delegated into a sibling worktree wrapper and left stale JSONL export](../docs/rca/2026-03-20-beads-wrapper-path-pollution-caused-stale-jsonl-export.md)
- [GitOps repair workflow failed before execution because inline heredoc was not parse-safe in GitHub Actions](../docs/rca/2026-03-13-gitops-repair-heredoc-parse-failure.md)
- [Topology refresh misclassified permission boundary as a held lock](../docs/rca/2026-03-09-topology-lock-permission-boundary.md)
- [Command-worktree follow-up UAT exposed preview, sync, and lock edge-case gaps](../docs/rca/2026-03-09-command-worktree-followup-uat.md)
- [Child worktree reconciliation renames authoritative feature worktree](../docs/rca/2026-03-08-topology-child-worktree-identity-drift.md)
- [Команда false завершилась с кодом 1](../docs/rca/2026-03-07-false-command-exit-code.md)


### Popular Tags

- `deploy` (17 lessons)
- `gitops` (16 lessons)
- `github-actions` (16 lessons)
- `cicd` (16 lessons)
- `moltis` (15 lessons)
- `rca` (10 lessons)
- `process` (9 lessons)
- `lessons` (9 lessons)
- `git-worktree` (8 lessons)
- `clawdiy` (8 lessons)


---

## Statistics

| Metric | Value |
|--------|-------|
| Total Lessons | 57 |
| Critical (P0/P1) | 26 |
| Categories | 5 |
| Unique Tags | 129 |

---

## How to Search

```bash
# Find lessons by severity
./scripts/query-lessons.sh --severity P1

# Find lessons by tag
./scripts/query-lessons.sh --tag docker

# Find lessons by category
./scripts/query-lessons.sh --category deployment

# Show all lessons
./scripts/query-lessons.sh --all
```

---

*This file is auto-generated by scripts/build-lessons-index.sh*
*Do not edit manually - changes will be overwritten*
