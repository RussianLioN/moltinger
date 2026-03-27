---
title: "Tracked Moltis deploy failed when docker compose force-recreate hit a slow-stop container race"
date: 2026-03-27
severity: P1
category: cicd
tags: [cicd, deploy, docker-compose, moltis, production, docker, rollout]
root_cause: "Tracked deploy relied on docker compose force-recreate against a fixed-name Moltis container without an explicit stop grace or pre-stop/remove step; Moltis exceeded Docker's default 10s stop timeout, was SIGKILLed, and compose then failed against the disappearing old container"
---

# RCA: Tracked Moltis deploy failed when docker compose force-recreate hit a slow-stop container race

**Дата:** 2026-03-27  
**Статус:** Resolved  
**Влияние:** production run `23666558828` завершился `failure`; после неудачного recreate контейнер `moltis` временно отсутствовал и потребовалось ручное восстановление сервиса.

## Ошибка

Падение произошло в workflow `Deploy Moltis`, job `Deploy to Production`, step `Run tracked Moltis deploy control plane`.

Ключевые строки:

- GitHub Actions log:
  - `Container watchtower Recreate`
  - `Container moltis Recreate`
  - `Container ollama-fallback Recreate`
  - `Container watchtower Recreated`
  - `Container ollama-fallback Recreated`
  - `Container moltis Error response from daemon: No such container: 0b531284aa96_moltis`
- Docker daemon log around `2026-03-27T20:45:46Z`:
  - `Container failed to exit within 10s of signal 15 - using the force`
  - followed by task delete for the old `moltis` container id `0b531284...`

После этого `docker inspect moltis` на сервере возвращал `No such object: moltis`, пока сервис не был поднят вручную.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему production deploy завершился `failure`? | `docker compose up -d --remove-orphans --force-recreate` упал на сервисе `moltis` | run `23666558828`, failed step log |
| 2 | Почему `docker compose` упал на `moltis`? | Compose пытался recreate old container, который уже исчез во время force-stop path | `No such container: 0b531284aa96_moltis` |
| 3 | Почему old container исчез во время recreate? | Docker не дождался завершения Moltis за дефолтные `10s`, отправил `SIGKILL`, после чего old container был удалён | `journalctl -u docker.service` at `20:45:46Z` |
| 4 | Почему deploy зависел от этого хрупкого recreate path? | `deploy.sh` целиком полагался на `docker compose up --force-recreate` для fixed-name Moltis container и не делал отдельный deterministic stop/remove | `scripts/deploy.sh` before fix |
| 5 | Почему это стало системной проблемой? | В compose файлах не был задан более длинный `stop_grace_period`, хотя Docker Compose по умолчанию ждёт только `10s` до `SIGKILL` | official Docker docs for `stop_grace_period`; `docker inspect moltis` showed no explicit stop timeout |

## Корневая причина

Rollback/skill-discovery логика здесь была не при чём. Корень сбоя был в rollout contract:

1. `deploy.sh` использовал `docker compose up --force-recreate` прямо по fixed-name `moltis` container.
2. Moltis не завершился за Docker default `10s`.
3. Docker принудительно убил old container.
4. Compose споткнулся об уже исчезнувший old container и оборвал deploy.

Итог: upgrade logic уже была корректной, но сам control-plane не переживал slow-stop lifecycle у Moltis.

## Принятые меры

1. В `scripts/deploy.sh` добавлен `prepare_moltis_container_for_rollout`:
   - детерминированно останавливает `moltis` с расширенным timeout;
   - затем удаляет existing fixed-name container до `compose up`;
   - только после этого запускает rollout.
2. В `docker-compose.prod.yml` и `docker-compose.yml` для `moltis` задан `stop_grace_period: 45s`.
3. Добавлены регрессионные guard-тесты:
   - `tests/unit/test_deploy_workflow_guards.sh`
   - `tests/static/test_config_validation.sh`
4. Обновлены ручные runbook/troubleshooting docs, чтобы не советовать хрупкий raw `up --force-recreate` без pre-stop/remove.

## Проверка после исправления

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash -n scripts/deploy.sh` | pass | local validation |
| `./tests/run.sh --lane static --filter 'config_validation|deploy_workflow_guards'` | pass | 111/111 |
| `./tests/run.sh --lane component --filter 'moltis_repo_skills_sync|moltis_runtime_attestation|moltis_codex_update'` | pass | 17/17 |
| Server health after manual recovery | pass | `moltis` healthy, `/health` => `200` |

## Уроки

1. Для fixed-name production containers `force-recreate` нельзя считать безопасным по умолчанию, если service может завершаться дольше Docker default timeout.
2. Если deploy требует recreate, сначала нужно стабилизировать stop contract: явный `stop_grace_period` и deterministic pre-stop/remove path.
3. Ошибка уровня Docker lifecycle должна документироваться отдельно от application-level rollback, иначе легко начать чинить не тот слой.
