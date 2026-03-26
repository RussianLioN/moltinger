---
title: "Moltis Telegram kept stale session-level model/context after OAuth recovery and continued to emit misleading status replies"
date: 2026-03-21
severity: P1
category: process
tags: [moltis, telegram, session-state, model-routing, context-drift, oauth, rca]
root_cause: "After provider recovery, the active Telegram-bound session still carried an old session model and contaminated tool context, but the recovery path did not explicitly reconcile/reset that channel session."
---

# RCA: Moltis Telegram kept stale session-level model/context after OAuth recovery and continued to emit misleading status replies

**Дата:** 2026-03-21  
**Статус:** Resolved  
**Влияние:** После восстановления `openai-codex` в runtime Telegram-путь всё ещё давал неверные пользовательские ответы: `/status` сообщал `zai::glm-5`, а затем authoritative UAT мог видеть reply вида `Activity log • nodes_list • sessions_list • cron`, хотя сама OAuth уже была исправна.

## Ошибка

Runtime-auth и provider catalog уже были восстановлены, но Telegram active session для чата `262872984` продолжала жить со stale session state:

- `sessions.list` показывал `activeChannel=true` для `session:a59b6137-6531-4046-91c2-f7ee13a3c9da`
- эта сессия была на `openai-codex::gpt-5.3-codex-spark`, а не на canonical `openai-codex::gpt-5.4`
- `sessions.preview` подтверждал, что `/status` был сгенерирован провайдером `openai-codex`, но сам текст ответа утверждал `модель: zai::glm-5`
- позднее authoritative Telegram UAT получил reply `Activity log • nodes_list • sessions_list • cron`, то есть сессия уже тащила за собой загрязнённый tool/error context

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему Telegram продолжал отвечать некорректно после восстановления OAuth? | Потому что отвечал не свежий runtime baseline, а уже существующая channel-bound session с собственным сохранённым model/context state. | `sessions.list`: активная channel session `session:a59b...` для `chat_id=262872984`. |
| 2 | Почему эта session state осталась неверной? | Потому что session-level модель была закреплена на `openai-codex::gpt-5.3-codex-spark`, а не на canonical `openai-codex::gpt-5.4`. | `sessions.list` / `sessions.patch key-only` до фикса показывали `model="openai-codex::gpt-5.3-codex-spark"`. |
| 3 | Почему пользователь видел `zai::glm-5`, хотя сам ответ шёл через `openai-codex`? | Потому что сессия несла старый conversational/tool context, и модель опиралась на него при генерации `/status`, а не на актуальный session contract. | `sessions.preview`: assistant message с `provider="openai-codex"` и `model="openai-codex::gpt-5.3-codex-spark"` содержал текст `модель: zai::glm-5`. |
| 4 | Почему после patch на `gpt-5.4` reply всё ещё мог быть плохим? | Потому что кроме неверной model selection в active session уже накопился tool/error контекст (`sessions_list`, `nodes_list`, `cron` без `action`), который продолжал протекать в новые ответы. | authoritative run `20260321T210206Z-684954`: reply `Activity log • nodes_list • sessions_list • cron`. |
| 5 | Почему этот хвост не был частью стандартного recovery path? | Потому что recovery path был сосредоточен на provider/runtime mounts, но не содержал обязательного шага reconcile/reset для активной Telegram channel session после provider recovery. | Предыдущий runbook фиксировал runtime recovery, но не session repair для Telegram-bound channel state. |

## Корневая причина

После восстановления provider/runtime слоя активная Telegram channel session осталась на старом session-level model/context состоянии. Recovery process возвращал `openai-codex` в runtime, но не выравнивал и не очищал именно ту channel-bound session, через которую продолжал общаться Telegram.

## Принятые меры

1. **Session model repair:**
   - `sessions.patch` для active Telegram session:
     - `key = session:a59b6137-6531-4046-91c2-f7ee13a3c9da`
     - `model = openai-codex::gpt-5.4`
2. **Session context cleanup:**
   - `sessions.reset` для той же active session, чтобы убрать загрязнённый tool/error context.
3. **UAT hardening:**
   - `scripts/telegram-web-user-probe.mjs` теперь классифицирует replies, начинающиеся с `Activity log ...`, и tool-error summaries вроде `missing 'action' parameter` как error signatures, а не как валидный ответ.
   - Добавлен regression test в `tests/component/test_telegram_web_probe_correlation.sh`.

## Подтверждение устранения

- До reset:
  - authoritative run `20260321T210206Z-684954` matched reply:
    - `Activity log • nodes_list • sessions_list • cron`
- После patch + reset:
  - `sessions.list` показывал active Telegram session на `openai-codex::gpt-5.4`
  - authoritative run `20260321T210324Z-686381` matched reply:
    - `... Модель: openai-codex::gpt-5.4 ...`

## Уроки

1. **Provider recovery ≠ channel-session recovery**: после ремонта OAuth/provider слоя нужно отдельно проверять активную channel-bound session.
2. **Session-level model state имеет приоритет над операторскими ожиданиями**: если чат живёт на старой session model, пользователь будет видеть старое поведение даже при исправном runtime.
3. **Reply-quality gate должен ловить tool-trace summaries**, а не только generic timeouts и `model not found`.
