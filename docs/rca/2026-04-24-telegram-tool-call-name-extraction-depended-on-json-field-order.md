---
title: "Telegram skill CRUD fastpath depended on JSON field order when extracting tool call names"
date: 2026-04-24
severity: P1
category: product
tags: [telegram, skills, hooks, runtime, after-llm, tool-calls, json, rca]
root_cause: "The Telegram-safe guard treated tool-call name extraction as a regex/string problem instead of a JSON contract. On live `AfterLLMCall` payloads, tool-call objects arrived as `{arguments, id, name}` rather than `{name, arguments}`, so `extract_tool_call_names()` failed to see allowlisted skill tools and skipped both direct CRUD execution and safe progress rewriting."
---

# RCA: Telegram skill CRUD fastpath depended on JSON field order when extracting tool call names

**Дата:** 2026-04-24
**Статус:** Resolved
**Влияние:** В live Telegram пользователь снова видел `create_skill ... missing 'name'`, хотя `AfterLLMCall` уже содержал корректный top-level `tool_calls` с `name`. Repo-owned fastpath не срабатывал и turn уходил в broken upstream tool boundary.
**Контекст:** `scripts/telegram-safe-llm-guard.sh`, `extract_tool_call_names()`, `tool_calls_only_direct_skill_crud_supported()`, `tool_calls_only_allowlisted()`, authoritative Telegram skill-create UAT.

## Ошибка

После предыдущего ремонта skill CRUD ещё один live create-turn снова упал в production:

- authoritative Telegram UAT на `Создай новый навык ...`
- live reply: `Не создался: create_skill снова вернул missing 'name'`
- production container logs одновременно показывали, что `AfterLLMCall` и `BeforeToolCall` уже несли `name`

Сначала это выглядело как очередной broken `BeforeToolCall` boundary. Но raw capture показал более точную картину:

- `AfterLLMCall` действительно содержал `tool_calls`
- объект tool call приходил как `{"arguments":{...},"id":"...","name":"create_skill"}`
- helper `extract_tool_call_names()` искал `"name"` только в позиции первого поля объекта

Из-за этого guard неверно решал, что allowlisted skill tools в ответе нет.

## Проверка прошлых уроков

Перед фиксом были повторно проверены:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag skills`
- `docs/LESSONS-LEARNED.md`
- `docs/rca/2026-04-23-moltis-tool-argument-envelope-drift.md`
- `docs/rca/2026-04-24-telegram-skill-crud-before-tool-modify-was-not-authoritative.md`
- `docs/rca/2026-04-24-telegram-sparse-skill-create-empty-turn-had-no-owned-recovery.md`

Что уже было известно:

1. нужно отличать `tool missing args` от `dirty but valid tool envelope`;
2. `BeforeToolCall modify` для Telegram нельзя считать authoritative;
3. live RCA нужно строить по container capture, а не по предположению о payload shape.

Что было новым:

- this time `AfterLLMCall` tool call существовал, но repo helper его не распознавал;
- проблема была не в отсутствии tool call и не в игнорировании самого `AfterLLMCall`, а в brittle field-order parsing.

## Evidence

### 1. Production capture опроверг гипотезу `tool_calls` нет

Captured `AfterLLMCall` payload for the failing turn contained:

- `text: "Пробую создать навык."`
- `tool_calls[0].name = "create_skill"`
- `tool_calls[0].arguments.name = "moltis-version-watch-20260424-tele-a1"`

То есть authoritative raw evidence показал: fastpath branch получил весь нужный JSON, но helper выше по стеку его не распознал.

### 2. Old extractor depended on `"name"` being the first object field

До фикса:

```bash
printf '%s' "$tool_calls_json" \
  | grep -oE '(^|[\[,])[[:space:]]*\{[[:space:]]*"name"[[:space:]]*:[[:space:]]*"[^"]+"'
```

Такой matcher работает только для shape:

```json
{"name":"create_skill","arguments":{...}}
```

Но не для live shape:

```json
{"arguments":{...},"id":"call_...","name":"create_skill"}
```

### 3. The same brittle extraction also broke update-skill control flow

После первой попытки починки create-path локальные regressions показали второй скрытый симптом:

- explicit `update_skill` turns переставали идти в allowlisted skill-authoring flow;
- `tool_calls_only_allowlisted()` and `tool_calls_only_direct_skill_crud_supported()` both depended on the same fragile extraction layer.

Это подтвердило, что фикс нужен не точечный под create, а на shared helper contract.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---|---|---|---|
| 1 | Почему live Telegram снова упал в `missing 'name'`? | Потому что direct CRUD fastpath не сработал и runtime ушёл в broken upstream tool boundary. | authoritative UAT + live runtime logs |
| 2 | Почему direct CRUD fastpath не сработал, хотя `AfterLLMCall` уже нёс `tool_calls`? | Потому что helper не смог распознать имя tool call. | raw capture showed `tool_calls[0].name=create_skill` |
| 3 | Почему helper не смог распознать имя? | Потому что он искал `"name"` только как первое поле JSON-объекта. | old regex in `extract_tool_call_names()` |
| 4 | Почему это не поймали раньше? | Потому что component tests использовали только canonical order `{name, arguments}` и не покрывали live order `{arguments, id, name}`. | old regression fixtures |
| 5 | Почему это системная проблема, а не единичный create bug? | Потому что тот же helper использовался и для allowlist routing, и для direct CRUD execution across create/update/delete paths. | both failing regressions after first patch attempt |

## Корневая причина

Repo-owned Telegram-safe guard нарушал JSON contract на границе `AfterLLMCall`: вместо семантического JSON parsing он извлекал имена tool calls position-sensitive regex-паттерном. Live Moltis payload поменял порядок полей внутри tool call object, и shared helper перестал видеть allowlisted skill tools.

Иными словами: payload был валидный, но repo parser был хрупкий.

## Принятые меры

1. `extract_tool_call_names()` переписан на JSON-aware extraction:
   - primary path: `perl + JSON::PP` over the full `tool_calls` array;
   - fallback path: top-level object field extraction without depending on field order.
2. Existing direct CRUD regression updated to use live-like tool-call object order `{arguments, id, name}`.
3. Full component suite re-run to confirm both:
   - direct `create_skill` CRUD fastpath;
   - allowlisted `update_skill` progress routing;
   - direct `update_skill/delete_skill` execution.

## Уроки

1. Для Telegram-safe hooks имена tool calls нужно извлекать как JSON semantics, а не regex по позиции полей.
2. Component regressions обязаны включать live-like field order, а не только canonical pretty shape.
3. Если authoritative capture уже показывает валидный tool call, следующий root fix должен быть в parser contract, а не в очередной heuristic around fallback text.

## Regression Test

**Test File:** `tests/component/test_telegram_safe_llm_guard.sh`

**Test Status:**

- [x] live-like `{arguments, id, name}` regression added
- [x] explicit `update_skill` allowlisted flow still passes
- [x] direct `update_skill/delete_skill` execution still passes
- [x] full suite passes
