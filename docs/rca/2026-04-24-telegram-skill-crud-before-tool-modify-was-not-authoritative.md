---
title: "Telegram skill CRUD still failed because live runtime did not authoritatively apply BeforeToolCall modify"
date: 2026-04-24
severity: P1
category: product
tags: [telegram, skills, hooks, runtime, create-skill, update-skill, patch-skill, rca]
root_cause: "Repo-owned repair initially assumed that normalizing create_skill/update_skill/patch_skill arguments in BeforeToolCall was sufficient, but authoritative production evidence showed live Moltis still validated the raw tool envelope and ignored that modify payload on the Telegram path."
---

# RCA: Telegram skill CRUD still failed because live runtime did not authoritatively apply BeforeToolCall modify

**Дата:** 2026-04-24
**Статус:** Resolved
**Влияние:** В Telegram пользователь видел `missing 'name' parameter` и похожие raw validation errors во время skill CRUD, хотя в сохранённом tool-call JSON имя и другие поля уже присутствовали. Это блокировало создание, обновление и sidecar-редактирование навыков прямо из бота.
**Контекст:** `scripts/telegram-safe-llm-guard.sh`, live Moltis Telegram runtime, dedicated skill tools `create_skill`/`update_skill`/`patch_skill`/`delete_skill`/`write_skill_files`.

## Ошибка

После предыдущих ремонтов Telegram-safe guard уже:

- правильно маршрутизировал Russian CRUD intent;
- правильно canonicalized dirty tool envelopes с `_channel`, `_session_key`, `body`, `allowed_tools`;
- перестал уходить в `exec`/filesystem probing.

Но authoritative production evidence всё равно показывал новый сбой:

- `create_skill` приходил с `name`, `body`, `description`, `allowed_tools`, а live runtime отвечал `missing 'name' parameter`;
- `Glob` приходил с `pattern`, но live runtime отвечал `missing 'pattern'`.

Общая форма была одинаковой: hook генерировал корректный `modify`, но live Telegram runtime исполнял и валидировал исходный сырой envelope, а не нормализованный payload.

## Проверка прошлых уроков

Перед фиксом были повторно проверены:

- `docs/LESSONS-LEARNED.md`
- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag skills`
- `docs/rca/2026-04-23-moltis-tool-argument-envelope-drift.md`
- `docs/rca/2026-04-23-telegram-direct-fastpath-before-llm-must-block.md`
- `docs/rca/2026-04-24-telegram-skill-crud-posix-locale-and-perl-fallback.md`

Релевантные прошлые уроки уже указывали:

1. dirty-but-valid envelopes нужно чинить в argument boundary, а не маскировать delivery;
2. для Telegram runtime `hook emitted correct JSON` не равно `runtime actually applied it`;
3. wrong intent bucket и поздний reply rewrite не заменяют фикса на owning layer.

Что было новым:

- даже после исправленной `BeforeToolCall` canonicalization live runtime Telegram всё ещё не давал авторитетного применения этого `modify` для native skill CRUD;
- значит корневой дефект был не только в форме аргументов, а в самой границе применения hook result.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---|---|---|---|
| 1 | Почему Telegram skill CRUD продолжал падать с `missing 'name' parameter`? | Потому что live runtime валидировал сырой tool envelope, а не нормализованный hook payload. | Production container logs for `create_skill` showed `name` inside persisted args and simultaneous runtime validation failure. |
| 2 | Почему normalizing `BeforeToolCall` не исправил поведение? | Потому что на этой live Telegram path `BeforeToolCall modify` не был authoritative execution boundary. | Hook artifacts stored the cleaned args, but runner still consumed the dirty raw envelope. |
| 3 | Почему это не поймали раньше? | Потому что synthetic/component checks доказывали корректность hook JSON, но не применение `modify` внутри live Moltis execution path. | Local tests passed while authoritative production CRUD still failed. |
| 4 | Почему symptom выглядел как ошибка модели, хотя поля были на месте? | Потому что runtime error message сообщал про missing required field, хотя реальная проблема была в bypass нормализованного envelope. | Same pattern reproduced for several tools, not just skill CRUD. |
| 5 | Почему нужен был другой архитектурный путь? | Потому что пока live Telegram runtime не гарантирует применение `BeforeToolCall modify`, repo-owned fix должен терминализовать этот класс turn раньше и выполнять owned CRUD deterministic path вне broken boundary. | Existing direct fastpath pattern already proved reliable for other Telegram-safe critical flows. |

## Корневая причина

Owning layer defect находился в repo-managed Telegram-safe contract design. Ремонт всё ещё полагался на live Moltis execution semantics, где `BeforeToolCall modify` для Telegram не был надёжным authoritative boundary. Поэтому даже корректная canonicalization не превращалась в корректное выполнение native skill CRUD.

Иными словами: проблема была не в том, что guard не умел очистить аргументы, а в том, что live runtime не обязанно исполнял именно очищенную версию этих аргументов.

## Принятые меры

1. Добавлен deterministic `AfterLLMCall` direct execution path для Telegram-safe native skill CRUD.
2. Этот path выполняет `create_skill`, `update_skill`, `patch_skill`, `delete_skill`, `write_skill_files` напрямую в runtime skills root и отправляет один clean user-facing reply через direct Bot API fastpath.
3. Для `create_skill` и `update_skill` добавлена compatibility normalization `body -> content`; `allowed_tools` удаляется как legacy drift.
4. Для `patch_skill` зафиксирован official contract `patches[]`; legacy `instructions` больше не считаются каноническим путём.
5. Prompt/config слой усилен: system guidance теперь явно запрещает legacy поля `body`, `allowed_tools`, `instructions` и закрепляет official skill tool schema.
6. Component regressions теперь доказывают не только canonicalization, но и реальное deterministic выполнение CRUD flow без попадания в broken live tool boundary.

## Уроки

1. Для live Telegram runtime `BeforeToolCall modify` нельзя считать authoritative только потому, что hook script вернул правильный JSON.
2. Если upstream/live boundary игнорирует repo-owned normalization, следующий source fix должен переносить critical flow в другой owning execution layer, а не добавлять ещё один rewrite.
3. Для skill CRUD Telegram-safe contract должен одновременно:
   - задавать official schema модели;
   - терпеть legacy drift на входе;
   - исполнять critical path там, где repo действительно контролирует выполнение.

## Regression Test

**Test File:** `tests/component/test_telegram_safe_llm_guard.sh`

**Test Status:**

- [x] Test created
- [x] Test reproduces the live-like envelope drift
- [x] Fix applied
- [x] Test passes
