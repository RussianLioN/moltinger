---
title: "Clawdiy deploy treated transient OpenClaw startup unhealthy as a hard latest-upgrade failure"
date: 2026-03-14
severity: P1
category: cicd
tags: [clawdiy, openclaw, docker, latest, healthcheck, startup, telegram, rollback, lessons]
root_cause: "Clawdiy deploy logic assumed Docker health status `unhealthy` was terminal, even though the official OpenClaw Docker image can recover from a slow startup phase and begin serving `/health` shortly afterward"
---

# RCA: Clawdiy deploy treated transient OpenClaw startup unhealthy as a hard latest-upgrade failure

**Дата:** 2026-03-14  
**Статус:** Resolved  
**Влияние:** Высокое; production update до official Docker `latest` (`2026.3.12`) дважды откатывался на `2026.3.11`, хотя isolated canary доказал, что образ способен выйти в `healthy` после более долгого прогрева  
**Контекст:** `Deploy Clawdiy` run `23091734325`, official GitHub issues `#42019`, `#43381`

## Ошибка

После cleanup server checkout и честной повторной попытки обновления до official Docker `latest`, deploy workflow поднял новый контейнер `clawdiy`, дождался статуса `unhealthy` и немедленно запустил rollback. Позже isolated canary на том же official image показал, что:

- при отключенном Telegram контейнер `2026.3.12` начинает отдавать `200` примерно через 100 секунд;
- при живом Telegram-профиле тот же image сначала становится `unhealthy`, но затем начинает отдавать `200` на `/health` и `/`, а после следующего Docker probe сам восстанавливается в `healthy`.

Значит rollback срабатывал слишком рано: мы трактовали временный startup-warmup как окончательную несовместимость образа.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему update до official Docker `latest` откатывался? | Потому что deploy ждал `healthy`, увидел промежуточный `unhealthy` и сразу счел rollout проваленным | run `23091734325`, `scripts/deploy.sh::wait_for_healthy` |
| 2 | Почему статус `unhealthy` оказался промежуточным, а не финальным? | Потому что isolated canary на `ghcr.io/openclaw/openclaw:latest` доказал: контейнер позже начинает отдавать `200` на `/health` и восстанавливает Docker health | canary `clawdiy-canary-telegram`, health log и `curl http://127.0.0.1:28790/health` |
| 3 | Почему startup занимал дольше нашего health window? | Потому что OpenClaw с включенным Telegram-каналом имеет заметный cold-start/warmup; сам runtime логирует `startup-grace: 60s` и `channel-connect-grace: 120s` | logs `clawdiy-canary-telegram`, official issue `#42019` |
| 4 | Почему наш deploy-contract не выдержал такой прогрев? | Потому что compose healthcheck был настроен агрессивно (`start_period: 40s`, `retries: 3`), а `wait_for_healthy` завершал rollout при первом `unhealthy` вместо ожидания до общего timeout | `docker-compose.clawdiy.yml`, `scripts/deploy.sh` до фикса |
| 5 | Почему это системная ошибка, а не одноразовый случай? | Потому что мы предполагали, что Docker health для OpenClaw строго монотонный: `starting -> healthy` без восстановлений, хотя official issues уже описывают холодный старт с ложными probe/health fail signals | official issues `#42019`, `#43381` |

## Корневая причина

Clawdiy deploy-contract трактовал временный Docker `unhealthy` во время официального OpenClaw startup-warmup как терминальную ошибку rollout, хотя runtime способен восстановиться и начать корректно отвечать после более долгого прогрева.

## Доказательства

### Isolated canary без Telegram

- контейнер `clawdiy-canary`
- image: `ghcr.io/openclaw/openclaw:latest`
- started at: `2026-03-14T16:52:25Z`
- `/health` и `/` начали возвращать `200` около `2026-03-14T16:54:07Z`
- Docker health стал `healthy` без rollback

### Isolated canary с живым Telegram-профилем

- контейнер `clawdiy-canary-telegram`
- image: `ghcr.io/openclaw/openclaw:latest`
- started at: `2026-03-14T16:55:11Z`
- Docker health был `unhealthy`
- уже в `2026-03-14T16:59:14Z` `/health` и `/` отвечали `200`
- в `2026-03-14T16:59:24Z` Docker health автоматически восстановился до `healthy`
- logs показывают:
  - `health-monitor started (interval: 300s, startup-grace: 60s, channel-connect-grace: 120s)`
  - `telegram ... starting provider`
  - временные `getUpdates conflict` при параллельном canary

## Принятые меры

1. `docker-compose.clawdiy.yml`
   - увеличен startup health grace:
     - `retries: 5`
     - `start_period: 180s`
2. `scripts/deploy.sh`
   - для Clawdiy введен отдельный `CLAWDIY_HEALTH_CHECK_TIMEOUT` (`420s`)
   - `wait_for_healthy` больше не считает первый `unhealthy` окончательной ошибкой, если контейнер продолжает работать
   - если HTTP `/health` уже возвращает `200`, deploy считает rollout готовым, даже если Docker health еще не успел переключиться из `starting/unhealthy`
3. Добавлены статические проверки на новый warmup contract.

## Уроки

1. **OpenClaw Docker startup не обязан быть монотонным**; при каналах и холодном старте возможен путь `starting -> unhealthy -> healthy`.
2. **Для long-lived Clawdiy важнее общий rollout timeout и реальный `/health`, чем мгновенная реакция на первый `unhealthy`.**
3. **Health grace для OpenClaw должна учитывать channel warmup**, а не только “голый” startup без каналов.

## Связанные артефакты

- Rule: `docs/rules/clawdiy-upgrade-health-must-tolerate-openclaw-startup-warmup.md`
- Related RCA: `docs/rca/2026-03-14-clawdiy-latest-channel-regressed-live-health.md`

---

*Создано по протоколу RCA.*
