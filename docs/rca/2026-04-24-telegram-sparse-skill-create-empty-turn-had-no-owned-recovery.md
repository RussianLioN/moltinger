---
title: "Telegram sparse skill create could still go silent because empty LLM turns had no repo-owned recovery"
date: 2026-04-24
severity: P1
category: product
tags: [telegram, skills, hooks, runtime, create-skill, sparse-create, rca]
root_cause: "Repo-owned Telegram skill CRUD hardening already bypassed the broken live tool boundary when the model emitted native skill tool calls, but it still assumed a valid sparse create request would always produce either text or tool calls. Authoritative production evidence showed `gpt-5.4` can return an empty AfterLLMCall payload for the same request, so the turn ended with `silent=true` and no repo-owned recovery path."
---

# RCA: Telegram sparse skill create could still go silent because empty LLM turns had no repo-owned recovery

**Дата:** 2026-04-24  
**Статус:** Resolved  
**Влияние:** пользователь отправлял в Telegram валидный запрос вида `Создай новый навык <slug> ...`, а бот не отвечал вообще и не создавал навык.  
**Контекст:** `scripts/telegram-safe-llm-guard.sh`, live Moltis Telegram runtime, authoritative Telegram Web UAT, dedicated skill tools `create_skill` / `update_skill` / `patch_skill` / `delete_skill` / `write_skill_files`.

## Ошибка

После предыдущего ремонта live Telegram skill CRUD уже умел:

- держать `sparse create` на native skill-tool lane;
- обходить broken `BeforeToolCall modify` boundary;
- напрямую исполнять `create_skill/update_skill/patch_skill/delete_skill/write_skill_files` на `AfterLLMCall`, если модель уже вернула эти tool calls.

Но в live production появился новый класс сбоя:

- Telegram ingress принимал пользовательский create-запрос;
- `chat.send` уходил в `openai-codex::gpt-5.4`;
- модель завершала turn без текста и без tool calls;
- runtime логировал `silent=true`;
- repo-owned guard ничего не делал, потому что direct skill CRUD path включался только при наличии tool calls.

Итог: пользователь видел `bot_no_response`.

## Проверка прошлых уроков

Перед фиксом были повторно проверены:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag skills`
- `docs/rca/2026-04-24-telegram-skill-crud-before-tool-modify-was-not-authoritative.md`
- `docs/rca/2026-04-23-moltis-tool-argument-envelope-drift.md`
- `docs/rca/2026-04-23-telegram-direct-fastpath-before-llm-must-block.md`

Релевантные уже закреплённые уроки:

1. broken live boundary нельзя лечить ещё одним `BeforeToolCall modify`;
2. Telegram-safe critical flow нужно переносить в owning execution layer, а не надеяться на красивый prompt;
3. `hook emitted good JSON` и `runtime реально применил это` — разные утверждения.

Что было новым:

- даже без грязного tool envelope и без visible tool error Telegram turn мог завершиться пустым ответом;
- текущий repo-owned recovery покрывал только ветку `tool_calls present`, но не ветку `valid intent + empty model turn`.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---|---|---|---|
| 1 | Почему Telegram не ответил на `Создай новый навык ...`? | Потому что модель вернула пустой `AfterLLMCall` без текста и без tool calls. | Production logs for `run_id=4ec67573-5589-4164-88a6-2d815cbfaf29`: `tool_calls=0`, `response=`, `silent=true`. |
| 2 | Почему guard не восстановил turn? | Потому что direct skill CRUD path запускался только когда `tool_calls_only_direct_skill_crud_supported == true`. | `scripts/telegram-safe-llm-guard.sh` before fix: direct execution branch required actual tool calls. |
| 3 | Почему это не поймали раньше? | Потому что предыдущий fix был сфокусирован на broken tool-boundary и raw validation errors, а не на empty-turn behavior модели. | Earlier RCA/test suite proved `tool call present -> direct execution`, but not `valid sparse create -> empty turn`. |
| 4 | Почему нельзя было просто вернуть старый `BeforeLLMCall` direct-create? | Потому что этот путь уже был сознательно убран: sparse create должен сначала оставаться на native skill-tool lane, а не обходить её заранее. | Existing regression `component_before_llm_guard_does_not_direct_fastpath_sparse_skill_create_anymore`. |
| 5 | Какой source fix нужен был на самом деле? | Нужно было добавить repo-owned `AfterLLMCall` recovery именно для `sparse create + empty turn`, синтезируя минимальный `create_skill` в том же deterministic direct CRUD layer. | New fix and regression create the skill and send one clean Telegram reply even when model returns empty. |

## Корневая причина

Owning layer defect был в неполном Telegram-safe recovery contract.  
Репозиторий уже взял под свой контроль ветку `native skill tool calls are present`, но ошибочно предположил, что valid sparse create intent всегда дойдёт хотя бы до текста или до tool calls.

Live `gpt-5.4` это предположение опроверг: sparse create turn может закончиться пустым `AfterLLMCall`.  
Без отдельного repo-owned recovery такой turn превращался в `silent hole`.

## Принятые меры

1. Добавлен deterministic `AfterLLMCall` recovery path для `current_turn_sparse_skill_create_request == true`, когда:
   - turn уже классифицирован как native skill CRUD;
   - tool calls отсутствуют;
   - `requested_skill_name` извлечён;
   - model reply пустой.
2. Новый path синтезирует minimal `create_skill` call и исполняет его через тот же `execute_direct_skill_tool_calls_json`, что и обычный direct CRUD branch.
3. Результат доставляется через тот же Bot API suppression-aware fastpath, без возврата к старому `BeforeLLMCall` direct-create.
4. Добавлен regression test на точную live-фразу:
   - `Создай новый навык moltis-version-watch-20260424 для автоматического отслеживания новой версии Moltis.`
5. Regression доказывает:
   - пустой `AfterLLMCall` больше не заканчивается `silent hole`;
   - навык реально создаётся в runtime root;
   - пользователю уходит один чистый итог без tool tail.

## Уроки

1. Для Telegram-safe skill CRUD нужно покрывать не только broken-tool boundary, но и пустые модельные завершения без tool calls.
2. Если native lane остаётся правильной архитектурой, repo-owned recovery должен жить после неё, а не возвращать более ранний shortcut.
3. `silent=true` в live логах — это отдельный defect class, а не «модель просто неудачно ответила».

## Regression Test

**Test File:** `tests/component/test_telegram_safe_llm_guard.sh`

**Test Status:**

- [x] Test created
- [x] Test reproduces sparse create with empty `AfterLLMCall`
- [x] Fix applied
- [x] Test passes
