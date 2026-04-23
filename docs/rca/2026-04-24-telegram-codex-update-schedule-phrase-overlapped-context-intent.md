---
title: "Telegram codex-update schedule phrasing overlapped context intent in guard and authoritative UAT"
date: 2026-04-24
severity: P1
category: product
tags: [telegram, codex-update, scheduler, context, uat, hooks, rca]
root_cause: "The exact user phrasing `По какому расписанию сейчас работает навык codex-update?` matched both the scheduler and context classifiers. In the Telegram-safe guard, context won and produced the wrong reply family. In the authoritative UAT wrapper, the same overlap made a valid scheduler reply fail local classification. Both layers encoded the same ambiguity differently, so live behavior and local verification drifted apart."
---

# RCA: Telegram codex-update schedule phrasing overlapped context intent in guard and authoritative UAT

Date: 2026-04-24
Status: Fixed in source, covered by regression tests, pending live redeploy verification
Context: live Telegram dialogue validation for `codex-update`

## Error

Во время живой проверки вопрос:

```text
По какому расписанию сейчас работает навык codex-update?
```

не дал scheduler-ответ. Бот вернул context/deduplication reply family:

```text
Раньше повторные сообщения про Codex CLI появлялись из-за дефекта старого контура дедупликации...
```

Это был неверный user-facing contract: пользователь спрашивал про расписание/cron path, а получил объяснение про дедупликацию и текущее состояние.

Параллельно локальный authoritative UAT wrapper не считал эту же формулировку чисто scheduler-вопросом: exact phrase одновременно проходила и в scheduler, и в context taxonomy.

## Lessons Pre-check

Перед фиксом были перечитаны:

- `docs/rca/2026-04-24-telegram-codex-update-scheduler-question-drifted-into-skill-detail-and-uat-false-pass.md`
- `docs/rca/2026-04-23-telegram-direct-fastpath-before-llm-must-block.md`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Главный вывод из предыдущих RCA подтвердился снова:
- intent taxonomy в Telegram-safe lane и taxonomy в authoritative UAT должны быть синхронизированы по одним и тем же phrasing families;
- иначе production и local verification начинают расходиться.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Почему бот ответил не про расписание? | Потому что guard отнёс exact phrase к `codex_update_context`, а не к `codex_update_scheduler`. |
| 2 | Почему phrase попала в `context`? | Потому что context regex ловил широкое `как/каким образом ... сейчас работает`, а вопрос про расписание тоже содержал `какому ... сейчас работает`. |
| 3 | Почему scheduler intent не защитил turn? | Потому что context branch исполнялся позже и вручную сбрасывал `current_turn_codex_update_scheduler_request=false`. |
| 4 | Почему локальный authoritative UAT не давал симметричную картину? | Потому что в wrapper exact phrase тоже одновременно подходила под scheduler и context families. |
| 5 | Почему это опасно? | Потому что один и тот же user prompt мог вести к разным выводам в runtime и в UAT harness, а значит regressions могли либо не ловиться, либо ловиться не тем слоем. |

## Root Cause

Корневая причина состояла из двух связанных overlap-ошибок:

1. `scripts/telegram-safe-llm-guard.sh` имел слишком широкий context matcher для `codex-update`, который не уважал уже распознанный scheduler intent.
2. `scripts/telegram-e2e-on-demand.sh` имел такой же semantic overlap: schedule phrasing проходил в `message_is_codex_update_context_query()` даже когда уже являлся scheduler-вопросом.

Иначе говоря, проблема была не в тексте ответа как таковом, а в самой intent taxonomy. Guard и UAT helper по-разному, но одинаково неправильно понимали одну и ту же фразу пользователя.

## Fixes Applied

1. `scripts/telegram-safe-llm-guard.sh`
   - context branch теперь не может перетереть уже распознанный `codex_update_scheduler` turn;
   - добавлен `determine_effective_codex_update_reply_mode()`, чтобы current scheduler turn имел приоритет над stale persisted context intent.
2. `scripts/telegram-e2e-on-demand.sh`
   - `message_is_codex_update_context_query()` теперь явно исключает scheduler-вопросы;
   - local authoritative taxonomy синхронизирована с production guard.
3. `tests/component/test_telegram_safe_llm_guard.sh`
   - добавлен regression на exact live phrase `По какому расписанию сейчас работает навык codex-update?`;
   - добавлен regression на stale persisted `codex_update_context`, который больше не должен ломать текущий scheduler turn.
4. `tests/component/test_telegram_remote_uat_contract.sh`
   - добавлен pass regression на exact phrase для scheduler contract;
   - добавлен fail regression, если exact phrase уходит в context reply family.

## Verification

Подтверждено локально:

- `bash -n scripts/telegram-safe-llm-guard.sh`
- `bash -n scripts/telegram-e2e-on-demand.sh`
- `bash tests/component/test_telegram_safe_llm_guard.sh` -> `154/154`
- `bash tests/component/test_telegram_remote_uat_contract.sh` -> `61/61`

## Prevention

1. Exact user phrasings с пересечением слов `как`, `каким`, `работает`, `расписание` нельзя покрывать только широкими regex families без приоритетов.
2. Для Telegram-safe intent routing узкие domain-specific branches (`scheduler`, `maintenance`, `state`) должны побеждать более общие explanatory/context branches.
3. Любой live-found phrasing bug нужно добавлять и в production guard, и в authoritative UAT taxonomy одним пакетом, иначе verification снова разойдётся с runtime.
