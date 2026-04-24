---
title: "Telegram sparse skill create recovery still depended on the current-turn user message instead of persisted CRUD intent"
date: 2026-04-24
severity: P1
category: product
tags: [telegram, skills, hooks, runtime, create-skill, sparse-create, persisted-intent, rca]
root_cause: "The repo had already added an AfterLLMCall recovery for sparse Telegram skill create, but that recovery still reconstructed its target name from the current AfterLLMCall payload. Live Telegram runs can omit the user message entirely on that phase, so the turn still ended silent unless CRUD mode and target name were persisted and rehydrated from repo-owned state."
---

# RCA: Telegram sparse skill create recovery still depended on the current-turn user message instead of persisted CRUD intent

**Дата:** 2026-04-24
**Статус:** Resolved
**Влияние:** После предыдущего ремонта Telegram skill create всё ещё мог завершиться `bot_no_response`: пользователь отправлял валидный запрос на создание навыка, но live `AfterLLMCall` приходил без user message, имя навыка повторно не извлекалось, навык не создавался, ответ не уходил.
**Контекст:** `scripts/telegram-safe-llm-guard.sh`, authoritative Telegram Remote UAT, production logs for live sparse create, persisted turn intent contract `skill_native_crud`.

## Ошибка

Предыдущий fix уже закрыл один дефект:

- пустой `AfterLLMCall` больше не считался допустимым silent turn;
- guard умел синтезировать minimal `create_skill`;
- архитектурно recovery жил в owning `AfterLLMCall` layer, а не в старом `BeforeLLMCall` shortcut.

Но authoritative production/UAT показали ещё один live-only разрыв:

- на `BeforeLLMCall` пользовательский текст и имя нового навыка были видны;
- на позднем `AfterLLMCall` live payload иногда содержал только system messages;
- recovery branch продолжал опираться на `requested_skill_name`, повторно извлекаемый из текущего payload;
- из-за этого ветка `sparse create recovery` не срабатывала, хотя persisted intent уже доказывал, что turn относится к native skill CRUD и это именно `create`.

Итог: user intent был корректно классифицирован, но recovery не имел достаточного repo-owned состояния, чтобы завершить turn без повторного чтения исчезнувшего user message.

## Проверка прошлых уроков

Перед фиксом были повторно проверены:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag skills`
- `docs/rca/2026-04-24-telegram-sparse-skill-create-empty-turn-had-no-owned-recovery.md`
- `docs/rca/2026-04-24-telegram-skill-crud-before-tool-modify-was-not-authoritative.md`
- `docs/rca/2026-04-23-telegram-direct-fastpath-before-llm-must-block.md`

Релевантные уже закреплённые уроки:

1. Telegram-safe critical path нельзя считать починенным, пока live runtime не доказан authoritative UAT, а не только локальным component coverage.
2. Для Telegram runtime `hook emitted correct JSON` и `runtime supplied the same payload shape on the next phase` — разные утверждения.
3. Если owning layer уже взял под контроль critical turn, recovery должен опираться на repo-owned state, а не на повторное везение с upstream payload shape.

Что было новым:

- предыдущий sparse-create fix предполагал, что live `AfterLLMCall` всё ещё несёт user message, хотя authoritative production path это опроверг;
- persisted contract `skill_native_crud` был слишком бедным: он сохранял класс turn, но не сохранял достаточно данных для late recovery;
- отдельно вскрылся вторичный drift: persisted native CRUD turn не должен уходить в чистый Tavily/search path, если live модель снова свернула в чужой tool family.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---|---|---|---|
| 1 | Почему после прошлого sparse-create fix Telegram всё ещё иногда не отвечал? | Потому что live `AfterLLMCall` мог прийти без user message, и recovery не мог повторно извлечь имя навыка. | Authoritative UAT run `24870123224` ended with `bot_no_response`; production logs showed `has_text=false`, `tool_calls_count=0`, `silent=true`, and no created skill file for the requested slug. |
| 2 | Почему recovery не взял имя навыка из уже сохранённого состояния? | Потому что persisted turn intent хранил только общий маркер `skill_native_crud`, без режима и target slug. | `scripts/telegram-safe-llm-guard.sh` before fix restored only coarse turn intent; sparse recovery still depended on current `requested_skill_name`. |
| 3 | Почему это не поймали локально раньше? | Потому что локальный regression fixture для `AfterLLMCall` всё ещё содержал user message и тем самым скрывал live payload drift. | Local test passed before live UAT; updated regression that removes user message from `AfterLLMCall` failed until persisted CRUD hydration was added. |
| 4 | Почему простой reply suppression не решал проблему? | Потому что defect был не в грязном тексте, а в отсутствии достаточного repo-owned execution context для owned recovery branch. | No duplicate/leak message was sent; the turn simply ended silent without creating the skill. |
| 5 | Какой source fix нужен был на самом деле? | Нужно было расширить persisted CRUD intent до режима и target name, гидрировать его на поздних фазах и использовать как authoritative fallback context; для чистого Tavily drift на persisted CRUD turn нужно fail-close, а не разрешать уводить turn в search tools. | New fix persists `skill_native_crud:create:<slug>`-style intent, restores name/mode on `AfterLLMCall`, and strips pure Tavily tool calls for persisted CRUD turns. |

## Корневая причина

Owning layer defect был в неполном persisted-state contract для Telegram-safe skill CRUD.

Репозиторий уже перенёс sparse create recovery в deterministic `AfterLLMCall` layer, но сохранил скрытое предположение: будто текущий `AfterLLMCall` всегда позволит заново вычислить target skill name из live payload. В production это неверно. Когда upstream payload терял user message, repo-owned recovery фактически оставался без собственных данных для завершения create-turn.

Иными словами: проблема была уже не в отсутствии recovery как такового, а в том, что recovery всё ещё зависел от неавторитетного upstream payload shape вместо repo-owned persisted CRUD context.

## Принятые меры

1. Persisted native CRUD turn intent расширен до backward-compatible форм:
   - `skill_native_crud`
   - `skill_native_crud:create:<name>`
   - `skill_native_crud:update:<name>`
   - `skill_native_crud:delete:<name>`
2. Добавлена гидрация persisted CRUD state на поздних hook phases:
   - восстанавливаются `mode`, `target skill name`, `sparse create` flag;
   - если текущий payload не содержит user message, recovery всё равно видит нужный slug.
3. Sparse create `AfterLLMCall` recovery теперь использует effective context:
   - `current sparse create OR persisted sparse create`
   - `current requested skill name OR persisted CRUD target`.
4. Для persisted native CRUD turn добавлен fail-closed branch против pure Tavily/search drift:
   - чистые Tavily tool calls не допускаются внутри Telegram-safe skill CRUD turn;
   - пользователю возвращается deterministic объяснение, а не ложный browser/search path.
5. Component regression обновлён под реальный live payload:
   - `AfterLLMCall` fixture больше не содержит user message;
   - test доказывает, что skill реально создаётся и direct reply уходит даже при таком payload.

## Уроки

1. Persisted intent для Telegram-safe critical flow должен хранить не только класс turn, но и минимальный execution context, необходимый для late recovery.
2. Если live runtime может менять payload shape между hook phases, recovery нельзя строить на повторном парсинге тех же user fields из следующей фазы.
3. Для native skill CRUD persisted context должен защищать не только от silent hole, но и от дрейфа в нерелевантные search/browser tools.

## Regression Test

**Test File:** `tests/component/test_telegram_safe_llm_guard.sh`

**Test Status:**

- [x] Test created
- [x] Test reproduces live `AfterLLMCall` without user message
- [x] Fix applied
- [x] Test passes
