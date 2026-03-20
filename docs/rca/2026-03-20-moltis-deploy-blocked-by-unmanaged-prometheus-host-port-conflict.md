---
title: "Moltis deploy blocked by unmanaged host-level Prometheus port conflict during full-stack compose up"
date: 2026-03-20
severity: P1
category: cicd
tags: [cicd, deploy, docker-compose, gitops, moltis, production, monitoring]
root_cause: "Moltis target deploy executed full-stack compose up (including monitoring services with host port 9090), while the server already had unmanaged system Prometheus bound to 9090; unrelated monitoring conflict blocked Moltis rollout"
---

# RCA: Moltis deploy blocked by unmanaged host-level Prometheus port conflict during full-stack compose up

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** production deploy run `23360516210` завершился `failure` в шаге `Run tracked Moltis deploy control plane`; Moltis upgrade pipeline снова прервался до post-deploy verification.

## Ошибка

Падение в run `23360516210` (workflow `Deploy Moltis`):

- `docker compose up` внутри tracked deploy завершился ошибкой:
  - `failed to bind host port for 0.0.0.0:9090 ... address already in use`
- До этого container-name conflict был уже устранён (`Removing legacy/conflicting container 'prometheus' ...`), но новый конфликт возник именно на host port binding.

Дополнительная проверка на сервере:

- `ss -ltnp '( sport = :9090 )'` показал:
  - `users:(("prometheus",pid=433564,...))`

Это подтвердило, что порт `9090` занят не managed docker-контейнером Moltis stack, а внешним system-level процессом.

## Анализ 5 Почему

| Уровень | Почему | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему deploy упал? | Шаг tracked deploy получил `exit 1` от `deploy.sh` во время `docker compose up` | run `23360516210`, failed step logs |
| 2 | Почему `docker compose up` завершился ошибкой? | Сервис `prometheus` не смог занять host port `9090` (`address already in use`) | stderr Docker в run logs |
| 3 | Почему порт `9090` был занят? | На сервере уже работал unmanaged системный `prometheus` процесс | `ss -ltnp` на `ainetic.tech` |
| 4 | Почему это блокировало именно Moltis update? | `moltis` target deploy поднимал весь compose stack, включая monitoring сервисы (`prometheus/alertmanager/cadvisor`) с host port bindings | `scripts/deploy.sh` до фикса: `compose_cmd normal up -d --remove-orphans` без service-scoping |
| 5 | Почему это архитектурно опасно? | Unrelated observability surface становился hard blocker для обновления Moltis core, хотя rollback/update контракт должен зависеть только от Moltis и его обязательных sidecar'ов | поведение pipeline до фикса |

## Корневая причина

Deploy контракт для `target=moltis` был избыточно широким: вместо service-scoped rollout запускался полный compose stack с monitoring сервисами и внешними портами. В окружении с внешним/унаследованным Prometheus это приводило к host-port конфликту (`9090`) и срывало Moltis rollout.

## Принятые меры

1. `scripts/deploy.sh` переведён на service-scoped deploy для `target=moltis`:
   - поднимаются только `moltis` + обязательные sidecar'ы (`watchtower`, `ollama`);
   - monitoring stack (`cadvisor/prometheus/alertmanager`) исключён из критического пути Moltis rollout.
2. Сужен scope legacy container conflict cleanup:
   - проверяются/очищаются только managed контейнеры Moltis target (`moltis`, `watchtower`, `ollama-fallback`);
   - больше не удаляются monitoring container names как часть Moltis deploy path.
3. Добавлен статический контрактный тест:
   - `static_deploy_script_scopes_moltis_rollout_to_core_and_sidecars`
4. Обновлён существующий тест очистки конфликтов:
   - закреплено, что cleanup не трогает monitoring names (`prometheus`) в Moltis target path.

## Проверка после исправлений

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash tests/static/test_config_validation.sh` | pass | 91/91 |
| Scope deploy path | pass | `static_deploy_script_scopes_moltis_rollout_to_core_and_sidecars` |
| Legacy conflict cleanup scope | pass | `static_deploy_script_cleans_legacy_container_name_conflicts_before_rollout` |

## Уроки

1. `target=moltis` не должен зависеть от успешного старта необязательных monitoring сервисов с host-level портами.
2. В CI/CD для production rollout нужно отделять critical runtime surface от auxiliary observability surface, чтобы исключить ложные hard blockers обновлений.
