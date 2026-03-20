---
title: "Tracked Moltis deploy cancelled by manual GitOps confirmation guard during CI workflow"
date: 2026-03-20
severity: P1
category: cicd
tags: [cicd, deploy, gitops, guardrails, moltis, production]
root_cause: "Remote tracked deploy wrapper did not propagate CI context to deploy.sh, so manual-confirmation guard aborted rollout inside GitHub Actions"
---

# RCA: Tracked Moltis deploy cancelled by manual GitOps confirmation guard during CI workflow

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** production deploy pipeline завершался `failure`, несмотря на успешные preflight/GitOps/backup шаги; финальный rollout до Moltis control-plane прерывался до старта контейнерного обновления.

## Ошибка

Падение в run `23357425657` (workflow `Deploy Moltis`, job `Deploy to Production`, step `Run tracked Moltis deploy control plane`):

- лог показывал `GitOps Compliance Warning` как для ручного запуска;
- затем `Operation cancelled`;
- job завершался `##[error]Tracked deploy control plane failed`.

## Анализ 5 Почему

| Уровень | Почему | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему deploy pipeline падал на финальном шаге? | `deploy.sh` возвращал non-zero в tracked control-plane | run `23357425657`, failed step `Run tracked Moltis deploy control plane` |
| 2 | Почему `deploy.sh` возвращал non-zero? | Срабатывал `gitops_confirm_manual` и отменял выполнение | лог: `GitOps Compliance Warning` + `Operation cancelled` |
| 3 | Почему guard считал запуск ручным, хотя запуск был из GitHub Actions? | На удалённом хосте внутри `run-tracked-moltis-deploy.sh` не было CI-маркеров (`GITHUB_ACTIONS`, `GITHUB_RUN_ID`) | `scripts/gitops-guards.sh` -> `gitops_is_ci`, remote call path |
| 4 | Почему CI-маркеры отсутствовали на remote hop? | Wrapper вызывал `deploy.sh --json moltis deploy` без проброса окружения для CI guard контракта | `scripts/run-tracked-moltis-deploy.sh` до фикса |
| 5 | Почему дефект попал в main? | Не было статического контракта, проверяющего что tracked remote entrypoint запускает `deploy.sh` в non-interactive CI mode | отсутствие соответствующего static test до фикса |

## Корневая причина

В shared remote entrypoint (`run-tracked-moltis-deploy.sh`) не был явно зафиксирован CI/non-interactive execution contract при вызове `deploy.sh`.  
Из-за этого GitOps manual-confirmation guard работал как в интерактивной сессии и отменял rollout в рамках CI/CD.

## Принятые меры

1. В `scripts/run-tracked-moltis-deploy.sh` добавлен явный проброс CI-контекста и non-interactive флага при вызове `deploy.sh`:
   - `GITHUB_ACTIONS=${GITHUB_ACTIONS:-true}`
   - `GITHUB_RUN_ID=${GITHUB_RUN_ID:-$WORKFLOW_RUN}`
   - `GITHUB_RUN_ATTEMPT=${GITHUB_RUN_ATTEMPT:-1}`
   - `GITOPS_CONFIRM_SKIP=true`
2. Добавлен static guard `static_tracked_deploy_propagates_ci_context_for_noninteractive_guarded_deploy` в `tests/static/test_config_validation.sh`.

## Проверка после исправлений

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash tests/static/test_config_validation.sh` | pass | 83/83 |
| Новый static guard для remote tracked deploy | pass | `static_tracked_deploy_propagates_ci_context_for_noninteractive_guarded_deploy` |

## Уроки

1. Любой SSH-hop из CI в remote script обязан явно восстанавливать execution context (CI/non-interactive), а не полагаться на implicit env inheritance.
2. Guardrails должны иметь тест-контракт на boundary "workflow -> SSH wrapper -> remote script", иначе production-breakage проявляется только в live deploy run.
