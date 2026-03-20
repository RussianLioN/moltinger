---
title: "Telegram webhook monitor default expected webhook while production stayed in polling mode"
date: 2026-03-20
severity: P2
category: process
tags: [telegram, monitor, polling, webhook, contract-drift, gitops]
root_cause: "Cron defaults for webhook monitor enforced TELEGRAM_REQUIRE_WEBHOOK=true despite documented production transport mode polling, producing permanent false-fail monitor verdicts"
---

# RCA: Telegram webhook monitor default expected webhook while production stayed in polling mode

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** Периодический монитор webhook в production стабильно возвращал `fail` даже при рабочем сервисе, потому что проверял неподходящий transport-контракт.

## Ошибка

После deploy `main` (run `23352151759`) ручной запуск:

`/opt/moltinger-active/scripts/telegram-webhook-monitor.sh --json`

давал:

- `inbound_mode: polling`
- `failures: Telegram webhook is not configured; inbound_mode expected webhook`

При этом production-контракт у проекта для канала Telegram оставался `polling`.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему монитор давал `fail`? | Потому что требовал webhook-mode. | `/etc/cron.d/moltis-telegram-webhook-monitor`: `TELEGRAM_REQUIRE_WEBHOOK=true` до фикса. |
| 2 | Почему это было неверно для production? | Production transport фактически работал в polling-mode. | Runtime report: `inbound_mode=polling`; runbook `docs/telegram-e2e-on-demand.md` фиксирует polling как текущий transport. |
| 3 | Почему несоответствие не ловилось заранее? | Static-guard тест проверял только probe/noise параметры, но не `TELEGRAM_REQUIRE_WEBHOOK`. | `tests/static/test_config_validation.sh` до фикса. |
| 4 | Почему это важно? | Постоянный ложный `fail` снижает доверие к мониторингу и маскирует реальные инциденты. | Операторская диагностика после merge/deploy anti-noise ветки. |
| 5 | Почему drift закрепился? | Контракт monitor defaults не был явно привязан к текущему production transport mode. | Отсутствовал явный polling-friendly default в cron contract. |

## Корневая причина

Contract drift между cron default параметрами webhook-monitor и фактическим production transport mode (`polling`).

## Принятые меры

1. `scripts/cron.d/moltis-telegram-webhook-monitor`
   - `TELEGRAM_REQUIRE_WEBHOOK` изменён на `false` по умолчанию;
   - комментарий обновлён: webhook requirement включается только при осознанном cutover.
2. `tests/static/test_config_validation.sh`
   - static-guard теперь требует `TELEGRAM_REQUIRE_WEBHOOK=false` в webhook cron defaults.
3. `docs/QUICK-REFERENCE.md`
   - зафиксирован `polling-friendly` default для server-side monitor.

## Подтверждение устранения

- `bash tests/static/test_config_validation.sh` — pass (включая новый guard).
- Ручной запуск monitor на сервере в default-contract больше не должен падать из-за transport mismatch.

## Уроки

1. Health-monitor defaults должны быть синхронизированы с фактическим production transport mode.
2. Любой contract параметр monitor-кронов должен иметь static-guard в CI.
3. Переход `polling -> webhook` должен оформляться как явный rollout-step, а не скрытый дефолт.
