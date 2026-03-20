---
title: "Telegram monitor generated unsolicited user-facing traffic by default"
date: 2026-03-20
severity: P2
category: process
tags: [telegram, uat, monitor, cron, gitops, signal-noise]
root_cause: "Two periodic monitor lanes were effectively active-by-default in production, while webhook probe logic auto-selected a chat target from allowlist, turning health checks into unsolicited user-visible messages"
---

# RCA: Telegram monitor generated unsolicited user-facing traffic by default

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** Production получал регулярные служебные Telegram-сообщения от monitor-процедур, что засоряло пользовательский чат и ухудшало операторский сигнал.

## Ошибка

В контуре мониторинга одновременно действовали:

1. cron для `telegram-user-monitor` (MTProto) каждые 10 минут;
2. cron для `telegram-webhook-monitor` каждые 15 минут;
3. fallback в `telegram-webhook-monitor.sh`, который при пустом `TELEGRAM_TEST_USER` брал первый ID из `TELEGRAM_ALLOWED_USERS`.

Итог: даже без явного намерения оператора health-check мог отправлять реальные сообщения в пользовательский чат.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему появлялись лишние сообщения в Telegram? | Потому что мониторинг периодически отправлял probe-сообщения в production чат. | `/etc/cron.d/moltis-telegram-user-monitor`, `/etc/cron.d/moltis-telegram-webhook-monitor` на сервере; `scripts/telegram-webhook-monitor.sh` вызывал `sendMessage`. |
| 2 | Почему probe выбирал реального пользователя автоматически? | При пустом `TELEGRAM_TEST_USER` скрипт подставлял первый `TELEGRAM_ALLOWED_USERS`. | До фикса: `TELEGRAM_TEST_USER="${TELEGRAM_ALLOWED_USERS%%,*}"` в `scripts/telegram-webhook-monitor.sh`. |
| 3 | Почему это было включено постоянно, а не только для диагностики? | Cron-шаблон MTProto lane содержал активную строку по умолчанию, а webhook lane требовал test user. | `scripts/cron.d/moltis-telegram-user-monitor` и `scripts/cron.d/moltis-telegram-webhook-monitor` до фикса. |
| 4 | Почему это не ловилось как контрактная ошибка? | Не было статических guard-тестов на «opt-in only» мониторинг и запрет auto-fallback для test user. | `tests/static/test_config_validation.sh` не проверял эти условия до фикса. |
| 5 | Почему это важно для rollout-качества? | Шум в чате маскирует реальные UAT-сигналы и раздражает пользователя, что снижает доверие к post-deploy верификации. | Операторская обратная связь + runbook contract про manual on-demand UAT. |

## Корневая причина

Контракт между «health monitoring» и «user-facing Telegram traffic» не был fail-closed: активные по умолчанию cron-задачи и fallback выбора chat-id фактически превращали мониторинг в регулярные пользовательские уведомления.

## Принятые меры

1. `scripts/telegram-webhook-monitor.sh`
   - удалён fallback `TELEGRAM_ALLOWED_USERS -> TELEGRAM_TEST_USER`;
   - `TELEGRAM_REQUIRE_TEST_USER` переведён в default `false`;
   - добавлен `TELEGRAM_PROBE_DISABLE_NOTIFICATION` (default `true`);
   - добавлены поля `send_probe_attempted` и `probe_skipped_reason` в JSON отчёт.
2. `scripts/cron.d/moltis-telegram-webhook-monitor`
   - default `TELEGRAM_REQUIRE_TEST_USER=false`;
   - добавлен default `TELEGRAM_PROBE_DISABLE_NOTIFICATION=true`;
   - зафиксирован opt-in характер active probe.
3. `scripts/cron.d/moltis-telegram-user-monitor`
   - cron-строка закомментирована (disabled by default, opt-in only).
4. `tests/static/test_config_validation.sh`
   - добавлены guard-тесты на:
     - отсутствие auto-fallback по allowlist;
     - passive defaults для webhook cron;
     - disabled-by-default MTProto cron.
5. Документация
   - обновлены `docs/TELEGRAM-USER-MONITOR.md` и `docs/QUICK-REFERENCE.md` под contract «manual authoritative UAT + opt-in periodic monitors».

## Подтверждение устранения

- Локально:
  - `bash tests/static/test_config_validation.sh` — pass
  - `bash -n scripts/telegram-webhook-monitor.sh` — pass
- Контракт по коду:
  - webhook-monitor больше не выбирает chat-id из allowlist автоматически;
  - MTProto cron не запускается, пока оператор явно не раскомментирует строку.

## Уроки

1. Любой мониторинг, который может отправлять сообщения пользователю, должен быть `opt-in` по умолчанию.
2. Health-check и user-facing notifications должны быть разделены контрактно, а не только документированы.
3. Анти-шум правила должны быть зафиксированы static-guard тестами, иначе настройка быстро деградирует в соседних ветках.
