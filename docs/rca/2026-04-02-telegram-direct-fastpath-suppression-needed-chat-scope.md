---
title: "Telegram direct fastpath suppression needed chat scope because live runtime drifted session identity"
date: 2026-04-02
tags: [telegram, moltis, hooks, skills, delivery, activity-log, rca]
root_cause: "The repo guard persisted same-turn direct-fastpath suppression only by `session_key/session_id`, but live Telegram delivery continued the already answered turn under a different runtime session identity while still targeting the same Telegram chat. Because the late `AfterLLMCall`/`MessageSending` tail no longer matched the original session-scoped marker, the dirty fallback escaped to the user after the clean direct fastpath answer. The repo-side fix was to persist and clear suppression by both session scope and chat scope."
---

# RCA: Telegram direct fastpath suppression needed chat scope because live runtime drifted session identity

## Ошибка

После уже успешного direct fastpath ответа на:

- `Расскажи мне про навык telegram-lerner`

пользователь всё ещё мог получить поздний грязный хвост:

- повторный ответ;
- fallback про сломанный инструмент;
- `Activity log`;
- `missing 'command' parameter`;
- упоминания `SKILL.md` и внутренних tool-вызовов.

## Проверка прошлых уроков

Проверены:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag hooks`
- [docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md)
- [docs/rca/2026-04-02-telegram-skill-detail-single-inband-path-regressed-live-runtime.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-02-telegram-skill-detail-single-inband-path-regressed-live-runtime.md)

Что уже было известно:

1. Live Telegram runtime Moltis/OpenClaw не даёт считать synthetic hook-contract полным доказательством user-facing delivery.
2. Same-turn suppression должна переживать поздние хвосты после direct fastpath.
3. `skill_detail` уже требовал deterministic runtime summary, а не best-effort tool probing.

Что оказалось новым:

1. Даже после возврата `skill_detail` direct fastpath live dirty tail не исчез полностью.
2. Локальные component tests для same-session path были зелёными, но live symptom всё ещё воспроизводился.
3. Проблема оказалась не только в «tail not terminal», а ещё и в слишком узкой идентичности suppression-marker.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---------|--------|-------|
| 1 | Почему после уже отправленного clean skill-detail ответа пользователь всё ещё видел грязный tail? | Потому что поздняя фаза того же Telegram turn не увидела активный suppression-marker. |
| 2 | Почему suppression-marker не был найден? | Потому что он сохранялся только по `session_key/session_id`. |
| 3 | Почему этого оказалось недостаточно? | Потому что live runtime продолжал тот же user-facing turn уже под другой session identity, но всё ещё в том же Telegram chat. |
| 4 | Почему это не поймали предыдущие tests? | Потому что regression tests покрывали same-session happy path, а не late tail с другим `session_key` и тем же `chat_id`. |
| 5 | Почему архитектура оказалась хрупкой? | Потому что delivery был привязан к Telegram chat, а suppression — только к runtime session; эти две идентичности были разведены. |

## Корневая причина

Repo guard моделировал direct-fastpath suppression слишком узко: только как session-scoped marker.

В реальном Telegram runtime пользовательский turn уже был отвечен через direct send в конкретный `chat_id`, но поздние `AfterLLMCall`/`MessageSending` хвосты могли прийти с другой session identity. Из-за этого clean direct-fastpath ответ и late dirty suppression жили в разных namespace'ах:

- direct delivery был chat-scoped;
- suppression был session-scoped.

Когда live runtime drift-ил `session_key/session_id`, поздний dirty tail больше не сопоставлялся с исходным marker и протекал в чат.

## Доказательства

1. Live deploy содержал правильный `skill_detail` direct fastpath, а `telegram-learner` реально существовал в runtime path внутри контейнера.
2. Authoritative/live-safe UAT мог увидеть ранний clean reply, но container audit для того же turn всё равно показывал:
   - `exec ... /home/moltis/.moltis/skills/telegram-learner/SKILL.md`
   - `tool execution failed`
   - поздний user-visible dirty outbound tail.
3. Локальные same-session tests уже были зелёными, что исключало простую script-syntax ошибку.
4. Новый regression-case с chat-scoped marker и другим `session_id` воспроизвёл live pattern и подтвердил, что chat-scoped suppression закрывает дыру.

## Исправление

Сделано:

1. Добавлен второй suppression namespace: chat-scoped marker на основе Telegram `chat_id`.
2. Direct fastpath теперь сохраняет suppression в оба scope:
   - session-scoped;
   - chat-scoped.
3. `BeforeToolCall`, `AfterLLMCall` и `MessageSending` теперь используют эффективный suppression-token:
   - сначала session-scoped;
   - затем chat-scoped fallback.
4. На новом user turn `BeforeLLMCall` очищает не только session-scoped, но и chat-scoped suppression, чтобы не заглушить следующую нормальную реплику в том же чате.
5. Добавлены regression tests на live-like drift:
   - dirty `MessageSending` tail при новом `session_id`, но том же `chat_id`;
   - late `AfterLLMCall` при новом `session_key`, но том же `chat_id`;
   - очистка chat-scoped suppression на новом user turn.

## Проверка

- `bash -n scripts/telegram-safe-llm-guard.sh`
- `git diff --check`
- `bash tests/component/test_telegram_safe_llm_guard.sh`
- `bash tests/component/test_telegram_remote_uat_contract.sh`

## Уроки

1. Для Telegram direct fastpath suppression должна следовать той же delivery identity, что и сам ответ, а не только runtime session identity.
2. Same-session component green не доказывает отсутствие late tail при live session drift.
3. Для user-facing Telegram reliability tests нужно отдельно покрывать кейс `same chat, different session key`.
