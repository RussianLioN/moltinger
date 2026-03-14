# Lessons Learned (Auto-generated)

**Generated**: 2026-03-14
**Total Lessons**: 28

---

## Quick Reference Card


### By Severity


#### P0 (1 lessons)
- [Unauthorized File Deletion Attempt](../docs/rca/2026-03-04-unauthorized-file-deletion-attempt.md)

#### P1 (7 lessons)
- [Clawdiy lost gpt-5.4 as default model after redeploy because runtime wizard state was not captured in tracked config](../docs/rca/2026-03-14-clawdiy-runtime-model-state-was-not-in-gitops.md)
- [Clawdiy upgrade to official Docker latest regressed live health and required baseline rollback](../docs/rca/2026-03-14-clawdiy-latest-channel-regressed-live-health.md)
- [Moltis deploy rollback to 0.9.10 after non-official image pin and missing GitOps checkout repair](../docs/rca/2026-03-13-moltis-official-docker-channel-and-gitops-repair.md)
- [GitOps repair workflow failed before execution because inline heredoc was not parse-safe in GitHub Actions](../docs/rca/2026-03-13-gitops-repair-heredoc-parse-failure.md)
- [Официальный мастер настройки Clawdiy не мог завершить OAuth из-за неверного контракта домашнего каталога OpenClaw](../docs/rca/2026-03-13-clawdiy-official-wizard-runtime-home-contract-mismatch.md)
- [Topology refresh misclassified permission boundary as a held lock](../docs/rca/2026-03-09-topology-lock-permission-boundary.md)
- [Self-inflicted GitOps drift from deployment audit markers](../docs/rca/2026-03-08-gitops-audit-markers-self-drift.md)

#### P2 (12 lessons)
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

#### P3 (7 lessons)
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


#### cicd (6 lessons)
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

#### process (11 lessons)
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

#### shell (5 lessons)
- [GitOps repair workflow failed before execution because inline heredoc was not parse-safe in GitHub Actions](../docs/rca/2026-03-13-gitops-repair-heredoc-parse-failure.md)
- [Topology refresh misclassified permission boundary as a held lock](../docs/rca/2026-03-09-topology-lock-permission-boundary.md)
- [Command-worktree follow-up UAT exposed preview, sync, and lock edge-case gaps](../docs/rca/2026-03-09-command-worktree-followup-uat.md)
- [Child worktree reconciliation renames authoritative feature worktree](../docs/rca/2026-03-08-topology-child-worktree-identity-drift.md)
- [Команда false завершилась с кодом 1](../docs/rca/2026-03-07-false-command-exit-code.md)


### Popular Tags

- `process` (9 lessons)
- `lessons` (8 lessons)
- `clawdiy` (7 lessons)
- `gitops` (6 lessons)
- `rca` (5 lessons)
- `openclaw` (5 lessons)
- `github-actions` (5 lessons)
- `deploy` (5 lessons)
- `topology-registry` (4 lessons)
- `oauth` (4 lessons)


---

## Statistics

| Metric | Value |
|--------|-------|
| Total Lessons | 28 |
| Critical (P0/P1) | 8 |
| Categories | 5 |
| Unique Tags | 72 |

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
