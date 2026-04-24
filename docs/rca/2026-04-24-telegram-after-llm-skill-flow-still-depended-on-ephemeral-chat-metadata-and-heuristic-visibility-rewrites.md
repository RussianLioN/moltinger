---
title: "Telegram AfterLLM skill flow still depended on ephemeral chat metadata and heuristic visibility rewrites"
date: 2026-04-24
severity: P1
category: product
tags: [telegram, skills, hooks, runtime, after-llm, chat-id, visibility, rca]
root_cause: "The repo-owned AfterLLM skill path still relied on upstream payload metadata and heuristic text checks instead of persisting the Telegram chat_id per session and canonicalizing skill visibility replies from runtime truth."
---

# RCA: Telegram AfterLLM skill flow still depended on ephemeral chat metadata and heuristic visibility rewrites

**Дата:** 2026-04-24
**Статус:** Resolved
**Влияние:** Live Telegram skill CRUD мог снова срываться на позднем `AfterLLMCall`, хотя tool call уже был корректным: deterministic repo-owned path не мог отправить финальный ответ пользователю из-за потерянного `chat_id`. Параллельно skill visibility всё ещё мог показать внутренний/чужой инвентарь навыков, если модель случайно упоминала хотя бы одно настоящее runtime-имя.
**Контекст:** `scripts/telegram-safe-llm-guard.sh`, authoritative Telegram Remote UAT, production hook captures, user-facing Telegram skill CRUD / skill visibility flows.

## Ошибка

После предыдущих ремонтов было видно, что:

- `create_skill`/`update_skill`/`delete_skill` уже исполняются в repo-owned direct CRUD path, а не через старый broken tool boundary;
- `skill visibility` уже имел deterministic runtime snapshot;
- локальные component tests на canonical payload shape проходили.

Но live evidence показал ещё два остаточных разрыва:

1. `AfterLLMCall` на production иногда приходил без `channel_chat_id` и вообще без chat metadata, хотя на более раннем hook phase этот `chat_id` уже был известен.
2. Final rewrite для `skill visibility` всё ещё был завязан на эвристику `reply mentions any runtime skill`, поэтому overbroad reply с частично правильными именами мог пройти мимо deterministic canonicalization.

Итог: root-owned execution path уже существовал, но всё ещё опирался на неавторитетные свойства upstream payload.

## Проверка прошлых уроков

Перед фиксом были повторно проверены:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag skills`
- `docs/rca/2026-04-24-telegram-tool-call-name-extraction-depended-on-json-field-order.md`
- `docs/rca/2026-04-24-telegram-sparse-create-recovery-needed-persisted-crud-intent.md`
- `docs/rca/2026-04-24-telegram-skill-crud-before-tool-modify-was-not-authoritative.md`

Релевантные уже закреплённые уроки:

1. Для Telegram-safe critical paths нужно считать upstream hook payload shape нестабильным между фазами.
2. Если repo уже владеет deterministic recovery, ему нужен собственный persisted execution context, а не повторная надежда на поля следующего payload.
3. Skill visibility нельзя считать исправленным, пока ответ полностью опирается на runtime truth, а не на частичное совпадение текста модели с реальными skill names.

Что было новым:

- persisted CRUD context уже хранил intent и slug, но не хранил последний известный `chat_id` для позднего direct send;
- visibility finalization была недостаточно строгой именно на поздних фазах delivery: хороший partial overlap с runtime names скрывал реальный leak лишних skill names.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---|---|---|---|
| 1 | Почему live Telegram create/update/delete всё ещё могли заканчиваться плохим user-facing результатом? | Потому что `AfterLLMCall` direct CRUD branch иногда не мог отправить clean summary пользователю. | Hermetic replay of the live capture showed `attempt_direct_skill_crud_after_llm_fastpath` returning early on empty `telegram_chat_id`. |
| 2 | Почему `telegram_chat_id` оказывался пустым, хотя раньше он был известен? | Потому что поздний live `AfterLLMCall` payload мог не содержать `channel_chat_id`, `to`, или других Telegram chat fields. | Production hook capture and bash-trace replay of the saved payload showed only datetime/system content without chat metadata. |
| 3 | Почему repo-owned path не восстановил этот `chat_id` из собственного состояния? | Потому что в session-owned persistence были `intent`, suppression и terminal markers, но не было persisted session chat binding. | `scripts/telegram-safe-llm-guard.sh` before fix had `.intent`, `.suppress`, `.terminal`, but no `.chat` sidecar. |
| 4 | Почему skill visibility leak тоже оставался возможным после прошлых fixes? | Потому что final rewrite срабатывал только при false-negative/generic mismatch или полном отсутствии runtime skill names в reply. | Existing branch logic skipped override when model reply mentioned any one runtime skill, even if the rest of the inventory was overbroad or internal. |
| 5 | Какой source fix был нужен на самом деле? | Нужно было сделать skill-flow fully repo-owned: persist/restore last known session `chat_id` for late direct sends and canonicalize skill visibility by comparing against exact runtime-derived final text instead of heuristic overlap. | New fix adds session-scoped `.chat` persistence, restores `current_chat_id` when live payload is sparse, and rewrites visibility whenever the final text deviates from the canonical runtime snapshot reply. |

## Корневая причина

Repo-owned Telegram skill flow был доведён только наполовину.

Архитектура уже перенесла critical skill CRUD logic в deterministic `AfterLLMCall` layer, но сама эта ветка всё ещё зависела от ephemeral upstream chat metadata, которого live runtime не обязан сохранять до поздней фазы. Одновременно `skill visibility` ещё доверял частичному semantic overlap текста модели, вместо того чтобы жёстко опираться на exact canonical runtime reply.

Иными словами: determinism был заявлен, но execution context и final output canonicalization оставались неполностью repo-owned.

## Принятые меры

1. Добавлен session-scoped persisted `chat_id` sidecar:
   - `chat_id` сохраняется по `session_key`, когда он известен;
   - поздние фазы могут восстановить его, если live payload уже sparse.
2. `AfterLLMCall` direct skill CRUD теперь использует restored session `chat_id`, а не только текущий payload.
3. `BeforeLLMCall` fastpath тоже использует `current_chat_id` fallback, если `system_chat_id` отсутствует.
4. `skill visibility` final rewrite tightened:
   - старый retired create intent всё ещё чистится на follow-up;
   - rewrite происходит whenever final reply deviates from the exact runtime-derived canonical visibility text;
   - уже корректный canonical final reply не переписывается повторно.
5. Добавлены новые component regressions:
   - live-shaped `AfterLLMCall` direct skill CRUD payload without chat metadata;
   - overbroad skill visibility inventory that still mentions some real runtime skill names.

## Уроки

1. Если Telegram-safe turn требует late direct send, persisted execution context должен хранить не только intent/slug, но и routing metadata, без которого reply невозможно доставить.
2. Для user-visible skill visibility correctness нельзя использовать эвристику вида “модель назвала хоть один правильный навык”; нужен exact runtime-owned canonical reply.
3. Live payload sparsity и semantic overbreadth нужно покрывать отдельными regression fixtures, даже если canonical/local payloads уже проходят.

## Regression Test

**Test Files:** `tests/component/test_telegram_safe_llm_guard.sh`, `tests/component/test_telegram_remote_uat_contract.sh`

**Test Status:**

- [x] Live-shaped `AfterLLMCall` skill CRUD payload without chat metadata reproduced
- [x] Overbroad skill visibility inventory reproduced
- [x] Fix applied
- [x] Relevant component suites pass
