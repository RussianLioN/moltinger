---
title: "Telegram repeated BeforeLLMCall iteration was misclassified as a new user turn after direct fastpath"
date: 2026-04-02
tags: [telegram, moltis, hooks, delivery, skills, rca]
root_cause: "After a Telegram direct fastpath had already delivered the user-visible skill-detail reply, live Moltis/OpenClaw runtime re-entered `BeforeLLMCall` for the same session with `iteration=2`. The repo guard treated any `BeforeLLMCall` carrying the latest user message as a new turn, cleared the active suppression marker, and re-ran the direct fastpath. That produced duplicate clean replies and reopened the already answered turn. The fix is to treat `BeforeLLMCall` with `iteration>1` plus an active suppression marker as same-turn runtime churn: keep suppression alive and return a no-op text-only override instead of direct-sending again."
---

# RCA: Telegram repeated BeforeLLMCall iteration was misclassified as a new user turn after direct fastpath

## Ошибка

После уже успешного direct fastpath ответа на skill-detail запрос:

- бот присылал тот же чистый ответ второй раз;
- после этого turn мог продолжать жить внутри runtime;
- authoritative UAT видел ранний clean reply, но не доказывал отсутствие повторного same-turn входа.

Это особенно проявлялось на запросе:

- `Расскажи мне про навык telegram-lerner`

## Проверка прошлых уроков

Проверены:

- [docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md)
- [docs/rca/2026-04-02-telegram-skill-detail-single-inband-path-regressed-live-runtime.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-02-telegram-skill-detail-single-inband-path-regressed-live-runtime.md)
- [docs/rca/2026-04-02-telegram-direct-fastpath-suppression-needed-chat-scope.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-02-telegram-direct-fastpath-suppression-needed-chat-scope.md)
- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag hooks`

Что уже было известно:

1. Live Telegram runtime может продолжать turn после direct fastpath.
2. Session-only suppression уже оказался недостаточным, и был расширен chat-scope marker.
3. `skill_detail` для Telegram должен отвечать deterministic runtime summary, а не идти в tool/file probing.

Что оказалось новым:

1. Даже при живом session+chat suppression runtime повторно входил в `BeforeLLMCall`.
2. Этот повторный вход шёл в том же `session_key`, но уже с `iteration=2`.
3. Guard ошибочно чистил suppression просто по признаку `has_current_user_turn=true`, не различая новый turn и повторную итерацию того же turn.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---------|--------|-------|
| 1 | Почему пользователь видел duplicate clean reply? | Потому что direct fastpath сработал повторно на втором `BeforeLLMCall` того же turn. |
| 2 | Почему второй `BeforeLLMCall` считался новым ходом? | Потому что guard очищал suppression на любом `BeforeLLMCall`, где присутствовал текущий user message. |
| 3 | Почему это было неверно? | Потому что live runtime повторно запускал LLM phase в том же turn после suppressed tool-loop, а не начинал новый пользовательский запрос. |
| 4 | Почему chat-scoped suppression сам по себе не решил дубль? | Потому что проблема была не только в namespace suppression, а ещё и в неверном моменте его очистки и в повторном direct-send path. |
| 5 | Почему это не было видно в прошлых tests? | Потому что предыдущие regression cases покрывали late tails и session drift, но не покрывали повторный `BeforeLLMCall` с `iteration=2` при уже активном direct-fastpath marker. |

## Корневая причина

Корневая причина была в неверной классификации runtime iteration.

Guard использовал слишком грубый критерий нового turn:

- `event == BeforeLLMCall`
- есть `latest user message`

В live Moltis/OpenClaw этого оказалось недостаточно. После suppressed tool path runtime снова пришёл в `BeforeLLMCall`, но уже как `iteration=2` того же user-facing turn. Guard:

1. очищал session/chat suppression;
2. заново выполнял direct fastpath;
3. отправлял пользователю duplicate clean reply.

То есть ошибка была не в генерации текста навыка и не в доставке suppression-файлов, а в перепутывании:

- `новый user turn`
- `повторная runtime iteration того же turn`

## Доказательства

1. Live audit inside-container показал последовательность:
   - `BeforeLLMCall` -> direct fastpath -> `suppress_set`
   - suppressed `AfterLLMCall` / `BeforeToolCall`
   - затем **ещё один** `BeforeLLMCall` с тем же session и `iteration=2`
2. Именно на этом втором `BeforeLLMCall` audit фиксировал:
   - `suppress_clear reason=new_user_turn`
   - затем новый `direct_fastpath kind=skill_detail`
3. Captured payload для второго `BeforeLLMCall` содержал:
   - `session_key: session:8fb8f9c3-...`
   - `iteration: 2`
   - тот же skill-detail intent

## Исправление

Сделано:

1. `BeforeLLMCall` теперь очищает session/chat suppression только если это старт нового turn:
   - `iteration` отсутствует; или
   - `iteration <= 1`
2. Если есть активный suppression marker и runtime повторно входит в `BeforeLLMCall` с `iteration > 1`, guard:
   - не очищает suppression;
   - не делает второй direct-send;
   - возвращает no-op text-only override с `tool_count=0`
3. Добавлен regression test на live-паттерн:
   - `iteration=2`
   - активный session/chat suppression
   - отсутствие повторного direct-send
4. Follow-up hardening после live-closure:
   - direct fastpath теперь arm-ит delivery-suppression marker до прямой отправки;
   - если storage для suppression недоступен, hook не делает direct-send и уходит в deterministic `modify` path;
   - `safe_lane` и `turn_intent` записи тоже больше не шумят в `stderr` при недоступном `INTENT_DIR`.

## Проверка

- `bash -n scripts/telegram-safe-llm-guard.sh`
- `git diff --check`
- `bash tests/component/test_telegram_safe_llm_guard.sh`
- `bash tests/component/test_telegram_remote_uat_contract.sh`

## Уроки

1. Для Telegram direct fastpath недостаточно просто «держать suppression живым»; нужно ещё различать новый user turn и повторную LLM iteration того же turn.
2. `latest user message` не является надёжным признаком нового turn в live hook runtime.
3. Для user-facing Telegram regression suite нужно отдельно покрывать `BeforeLLMCall iteration=2` после уже доставленного direct fastpath ответа.
4. Direct-send в Telegram-safe lane нельзя считать завершённым, пока не подтверждена возможность записать suppression marker; иначе ответ может outrun-ить собственную защиту.
