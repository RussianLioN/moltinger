---
title: "Deploy hardening follow-up introduced a latent verify failure-path regression and queue-blind watchdog alerts"
date: 2026-03-28
severity: P2
category: cicd
tags: [cicd, deploy, rollback, bash, set-e, watchdog, github-actions, notifications, moltis, tests]
root_cause: "The first hardening pass validated the happy path and static workflow structure, but it did not simulate bash set -e behavior inside verify_deployment() or GitHub Actions queue serialization semantics, so record_verification_failure() became fatal in the wrong place and the watchdog treated healthy queued runs as stalls"
---

# RCA: Deploy hardening follow-up introduced a latent verify failure-path regression and queue-blind watchdog alerts

**Дата:** 2026-03-28  
**Статус:** Resolved  
**Влияние:** latent production risk after the first hardening merge. The successful deploy run stayed green, but the code still contained a broken failure path: a real `verify_deployment()` mismatch could exit `deploy.sh` before auto-rollback and before the JSON contract. In parallel, the new watchdog could raise false alerts on healthy serialized deploy runs and notification channels were still coupled by default GitHub Actions step semantics.

## Ошибка

После merge первого hardening PR был выполнен дополнительный expert review. Он выявил три связанных дефекта:

1. `record_verification_failure()` возвращал `1` внутри `verify_deployment()` при `set -euo pipefail`, из-за чего shell мог аварийно завершить `deploy.sh` раньше `rollback()` и раньше `output_json_result()`.
2. `deploy-stall-watchdog.sh` считал stalled любой `queued`/`waiting`/`in_progress` run старше порога по `created_at`, не различая:
   - нормальную сериализацию через workflow `concurrency`;
   - реально зависший run;
   - long-running, но прогрессирующий run.
3. В `deploy-status-notify.yml` и `deploy-stall-watchdog.yml` email step шёл раньше Telegram step без `always()`/`continue-on-error`, поэтому падение email могло скрыть Telegram delivery.

Проблема была поймана до нового production incident, но уже после того, как changes попали в `main`, поэтому требовала немедленного follow-up.

## Что было доказано

1. Bash helper с `return 1` внутри `verify_deployment()` under `set -e` действительно ломал controlled failure path.
2. При таком поведении `scripts/run-tracked-moltis-deploy.sh` видел бы только generic envelope вида `deploy.sh exited with code ... before returning JSON`, а не `verify_failure_reason`.
3. Watchdog на `queued` run по одному только `created_at` действительно даёт false positive при штатной сериализации deploy через `concurrency`.
4. Watchdog, читающий только `repos/{repo}/actions/runs`, мог терять нужный `Deploy Moltis` run в шумном репозитории.
5. GitHub Actions по умолчанию использует implicit `success()` для шагов, поэтому второй notification channel может быть skipped после падения первого.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему latent bug остался после первого hardening PR? | Были покрыты happy path и статические контракты, но не был воспроизведён verify-failure under `set -e` | review finding + new unit test |
| 2 | Почему helper `record_verification_failure()` оказался опасным? | Он совмещал две роли: фиксацию причины и немедленный non-zero exit | `scripts/deploy.sh` до follow-up |
| 3 | Почему watchdog шумел на здоровые queued runs? | Stall detection была построена по `created_at` и статусу без учёта GitHub Actions concurrency serialization | `scripts/deploy-stall-watchdog.sh` до follow-up |
| 4 | Почему часть notification failures могла скрываться? | Email и Telegram steps использовали default `success()` chaining вместо изолированного канального выполнения | `deploy-status-notify.yml`, `deploy-stall-watchdog.yml` до follow-up |
| 5 | Почему это не было поймано раньше? | Не было unit tests на аварийный shell path и на queue/progress semantics watchdog | test gap before follow-up |

## Корневая причина

Корень проблемы был в неполной проверке hardening-изменений.

### Primary root cause

Failure-path hardening был реализован без исполнения controlled verify-failure scenario under real shell semantics (`set -euo pipefail`).

### Contributing root causes

- watchdog использовал упрощённую модель stall detection по `created_at`, а не по `updated_at`/queue semantics;
- notification workflows не были спроектированы как channel-isolated;
- timeout hardening не покрывал `test` job полностью.

## Принятые меры

1. `record_verification_failure()` переведён на safe contract:
   - записывает first failure reason;
   - логирует ошибку;
   - не убивает shell сам по себе.
2. `verify_deployment()` теперь:
   - продолжает собирать evidence после первой verify mismatch;
   - возвращает controlled `1` только в конце, если verification failure зафиксирован.
3. `verify_moltis_repo_skills_discovery()` теперь явно возвращает non-zero только на локально blocking шагах, а верхний verify path не теряет последующие contract checks.
4. `deploy-stall-watchdog.sh` переведён на workflow-specific GitHub API:
   - `repos/{repo}/actions/workflows/{workflow_file}/runs`
   - bounded pagination up to `MAX_RUNS`.
5. Stall detection ужесточена:
   - `in_progress` stalled only by `updated_at` idle time;
   - `queued`/`waiting` alert only when queue age exceeds threshold and there is no older active in-progress predecessor.
6. Notification workflows сделаны channel-isolated:
   - `if: always() && ...`
   - `continue-on-error: true`
   - финальная проверка падает только если все настроенные каналы не доставили сообщение.
7. `deploy.yml` получил missing job-level timeout для `test`.
8. Добавлены новые unit/static checks:
   - `tests/unit/test_deploy_verify_failure_contract.sh`
   - expanded `tests/unit/test_deploy_stall_watchdog.sh`
   - updated `tests/static/test_config_validation.sh`

## Проверка после исправления

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash -n scripts/deploy.sh` | pass | local |
| `bash -n scripts/deploy-stall-watchdog.sh` | pass | local |
| `bash tests/unit/test_deploy_verify_failure_contract.sh` | pass | 2/2 |
| `bash tests/unit/test_deploy_stall_watchdog.sh` | pass | 3/3 |
| `bash tests/unit/test_deploy_workflow_guards.sh` | pass | 28/28 |
| `bash tests/component/test_health_monitor_runtime_guards.sh` | pass | 4/4 |
| `bash tests/static/test_config_validation.sh` | pass | 115/115 |

## Уроки

1. Для Bash под `set -e` нельзя смешивать “record error” и “terminate control flow” в одном helper без explicit test на аварийный сценарий.
2. Для watchdog нельзя считать queue age stall-сигналом без модели сериализации и progress semantics.
3. Notification workflows должны быть отказоустойчивыми по каналам: email outage не должен блокировать Telegram и наоборот.
4. Happy-path proof не заменяет failure-path proof, особенно когда изменение касается rollback, verify или alerting logic.
