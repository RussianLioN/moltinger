# Lessons Learned (Auto-generated)

**Generated**: 2026-04-15
**Total Lessons**: 80

---

## Quick Reference Card


### By Severity


#### P0 (1 lessons)
- [Unauthorized File Deletion Attempt](../docs/rca/2026-03-04-unauthorized-file-deletion-attempt.md)

#### P1 (38 lessons)
- [Worktree governance helpers trusted contextual Beads state instead of canonical ownership/runtime evidence](../docs/rca/2026-04-15-worktree-governance-helpers-trusted-contextual-beads-state.md)
- [Telegram codex-update live runtime ignored in-band hook modify despite correct guard output](../docs/rca/2026-04-14-telegram-codex-update-live-runtime-ignored-inband-modify.md)
- [Telegram codex-update hard override did not terminalize blocked tool follow-up](../docs/rca/2026-04-14-telegram-codex-update-hard-override-did-not-terminalize-blocked-tool-followup.md)
- [Telegram codex-update direct fastpath raced underlying run](../docs/rca/2026-04-14-telegram-codex-update-direct-fastpath-raced-underlying-run.md)
- [Telegram codex-update classifier missed live BeforeLLMCall turns when messages content arrived as arrays](../docs/rca/2026-04-14-telegram-codex-update-array-content-bypassed-turn-classifier.md)
- [Telegram chat probe skill pointed to a missing wrapper entrypoint](../docs/rca/2026-04-14-telegram-chat-probe-skill-pointed-to-missing-wrapper-entrypoint.md)
- [Deploy host automation missing cron package bootstrap](../docs/rca/2026-04-14-deploy-host-automation-missing-cron-package-bootstrap.md)
- [Skill execution drifted into workaround behavior and task reports lacked a shared simple contract](../docs/rca/2026-04-09-skill-execution-and-reporting-contract-drift.md)
- [Runtime-only Beads repair still pointed at raw bootstrap after the CLI contract drifted](../docs/rca/2026-03-29-runtime-only-repair-contract-still-pointed-at-raw-bootstrap.md)
- [Managed worktree creation mixed up the create executor and hook bootstrap-source contract](../docs/rca/2026-03-28-worktree-create-helper-and-hook-bootstrap-source-drift.md)
- [Moltis Telegram user bots needed explicit stream_mode off](../docs/rca/2026-03-28-moltis-telegram-user-bots-needed-explicit-stream-mode-off.md)
- [Tracked Moltis deploy failed because the repo skill sync helper crashed in its EXIT trap under set -u](../docs/rca/2026-03-28-moltis-repo-skill-sync-trap-broke-deploy-verification.md)
- [Moltis operator browser session isolation and Telegram send attribution drift](../docs/rca/2026-03-28-moltis-operator-browser-session-isolation-and-telegram-send-attribution-drift.md)
- [Tracked Moltis deploy failed because auto-rollback reused an unsafe recreate path while health-monitor mutated Docker state during the same incident](../docs/rca/2026-03-28-moltis-deploy-auto-rollback-recreate-and-health-monitor-interference.md)
- [Moltis browser runs still timed out because the overall agent timeout matched the browser navigation timeout and the repo smoke helper still used retired chat endpoints](../docs/rca/2026-03-28-moltis-browser-timeout-budget-equalled-navigation-timeout.md)
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

#### P2 (25 lessons)
- [Worktree cleanup helper treated derived branch-only path as a path/branch conflict](../docs/rca/2026-04-15-worktree-cleanup-helper-treated-derived-branch-path-as-conflict.md)
- [Worktree cleanup helper blocked merged behind-only branch on stale upstream unpushed-guard](../docs/rca/2026-04-15-worktree-cleanup-helper-blocked-merged-behind-only-branch-on-stale-upstream-guard.md)
- [Telegram skill-detail remained non-terminal and repo skills lacked a shared Telegram-safe summary contract](../docs/rca/2026-04-05-telegram-skill-detail-general-hardening.md)
- [Tracked deploy empty stdout broke GitHub Actions JSON contract](../docs/rca/2026-04-02-tracked-deploy-empty-stdout-broke-json-contract.md)
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

#### P3 (15 lessons)
- [Telegram skill-detail regressed after removing direct fastpath and relying on a single in-band hook path](../docs/rca/2026-04-02-telegram-skill-detail-single-inband-path-regressed-live-runtime.md)
- [Telegram skill-detail requests regressed through dual delivery paths, container drift, rewrite gaps, and skill-internal wording leaks](../docs/rca/2026-04-02-telegram-skill-detail-fell-back-to-tool-error-leak.md)
- [Telegram learner skill-detail still leaked tool failures because the summary builder kept a shell-unsafe Perl branch and the skill contract was too operator-heavy](../docs/rca/2026-04-02-telegram-learner-skill-detail-hardening.md)
- [Telegram direct fastpath tail was not terminal and live outbound hooks were incomplete](../docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md)
- [Telegram direct fastpath suppression needed chat scope because live runtime drifted session identity](../docs/rca/2026-04-02-telegram-direct-fastpath-suppression-needed-chat-scope.md)
- [Telegram repeated BeforeLLMCall iteration was misclassified as a new user turn after direct fastpath](../docs/rca/2026-04-02-telegram-direct-fastpath-repeat-before-llm-iteration-was-misclassified-as-new-turn.md)
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


#### cicd (29 lessons)
- [Deploy host automation missing cron package bootstrap](../docs/rca/2026-04-14-deploy-host-automation-missing-cron-package-bootstrap.md)
- [Tracked deploy empty stdout broke GitHub Actions JSON contract](../docs/rca/2026-04-02-tracked-deploy-empty-stdout-broke-json-contract.md)
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

#### configuration (1 lessons)
- [Moltis Telegram user bots needed explicit stream_mode off](../docs/rca/2026-03-28-moltis-telegram-user-bots-needed-explicit-stream-mode-off.md)

#### generic (11 lessons)
- [Telegram skill-detail regressed after removing direct fastpath and relying on a single in-band hook path](../docs/rca/2026-04-02-telegram-skill-detail-single-inband-path-regressed-live-runtime.md)
- [Telegram skill-detail requests regressed through dual delivery paths, container drift, rewrite gaps, and skill-internal wording leaks](../docs/rca/2026-04-02-telegram-skill-detail-fell-back-to-tool-error-leak.md)
- [Telegram learner skill-detail still leaked tool failures because the summary builder kept a shell-unsafe Perl branch and the skill contract was too operator-heavy](../docs/rca/2026-04-02-telegram-learner-skill-detail-hardening.md)
- [Telegram direct fastpath tail was not terminal and live outbound hooks were incomplete](../docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md)
- [Telegram direct fastpath suppression needed chat scope because live runtime drifted session identity](../docs/rca/2026-04-02-telegram-direct-fastpath-suppression-needed-chat-scope.md)
- [Telegram repeated BeforeLLMCall iteration was misclassified as a new user turn after direct fastpath](../docs/rca/2026-04-02-telegram-direct-fastpath-repeat-before-llm-iteration-was-misclassified-as-new-turn.md)
- [2026-03-06-browser-compat-speckit-desync](../docs/rca/2026-03-06-browser-compat-speckit-desync.md)
- [2026-03-03-sample-enhanced-rca](../docs/rca/2026-03-03-sample-enhanced-rca.md)
- [2026-03-03-rca-skill-creation](../docs/rca/2026-03-03-rca-skill-creation.md)
- [2026-03-03-rca-comprehensive-test](../docs/rca/2026-03-03-rca-comprehensive-test.md)
- [2026-03-03-git-branch-confusion](../docs/rca/2026-03-03-git-branch-confusion.md)

#### process (26 lessons)
- [Worktree governance helpers trusted contextual Beads state instead of canonical ownership/runtime evidence](../docs/rca/2026-04-15-worktree-governance-helpers-trusted-contextual-beads-state.md)
- [Telegram chat probe skill pointed to a missing wrapper entrypoint](../docs/rca/2026-04-14-telegram-chat-probe-skill-pointed-to-missing-wrapper-entrypoint.md)
- [Skill execution drifted into workaround behavior and task reports lacked a shared simple contract](../docs/rca/2026-04-09-skill-execution-and-reporting-contract-drift.md)
- [Telegram skill-detail remained non-terminal and repo skills lacked a shared Telegram-safe summary contract](../docs/rca/2026-04-05-telegram-skill-detail-general-hardening.md)
- [Runtime-only Beads repair still pointed at raw bootstrap after the CLI contract drifted](../docs/rca/2026-03-29-runtime-only-repair-contract-still-pointed-at-raw-bootstrap.md)
- [Managed worktree creation mixed up the create executor and hook bootstrap-source contract](../docs/rca/2026-03-28-worktree-create-helper-and-hook-bootstrap-source-drift.md)
- [Moltis operator browser session isolation and Telegram send attribution drift](../docs/rca/2026-03-28-moltis-operator-browser-session-isolation-and-telegram-send-attribution-drift.md)
- [Moltis browser runs still timed out because the overall agent timeout matched the browser navigation timeout and the repo smoke helper still used retired chat endpoints](../docs/rca/2026-03-28-moltis-browser-timeout-budget-equalled-navigation-timeout.md)
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

#### product (4 lessons)
- [Telegram codex-update live runtime ignored in-band hook modify despite correct guard output](../docs/rca/2026-04-14-telegram-codex-update-live-runtime-ignored-inband-modify.md)
- [Telegram codex-update hard override did not terminalize blocked tool follow-up](../docs/rca/2026-04-14-telegram-codex-update-hard-override-did-not-terminalize-blocked-tool-followup.md)
- [Telegram codex-update direct fastpath raced underlying run](../docs/rca/2026-04-14-telegram-codex-update-direct-fastpath-raced-underlying-run.md)
- [Telegram codex-update classifier missed live BeforeLLMCall turns when messages content arrived as arrays](../docs/rca/2026-04-14-telegram-codex-update-array-content-bypassed-turn-classifier.md)

#### security (1 lessons)
- [Unauthorized File Deletion Attempt](../docs/rca/2026-03-04-unauthorized-file-deletion-attempt.md)

#### shell (6 lessons)
- [Beads wrapper delegated into a sibling worktree wrapper and left stale JSONL export](../docs/rca/2026-03-20-beads-wrapper-path-pollution-caused-stale-jsonl-export.md)
- [GitOps repair workflow failed before execution because inline heredoc was not parse-safe in GitHub Actions](../docs/rca/2026-03-13-gitops-repair-heredoc-parse-failure.md)
- [Topology refresh misclassified permission boundary as a held lock](../docs/rca/2026-03-09-topology-lock-permission-boundary.md)
- [Command-worktree follow-up UAT exposed preview, sync, and lock edge-case gaps](../docs/rca/2026-03-09-command-worktree-followup-uat.md)
- [Child worktree reconciliation renames authoritative feature worktree](../docs/rca/2026-03-08-topology-child-worktree-identity-drift.md)
- [Команда false завершилась с кодом 1](../docs/rca/2026-03-07-false-command-exit-code.md)

#### tooling (2 lessons)
- [Worktree cleanup helper treated derived branch-only path as a path/branch conflict](../docs/rca/2026-04-15-worktree-cleanup-helper-treated-derived-branch-path-as-conflict.md)
- [Worktree cleanup helper blocked merged behind-only branch on stale upstream unpushed-guard](../docs/rca/2026-04-15-worktree-cleanup-helper-blocked-merged-behind-only-branch-on-stale-upstream-guard.md)


### Popular Tags

- `rca` (28 lessons)
- `moltis` (26 lessons)
- `telegram` (20 lessons)
- `deploy` (19 lessons)
- `github-actions` (17 lessons)
- `gitops` (16 lessons)
- `cicd` (16 lessons)
- `skills` (11 lessons)
- `beads` (10 lessons)
- `process` (9 lessons)


---

## Statistics

| Metric | Value |
|--------|-------|
| Total Lessons | 80 |
| Critical (P0/P1) | 39 |
| Categories | 8 |
| Unique Tags | 161 |

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
