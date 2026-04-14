---
title: "Telegram codex-update direct fastpath raced underlying run"
date: 2026-04-14
severity: P1
category: product
tags: [telegram, codex-update, fastpath, hook, cron, uat, rca]
root_cause: "The Telegram-safe `codex-update` path used an out-of-band direct-send fastpath that did not actually terminate the underlying LLM run, so a later `cron` tool failure produced a second bad reply; the authoritative Telegram Web probe also allowed an early clean reply to settle before observing that delayed second reply."
---

# RCA: Telegram codex-update direct fastpath raced underlying run

Date: 2026-04-14  
Status: Resolved in source, pending deploy/live re-verification  
Context: beads `moltinger-15te`, live Moltis Telegram regression on `@moltinger_bot`

## Error

Пользователь получил в live Telegram такой ответ вместо канонического scheduler-safe контракта:

```text
Проверил — и да, тут инструмент расписания реально сломан: на list он снова ответил missing 'action' parameter.
...
📋 Activity log
• 🔧 cron
•   ❌ missing 'action' parameter
```

При этом ранний post-deploy smoke уже был ошибочно интерпретирован как `passed`, хотя bad reply реально существовал в том же production chat.

## Lessons Pre-check

Перед фиксом были проверены lessons и связанные правила:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag cron`
- `./scripts/query-lessons.sh --tag codex-update`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Релевантные прошлые уроки:

1. `2026-03-20-telegram-uat-false-pass-on-model-not-found.md`  
   transport/ранний зелёный helper verdict не доказывает корректный пользовательский ответ.
2. `2026-03-28-telegram-codex-update-sandbox-skill-path-mismatch-and-activity-log-transport-leak.md`  
   `codex-update` на Telegram-safe surface должен отвечать deterministic contract-ом, а не уходить в tool/memory speculation.
3. `2026-04-05-telegram-skill-detail-general-hardening.md`  
   prompt family drift и stale chat contamination нужно ловить по authoritative evidence, а не по “похожему” старому прогону.

Что эти уроки уже покрывали:

- Telegram-safe ответы нельзя считать зелёными только по раннему helper success.
- `codex-update` routes требуют deterministic rewrite, а не best-effort tool behavior.

Что оставалось непокрытым:

- out-of-band direct fastpath для `codex-update` не считался dangerous, хотя он не останавливал underlying run;
- authoritative Telegram Web probe не держал дополнительное окно наблюдения после раннего clean reply.

## Evidence

Production evidence с `root@ainetic.tech`:

- `scripts/telegram-e2e-on-demand.sh --mode authoritative` вернул `pre_send_invalid_activity` и показал уже существующий bad incoming reply в чате.
- `docker logs moltis` зафиксировал живой run:
  - `2026-04-14T11:39:07Z` tool call `cron` с `{"action":"list",...}`
  - затем `tool execution failed ... missing 'action' parameter`
  - затем финальный user-facing bad reply.
- `/tmp/moltis-telegram-safe-llm-guard.audit.log` зафиксировал, что hook раньше в том же run уже сделал:
  - `direct_fastpath kind=codex_update`
  - затем `direct_fastpath_after_llm_suppress`
  - затем `direct_fastpath_tool_suppress`

Это доказало, что ранний direct send произошёл, но сам run не остановился и позже сгенерировал второй плохой ответ.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Почему пользователь увидел bad reply с `cron`/`missing 'action' parameter`? | Потому что underlying LLM run всё же вызвал `cron` tool и поздно вернул ошибочный текст в чат. |
| 2 | Почему underlying run вообще продолжил жить после Telegram-safe ответа? | Потому что `codex-update` использовал `BeforeLLMCall` direct fastpath, который делал `sendMessage`, но не заменял prompt на hard override и не завершал сам run. |
| 3 | Почему это не было остановлено последующими suppress hooks? | Потому что suppression оказался best-effort post-factum механизмом; live runtime всё равно довёл run до позднего финального ответа. |
| 4 | Почему post-deploy smoke был интерпретирован как зелёный? | Потому что authoritative Telegram Web probe успел стабилизировать ранний clean reply до прихода позднего bad second reply. |
| 5 | Почему такая гонка вообще была возможна как системный контракт? | Потому что мы считали out-of-band fastpath “эквивалентом short-circuit”, не зафиксировав инварианту: user-facing deterministic reply допустим только если он останавливает модель до tool execution, а не параллельно ей. |

## Root Cause

`codex-update` в Telegram-safe lane использовал out-of-band `direct_fastpath_send_with_suppression()` на `BeforeLLMCall`.  
Этот path отправлял ранний канонический ответ, но не превращал ход в настоящий hard override до модели. В результате реальный LLM run продолжал выполняться, вызывал `cron` tool, получал ошибку `missing 'action' parameter` и позже отправлял второй bad reply.

Параллельно authoritative Telegram Web probe возвращал verdict слишком рано после первого clean reply и не держал дополнительное observation window, достаточное чтобы заметить поздний второй ответ.

## Fixes Applied

1. `scripts/telegram-safe-llm-guard.sh`
   - `codex-update` исключён из `BeforeLLMCall` direct fastpath.
   - Теперь этот route всегда идёт через deterministic hard override до модели.
2. `tests/component/test_telegram_safe_llm_guard.sh`
   - regression теперь требует, чтобы даже при `MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true` `codex-update` шёл через `modify`, а не через direct send.
3. `scripts/telegram-web-user-probe.mjs`
   - добавлено `minReplyObservationMs` окно наблюдения после первого reply;
   - authoritative probe теперь не считается settled только из-за раннего clean-looking ответа.
4. `tests/component/test_telegram_web_probe_correlation.sh`
   - добавлена regression на delayed second reply, который должен победить ранний clean reply.

## Prevention

1. Out-of-band direct send нельзя считать safe short-circuit для высокорисковых user-facing маршрутов, если underlying run продолжает жить.
2. Для deterministic Telegram-safe routes canonical path должен быть `BeforeLLMCall hard override`, а не “отправили напрямую и надеемся, что suppression всё дочистит”.
3. Authoritative Telegram UAT должен держать observation window после первого reply, если продукт допускает delayed second replies.

## Уроки

1. Ранний “хороший” reply не доказывает успех, если у runtime ещё есть шанс прислать второй ответ в том же turn.
2. `direct fastpath` и `true short-circuit` — это разные вещи; для Telegram-safe маршрутов их нельзя смешивать.
3. Если production evidence противоречит старому smoke, источником истины становится live audit/correlation evidence, а не прежний зелёный verdict.
