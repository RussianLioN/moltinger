---
title: "Telegram skill-detail regressed after removing direct fastpath and relying on a single in-band hook path"
date: 2026-04-02
tags: [telegram, moltis, hooks, skills, activity-log, rca]
root_cause: "Commit `adb00b0` removed the Bot API direct fastpath for Telegram skill-detail requests and assumed the remaining single in-band hook path (`BeforeLLMCall` hard override plus downstream rewrites) was sufficient. In live Moltis 0.10.18 Telegram runtime, that assumption was false: the project hook was registered and the handler itself still produced the correct deterministic reply when invoked manually inside the container, but the live chat turn still fell through to the model/tool loop, executed `exec sed .../telegram-learner/SKILL.md`, and leaked the generic fallback plus Activity log. The reliable delivery mechanism for this intent therefore remains the direct Bot API fastpath with same-turn suppression, not the in-band-only path."
---

# RCA: Telegram skill-detail regressed after removing direct fastpath and relying on a single in-band hook path

## Ошибка

После коммита `adb00b0` вопрос пользователя вида:

- `Расскажи мне про навык telegram-lerner`

снова начал в проде:

- уходить в LLM/tool path;
- вызывать `exec sed -n '1,220p' /home/moltis/.moltis/skills/telegram-learner/SKILL.md`;
- падать с `missing 'command' parameter`;
- возвращать fallback про «не получилось прочитать `SKILL.md`»;
- дописывать `Activity log`.

## Проверка прошлых уроков

Проверены:

- [docs/rca/2026-04-02-telegram-skill-detail-fell-back-to-tool-error-leak.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-02-telegram-skill-detail-fell-back-to-tool-error-leak.md)
- [docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md)
- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag skills`

Что уже было известно:

1. Live Telegram runtime Moltis 0.10.18 ненадёжно уважает чисто hook-based in-band modify path.
2. Для user-facing Telegram сценариев уже приходилось использовать deterministic direct Bot API fastpath с same-turn suppression.
3. Для skill-detail ранее уже понадобился deterministic runtime summary из `SKILL.md`, а не best-effort tool probing модели.

Что оказалось новым:

1. Коммит `adb00b0` удалил direct fastpath именно для `skill_detail`.
2. Локальные тесты были переписаны так, будто single in-band path достаточно.
3. Прод это опроверг: handler сам по себе исправен, но live Telegram turn всё равно не прожимает нужный modify contract.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---------|--------|-------|
| 1 | Почему пользователь снова увидел fallback и `Activity log`? | Потому что turn дошёл до LLM/tool loop и выполнил `exec` вместо deterministic skill-detail ответа. |
| 2 | Почему deterministic ответ не был доставлен? | Потому что для `skill_detail` был удалён direct Bot API fastpath, а оставшийся single in-band path в live Telegram runtime не сработал надёжно. |
| 3 | Почему это считалось безопасным изменением? | Потому что локальные regression tests были переписаны под гипотезу «одного in-band path достаточно», и они перестали требовать direct send/suppression marker. |
| 4 | Почему это не было просто deploy drift? | Потому что сервер и текущая ветка были на одном и том же коммите `adb00b0`. |
| 5 | Почему это не было поломкой самого handler script? | Потому что тот же runtime handler, вызванный вручную внутри контейнера с live-подобным payload, вернул правильный deterministic skill-detail hard override. |

## Корневая причина

Корневая причина была в ложном архитектурном упрощении.

`adb00b0` исходил из предположения, что для `skill_detail` можно убрать direct Bot API fastpath и оставить только один «чистый» in-band delivery route:

- `BeforeLLMCall` hard override;
- `AfterLLMCall` rewrite;
- `MessageSending` rewrite.

На практике live Moltis 0.10.18 Telegram runtime этот контракт снова не подтвердил:

1. project hook был зарегистрирован;
2. runtime handler существовал и работал корректно при ручном вызове внутри контейнера;
3. но реальный Telegram turn всё равно пошёл в `exec` tool path и дошёл до user-visible fallback.

То есть проблема была не в отсутствии deterministic summary и не в несуществующем `SKILL.md`. Проблема была именно в выборе ненадёжного delivery path для этого intent.

## Доказательства

1. Локальный репозиторий и сервер были на одном и том же коммите:
   - `adb00b0`
2. Серверные логи на проблемном turn показали:
   - `chat.send ... user_message=Расскажи мне про навык telegram-lerner`
   - `executing tool ... tool=exec ... sed -n '1,220p' /home/moltis/.moltis/skills/telegram-learner/SKILL.md`
   - `tool execution failed ... missing 'command' parameter`
   - финальный fallback про сломанный вызов инструмента
3. `moltis hooks list --json` внутри live runtime показал project hook:
   - `telegram-safe-llm-guard`
   - `source: "project"`
   - `path: /home/moltis/.moltis/.moltis/hooks/telegram-safe-llm-guard`
4. Ручной вызов runtime handler inside-container с live-подобным `BeforeLLMCall` payload вернул корректный deterministic skill-detail ответ про `telegram-learner`.

## Исправление

Сделано:

1. Возвращён direct Bot API fastpath для `skill_detail` в `BeforeLLMCall`.
2. После direct send снова ставится same-turn suppression marker:
   - `skill_detail:<slug>`
3. Локальные regression tests возвращены к реальному live contract:
   - `skill_detail` должен direct-send'иться;
   - должен оставаться suppression marker;
   - stdout/stderr handler path должны оставаться пустыми;
   - текст ответа должен идти из runtime `SKILL.md`.

## Проверка

- `bash -n scripts/telegram-safe-llm-guard.sh`
- `bash -n tests/component/test_telegram_safe_llm_guard.sh`
- `bash tests/component/test_telegram_safe_llm_guard.sh`
- `bash tests/component/test_telegram_remote_uat_contract.sh`

## Уроки

1. Для Telegram-safe `skill_detail` direct Bot API fastpath остаётся не оптимизацией, а runtime reliability contract.
2. Нельзя переписывать regression tests от live-proven delivery path к «более красивой» архитектуре без нового live proof.
3. Если handler вручную внутри контейнера работает, а live turn нет, это признак не script-bug, а runtime delivery contract gap.
4. Для таких сценариев single-path simplification допустим только тогда, когда именно этот path подтверждён live Telegram UAT, а не только unit/component тестами.
