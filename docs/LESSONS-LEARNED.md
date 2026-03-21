# Lessons Learned (Auto-generated)

**Generated**: 2026-03-21
**Total Lessons**: 25

---

## Quick Reference Card


### By Severity


#### P0 (1 lessons)
- [Unauthorized File Deletion Attempt](../docs/rca/2026-03-04-unauthorized-file-deletion-attempt.md)

#### P1 (5 lessons)
- [ASC demo: расхождение локального и удалённого frontend bundle](../docs/rca/2026-03-21-asc-demo-remote-bundle-drift.md)
- [Handoff lock key TypeError переводил confirmed brief в ложный handoff_running и срывал download-ready](../docs/rca/2026-03-20-handoff-lock-key-typeerror-download-stall.md)
- [Повторное подтверждение brief скрывалось из ленты после второй правки](../docs/rca/2026-03-20-brief-correction-dedup-drop.md)
- [Topology refresh misclassified permission boundary as a held lock](../docs/rca/2026-03-09-topology-lock-permission-boundary.md)
- [Self-inflicted GitOps drift from deployment audit markers](../docs/rca/2026-03-08-gitops-audit-markers-self-drift.md)

#### P2 (9 lessons)
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
- [2026-03-21-beads-post-migration-jsonl-misread](../docs/rca/2026-03-21-beads-post-migration-jsonl-misread.md)
- [2026-03-18-playwright-session-instability-and-fallback](../docs/rca/2026-03-18-playwright-session-instability-and-fallback.md)
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


#### cicd (3 lessons)
- [Self-inflicted GitOps drift from deployment audit markers](../docs/rca/2026-03-08-gitops-audit-markers-self-drift.md)
- [Ложные error-сигналы в успешных GitHub workflow](../docs/rca/2026-03-07-workflow-alert-severity-mismatch.md)
- [Повторяющиеся падения GitHub Actions workflow (Drift + Deploy)](../docs/rca/2026-03-07-github-workflows-recurring-failures.md)

#### generic (7 lessons)
- [2026-03-21-beads-post-migration-jsonl-misread](../docs/rca/2026-03-21-beads-post-migration-jsonl-misread.md)
- [2026-03-18-playwright-session-instability-and-fallback](../docs/rca/2026-03-18-playwright-session-instability-and-fallback.md)
- [2026-03-06-browser-compat-speckit-desync](../docs/rca/2026-03-06-browser-compat-speckit-desync.md)
- [2026-03-03-sample-enhanced-rca](../docs/rca/2026-03-03-sample-enhanced-rca.md)
- [2026-03-03-rca-skill-creation](../docs/rca/2026-03-03-rca-skill-creation.md)
- [2026-03-03-rca-comprehensive-test](../docs/rca/2026-03-03-rca-comprehensive-test.md)
- [2026-03-03-git-branch-confusion](../docs/rca/2026-03-03-git-branch-confusion.md)

#### process (10 lessons)
- [ASC demo: расхождение локального и удалённого frontend bundle](../docs/rca/2026-03-21-asc-demo-remote-bundle-drift.md)
- [Handoff lock key TypeError переводил confirmed brief в ложный handoff_running и срывал download-ready](../docs/rca/2026-03-20-handoff-lock-key-typeerror-download-stall.md)
- [Повторное подтверждение brief скрывалось из ленты после второй правки](../docs/rca/2026-03-20-brief-correction-dedup-drop.md)
- [Hosted Clawdiy Control UI был развернут с password auth вместо token auth](../docs/rca/2026-03-12-clawdiy-hosted-control-ui-password-auth-mismatch.md)
- [UAT registry snapshots were treated as disposable during UAT maintenance](../docs/rca/2026-03-09-uat-registry-snapshot-loss.md)
- [Диагностика remote rollout началась без повторного применения Traefik-first уроков](../docs/rca/2026-03-09-remote-rollout-diagnosis-skipped-traefik-lessons.md)
- [Локальный runtime был поднят вместо работы с удалённым сервисом](../docs/rca/2026-03-08-remote-target-boundary-before-local-runtime.md)
- [False GitHub Auth Failure During Codex Push](../docs/rca/2026-03-08-codex-github-auth-false-failure.md)
- [Повторный запрос уже документированных секретов](../docs/rca/2026-03-07-context-discovery-before-user-questions.md)
- [Token Bloat в инструкциях — повторяющаяся проблема](../docs/rca/2026-03-04-token-bloat-recurring.md)

#### security (1 lessons)
- [Unauthorized File Deletion Attempt](../docs/rca/2026-03-04-unauthorized-file-deletion-attempt.md)

#### shell (4 lessons)
- [Topology refresh misclassified permission boundary as a held lock](../docs/rca/2026-03-09-topology-lock-permission-boundary.md)
- [Command-worktree follow-up UAT exposed preview, sync, and lock edge-case gaps](../docs/rca/2026-03-09-command-worktree-followup-uat.md)
- [Child worktree reconciliation renames authoritative feature worktree](../docs/rca/2026-03-08-topology-child-worktree-identity-drift.md)
- [Команда false завершилась с кодом 1](../docs/rca/2026-03-07-false-command-exit-code.md)


### Popular Tags

- `process` (6 lessons)
- `ux` (5 lessons)
- `rca` (5 lessons)
- `topology-registry` (4 lessons)
- `git-worktree` (4 lessons)
- `gitops` (3 lessons)
- `github-actions` (3 lessons)
- `drift-detection` (3 lessons)
- `deploy` (3 lessons)
- `web-demo` (2 lessons)


---

## Statistics

| Metric | Value |
|--------|-------|
| Total Lessons | 25 |
| Critical (P0/P1) | 6 |
| Categories | 5 |
| Unique Tags | 60 |

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
