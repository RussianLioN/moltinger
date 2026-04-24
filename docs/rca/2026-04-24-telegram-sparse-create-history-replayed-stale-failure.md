---
title: "Telegram sparse skill create replayed stale create-skill failure from contaminated history"
date: 2026-04-24
severity: P1
category: product
tags: [telegram, skills, hooks, runtime, create-skill, sparse-create, history, contamination, rca]
root_cause: "BeforeLLMCall still passed contaminated session history into sparse Telegram create turns. When old assistant messages already claimed `create_skill` was broken, the model simply repeated that stale failure instead of starting a fresh native CRUD attempt."
---

# RCA: Telegram sparse skill create replayed stale create-skill failure from contaminated history

**Дата:** 2026-04-24  
**Статус:** Resolved  
**Влияние:** После merge/deploy предыдущего Telegram skill-CRUD фикса пользователь всё ещё мог получить ложный ответ вида `Не могу создать ... create_skill сломан ... missing 'name'` на полностью валидный новый запрос создания навыка. Навык не создавался, потому что модель не делала ни одного tool call и просто повторяла старую failure-реплику из истории сессии.  
**Контекст:** `scripts/telegram-safe-llm-guard.sh`, authoritative Telegram Remote UAT for production create-skill flow, hook capture bundle inside live container.

## Ошибка

На production был повторно прогнан authoritative Telegram UAT exact prompt:

`Создай новый навык moltis-version-watch-20260424-tele-a1 для автоматического отслеживания новой версии Moltis.`

UAT завершился `failed`, но не из-за отсутствия reply. Reply был, однако он был неверным и содержал старую ложную диагностику:

`Не могу создать в этой сессии: create_skill сломан и возвращает missing 'name' даже при корректном вызове.`

Production logs показали, что в этом ходе:

- `BeforeLLMCall` стартовал как обычный safe Telegram create turn;
- `AfterLLMCall` завершился с `tool_calls_count=0`;
- итоговый текст был именно старым failure-ответом;
- Telegram реально отправил этот текст пользователю.

То есть проблема была не в поздней доставке и не в скрытом tool error: модель вообще не вошла в fresh native CRUD path.

## Проверка прошлых уроков

Перед фиксом были повторно проверены:

- `docs/LESSONS-LEARNED.md`
- `docs/rca/2026-04-24-telegram-sparse-create-recovery-needed-persisted-crud-intent.md`
- `docs/rca/2026-04-24-telegram-tool-call-name-extraction-depended-on-json-field-order.md`
- `docs/rca/2026-04-24-telegram-skill-crud-before-tool-modify-was-not-authoritative.md`
- live hook capture и production logs для exact failing run

Что уже было известно из прошлых уроков:

1. `AfterLLMCall`/`MessageSending modify` нельзя считать authoritative proof сами по себе; нужен source fix раньше по critical path.
2. Sparse create-turn обязан входить в native skill CRUD lane, а не в browser/search/maintenance path.
3. Live Telegram payload shape может отличаться от локальных fixture и это надо подтверждать authoritative UAT.

Что было новым в этом инциденте:

1. Даже после исправления persisted CRUD intent новый sparse create-turn всё ещё мог быть заражён старой assistant history.
2. Проблема была уже не в пустом `AfterLLMCall`, а в том, что модель до него видела старые failure-traces и принимала их за актуальный контекст текущей попытки.
3. Репозиторий ещё не имел repo-owned guard, который бы принудительно очищал contaminated sparse-create history до нового create-turn.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---|---|---|---|
| 1 | Почему новый Telegram create request снова вернул старый текст про `create_skill` и `missing 'name'`? | Потому что модель увидела в history старые assistant failure messages и повторила их вместо нового tool path. | Authoritative UAT run `24872155539` observed the exact stale failure text as the matched reply. |
| 2 | Почему модель вообще видела эти старые failure messages в fresh sparse create-turn? | Потому что `BeforeLLMCall` для sparse create только prepend'ил guards, но не вычищал contaminated session history. | Live capture `20260424T042635Z-712.output.json` showed `message_count=165` and still contained prior assistant lines about `create_skill` returning `missing 'name'`. |
| 3 | Почему это стало критично именно для create-turn? | Потому что sparse create relies on a fresh first native CRUD attempt; stale assistant refusal in the same history changes the model prior and nudges it to answer textually instead of calling `create_skill`. | Live `AfterLLMCall` payload `20260424T042642Z-1203.payload.json` had `tool_calls=[]` and already contained the stale refusal text. |
| 4 | Почему поздняя `AfterLLMCall modify` перепись не спасла пользователя? | Потому что в этом path live runtime всё ещё завершал run исходным текстом модели, а не modified replacement. | Capture showed `AfterLLMCall output` already tried to rewrite to Telegram-safe generic text, but production run still completed with the stale failure message. |
| 5 | Какой repo-owned fix действительно устраняет корень причины? | Нужно очищать sparse create-turn history ещё в `BeforeLLMCall`, если там уже есть stale create-failure traces, и передавать модели только current user request плюс свежие skill guards. | New regression test reproduces that exact contamination shape; after fix the modified payload contains only guard systems and the latest user create request. |

## Корневая причина

Корневая причина была в incomplete `BeforeLLMCall` contract для Telegram sparse create-turn.

Guard уже умел:

- классифицировать sparse create;
- запрещать лишние tool families;
- добавлять skill-authoring instructions.

Но он всё ещё предполагал, что достаточно просто prepend'ить эти guards к существующему `messages_json`. Это предположение оказалось ложным: если в той же сессии уже накопились старые assistant/tool traces о поломанном `create_skill`, модель воспринимала их как актуальное состояние текущей попытки и повторяла старый отказ вместо fresh native CRUD start.

Иными словами: проблема была не в отсутствии инструкций, а в том, что current sparse create-turn не был изолирован от исторического мусора, который уже противоречил этим инструкциям.

## Принятые меры

1. Для sparse create-turn добавлен explicit contamination detector по raw `messages_json`.
2. Если история содержит stale create-failure markers (`create_skill`, `missing 'name'`, `не смог создать`, `сломан`, `broken`), `BeforeLLMCall` теперь сбрасывает history до минимального current-turn контекста:
   - свежие Telegram skill guards;
   - последний user create request.
3. Добавлен regression test `component_before_llm_guard_resets_sparse_create_history_after_stale_create_failure`.
4. Полный suite `bash tests/component/test_telegram_safe_llm_guard.sh` повторно прогнан и прошёл `167/167`.

## Уроки

1. Для Telegram-safe create/update/delete flows недостаточно добавить правильные guards; нужно ещё изолировать текущий turn от stale assistant/tool history, если она уже противоречит current contract.
2. Если live capture показывает `tool_calls=0` и устаревший отказ в ответе, сначала нужно проверять contaminated `BeforeLLMCall` history, а не лечить только `AfterLLMCall` output rewriting.
3. Sparse create-turn — это отдельный high-risk режим: ему нужен minimal current-turn context, иначе старая незавершённая create/debug история легко перезапишет намерение модели.

## Regression Test

**Test File:** `tests/component/test_telegram_safe_llm_guard.sh`

**Test Status:**

- [x] Test created
- [x] Test reproduces stale create failure contamination in sparse Telegram create history
- [x] Fix applied
- [x] Test passes
