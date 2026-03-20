---
title: "Tracked Moltis deploy failed on legacy prometheus container-name conflict and opaque non-JSON failure envelope"
date: 2026-03-20
severity: P1
category: cicd
tags: [cicd, deploy, docker-compose, gitops, moltis, production]
root_cause: "Remote host kept legacy container /prometheus from a different compose project, while tracked deploy expected to create managed /prometheus; deploy.sh exited before JSON result, masking the real conflict"
---

# RCA: Tracked Moltis deploy failed on legacy prometheus container-name conflict and opaque non-JSON failure envelope

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** production deploy run `23358681257` завершился `failure`; rollout прервался на control-plane этапе до финальной verification.

## Ошибка

Падение в run `23358681257` (workflow `Deploy Moltis`, step `Run tracked Moltis deploy control plane`):

- Docker вернул конфликт имени контейнера:
  - `Error response from daemon: Conflict. The container name "/prometheus" is already in use ...`
- После этого tracked wrapper вернул fallback-ошибку:
  - `run-tracked-moltis-deploy.sh received non-JSON output from deploy.sh`

## Анализ 5 Почему

| Уровень | Почему | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему deploy завершился `failure`? | `deploy.sh --json moltis deploy` завершился ошибкой при `docker compose up` | run `23358681257`, failed step log |
| 2 | Почему `docker compose up` упал? | На хосте уже существовал контейнер `/prometheus` | лог ошибки Docker conflict |
| 3 | Почему существующий `/prometheus` конфликтовал с tracked stack? | Контейнер имел другой compose project label (`ainetic`), а текущий deploy работает с `COMPOSE_PROJECT_NAME=moltinger` и тем же `container_name` | `docker inspect prometheus`: project=`ainetic` |
| 4 | Почему legacy контейнер не был устранён до rollout? | В `deploy.sh` не было шага нормализации/очистки container-name конфликтов перед `compose up` | код `scripts/deploy.sh` до фикса |
| 5 | Почему первичная причина была замаскирована generic-ошибкой? | Wrapper ожидал валидный JSON от `deploy.sh`, но при раннем `set -e` exit JSON не формировался | `scripts/run-tracked-moltis-deploy.sh` до фикса |

## Корневая причина

Два связанных дефекта:

1. На сервере остался legacy контейнер `/prometheus` из другого compose project (`ainetic`), который конфликтовал с managed rollout по фиксированному `container_name`.
2. При раннем падении `deploy.sh` JSON-контракт не соблюдался, и wrapper выдавал непрозрачную ошибку non-JSON вместо явной причины.

## Принятые меры

1. В `scripts/deploy.sh` добавлен guard `resolve_container_name_conflicts`:
   - проверяет managed container names для target;
   - находит контейнеры с тем же именем, но с project label, отличным от ожидаемого `COMPOSE_PROJECT_NAME`;
   - принудительно удаляет конфликтный legacy контейнер до `compose up`.
2. В `scripts/run-tracked-moltis-deploy.sh` добавлена явная проверка JSON-контракта:
   - если `deploy.sh` завершился без валидного JSON, возвращается точный failure message с exit code.
3. Добавлены статические регрессионные проверки:
   - `static_deploy_script_cleans_legacy_container_name_conflicts_before_rollout`
   - `static_tracked_deploy_detects_missing_json_contract_from_deploy_sh`

## Проверка после исправлений

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash tests/static/test_config_validation.sh` | pass | 89/89 |
| Guard очистки legacy conflict | pass | static test `static_deploy_script_cleans_legacy_container_name_conflicts_before_rollout` |
| Guard JSON envelope | pass | static test `static_tracked_deploy_detects_missing_json_contract_from_deploy_sh` |

## Уроки

1. Для production-хоста с долгой историей деплоев нельзя предполагать отсутствие legacy контейнеров с фиксированными именами; перед rollout нужна явная нормализация managed surface.
2. Для CI orchestration JSON-контракт должен быть fail-closed: даже при ранних авариях ошибка обязана быть диагностичной и привязанной к root cause, а не к generic parse failure.
