---
title: "Telegram codex-update classifier missed live BeforeLLMCall turns when messages content arrived as arrays"
date: 2026-04-14
severity: P1
category: product
tags: [telegram, codex-update, hooks, payload-shape, uat, rca]
root_cause: "The Telegram-safe guard extracted the latest user/system message only when `messages[].content` was a plain JSON string. In live Moltis Telegram runs, `BeforeLLMCall` can carry content as array/object parts (for example `[{\"type\":\"input_text\",\"text\":\"...\"}]`). That payload-shape drift made the codex-update scheduler turn invisible to the classifier, so the guard left the original prompt in place, only zeroed tool_count, and the model produced a clean but false memory-based answer. The authoritative UAT taxonomy also underfit this clean wording and let it pass."
---

# RCA: Telegram codex-update classifier missed live BeforeLLMCall turns when messages content arrived as arrays

Date: 2026-04-14  
Status: Fixed in source, pending merge/deploy/live re-verification  
Context: beads `moltinger-pggs`, residual live regression after merge of `#179`

## Ошибка

После green deploy и formal `passed` authoritative UAT пользователь всё ещё получал неверный live Telegram ответ:

```text
Да, есть.

По сохранённой памяти у меня зафиксировано, что настроена такая логика:
- ежедневно проверять стабильные обновления Codex CLI;
- присылать краткое уведомление только если вышла новая стабильная версия.
...
по сохранённому контексту наличие такого крона подтверждено.
```

Это был уже не старый dirty leak с `Activity log`, а clean false-positive variant: бот уверенно подтверждал live cron по "памяти".

## Проверка прошлых уроков

Перед новым fix cycle были заново проверены:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag codex-update`
- `docs/LESSONS-LEARNED.md`

Релевантные прошлые RCA:

1. `2026-04-14-telegram-codex-update-live-runtime-ignored-inband-modify.md`
2. `2026-04-14-telegram-codex-update-direct-fastpath-raced-underlying-run.md`
3. `2026-04-02-telegram-skill-detail-single-inband-path-regressed-live-runtime.md`

Что уже было известно:

- live Telegram verification нужно судить по реальному тексту ответа, а не по одному только workflow verdict;
- для Telegram-safe routes payload delivery path и live user-visible effect могут расходиться;
- authoritative UAT taxonomy должен ловить не только dirty telemetry leaks, но и clean semantic violations.

Что оказалось новым:

- текущий residual баг не требовал tool call вообще;
- direct/in-band delivery debate не объяснял observed run, потому что плохой live ответ появился в run без tool calls и без hook timeout;
- корень оказался глубже: turn classifier не видел latest message content при live array/object payload shape.

## Evidence

### 1. Production run показал, что bad reply пришёл без tool calls

Из `/opt/moltinger/data/logs.jsonl` для live run `60e379e2-1e8f-4ebc-9be0-5c2dc07aa3e3`:

- `chat.send` на exact user message про cron/Codex CLI
- `calling LLM (streaming)` почти сразу после inbound dispatch
- `tool_calls_count = 0`
- final response already contained the clean false-positive memory wording

Это исключило гипотезу "response сломался уже после tool branch".

### 2. Server script и hook registration были корректны

На production проверено:

- `/opt/moltinger/scripts/telegram-safe-llm-guard.sh` содержал уже актуальный codex-update guard code;
- hook `telegram-safe-llm-guard` был зарегистрирован в live runtime и виден в `moltis hooks list --json`.

То есть проблема не была deploy drift или missing hook registration.

### 3. Local repro восстановил именно observed production behavior

До фикса:

- string payload для `BeforeLLMCall` на exact scheduler question приводил guard к codex-update hard override/direct fastpath;
- но тот же payload с `messages[].content` в форме:
  - `[{ "type": "input_text", "text": "..." }]`
  не распознавался как codex-update turn.

В этом случае guard возвращал только generic Telegram-safe mutate path:

- original messages preserved
- `tool_count=0`
- no codex-update hard override

Это exactly explains live run:

- model saw the original user prompt;
- tools were unavailable/zeroed;
- model still fabricated a clean memory-based answer.

### 4. UAT taxonomy underfit this wording

Artifact `/tmp/pr179-uat-artifacts/telegram-e2e-result.json` уже содержал bad reply family:

- `По сохранённой памяти у меня зафиксировано...`
- `ежедневно проверять стабильные обновления Codex CLI`
- `наличие такого крона подтверждено`

Но `reply_has_codex_update_scheduler_memory_false_negative()` не ловил эти variants, поэтому workflow ошибочно пометил run как `passed`.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---|---|---|
| 1 | Почему пользователь снова получил ложный ответ про cron "по памяти"? | Потому что модель увидела исходный prompt и сгенерировала clean memory-based answer без tool path. |
| 2 | Почему Telegram-safe guard не переписал этот turn в codex-update contract? | Потому что classifier не смог извлечь latest user/system text из live `messages[].content`, пришедшего как array/object parts. |
| 3 | Почему classifier не смог этого сделать? | Потому что `extract_last_message_content_by_role()` умел вытаскивать `content` только как plain JSON string. |
| 4 | Почему это не поймали раньше? | Потому что component tests использовали только string-shaped `messages[].content`, а authoritative UAT matcher искал только старые dirty memory/tool-leak variants. |
| 5 | Почему это дожило до production despite prior fixes? | Потому что предыдущие fix cycles спорили о delivery path, а не проверили более базовую предпосылку: одинаково ли hook вообще читает live payload shape и test payload shape. |

## Root Cause

Корневая причина была в payload-shape contract drift между тестовым и live `BeforeLLMCall` payload:

- tests моделировали `messages[].content` как plain string;
- live runtime может присылать `content` как array/object text parts;
- `scripts/telegram-safe-llm-guard.sh` извлекал текст только из string content;
- из-за этого codex-update scheduler turn выпадал из classifier;
- guard не делал deterministic codex-update rewrite, а только generic `tool_count=0`;
- model отвечала clean, но неверным memory-assertion текстом.

Дополнительный contributing factor:

- authoritative UAT taxonomy ловила старые wording families, но не observed live phrasing `По сохранённой памяти у меня зафиксировано...`.

## Исправления

Сделано:

1. `scripts/telegram-safe-llm-guard.sh`
   - `extract_last_message_content_by_role()` переведён на JSON-aware flatten:
     - string content
     - array content
     - object content
     - common nested text fields (`text`, `content`, `input_text`, `output_text`, `value`)
   - string fallback path сохранён для degraded environments
2. `tests/component/test_telegram_safe_llm_guard.sh`
   - добавлена live-like regression на `BeforeLLMCall`, где system/user messages приходят как `input_text` arrays
   - regression требует того же codex-update direct fastpath / scheduler contract, что и string payload
3. `scripts/telegram-e2e-on-demand.sh`
   - semantic matcher `reply_has_codex_update_scheduler_memory_false_negative()` расширен на observed live wording:
     - `По сохранённой памяти у меня зафиксировано`
     - `ежедневно проверять стабильные обновления Codex CLI`
     - `наличие такого крона подтверждено`
4. `tests/component/test_telegram_remote_uat_contract.sh`
   - добавлен dedicated stub/test на recorded-memory clean false-positive variant

## Проверка

Локально подтверждено:

- array-shaped repro теперь выдаёт codex-update hard override, а не original prompt passthrough
- `bash tests/component/test_telegram_safe_llm_guard.sh` → `121/121 PASS`
- `bash tests/component/test_telegram_remote_uat_contract.sh` → `44/44 PASS`
- `git diff --check` → clean

## Предотвращение

1. Для Telegram-safe hooks tests должны покрывать не только string payloads, но и live-like structured message content.
2. Если live run противоречит classifier expectations, сначала нужно проверить payload shape parity, а уже потом спорить о delivery architecture.
3. Authoritative UAT semantic checks должны ловить clean semantic lies, а не только internal telemetry leaks.

## Уроки

1. Для Telegram-safe guard'ов `messages[].content` shape является частью public runtime contract; string-only tests недостаточны.
2. `tool_count=0` без правильной intent classification не равен safe deterministic answer — модель всё ещё может уверенно соврать без tool calls.
3. Зеленый authoritative workflow ничего не стоит, если semantic taxonomy не знает наблюдавшийся bad wording family.
