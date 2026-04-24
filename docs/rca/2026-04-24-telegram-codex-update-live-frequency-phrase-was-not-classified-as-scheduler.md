---
title: "Telegram codex-update live frequency phrase was not classified as scheduler"
date: 2026-04-24
severity: P1
category: product
tags: [telegram, codex-update, scheduler, frequency, uat, rca]
root_cause: "Both the Telegram-safe guard and the authoritative Telegram UAT wrapper only recognized explicit schedule words like cron/scheduler/расписание. A natural user phrasing like `Как часто обновляется навык codex-update?` missed the scheduler branch, fell through to generic codex-update handling, and the authoritative wrapper false-passed because it used the same narrow question classifier."
---

# RCA: Telegram codex-update live frequency phrase was not classified as scheduler

Date: 2026-04-24
Status: Fixed in source and covered by regression tests
Context: live Telegram dialogue validation for `codex-update`

## Error

Во время user-like проверки вопрос:

```text
Как часто обновляется навык codex-update?
```

не попал в scheduler-ветку. В live Telegram бот отвечал generic skill-detail family:

```text
codex-update — показывает, есть ли новая стабильная версия Codex CLI...
```

При этом authoritative Telegram UAT тоже возвращал `passed`, хотя ответ был не по контракту.

## Lessons Pre-check

Перед фиксом были перечитаны:

- `docs/rca/2026-04-24-telegram-codex-update-scheduler-question-drifted-into-skill-detail-and-uat-false-pass.md`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Вывод из pre-check:

1. intent matcher в Telegram-safe lane сам является частью user-facing контракта;
2. authoritative UAT бесполезен, если использует ту же слепую taxономию, что и runtime;
3. для scheduler-вопросов нужен не только negative leak detector, но и positive contract match.

## Root Cause

Корневая причина была двойной, но одинаковой по смыслу:

1. `scripts/telegram-safe-llm-guard.sh` распознавал scheduler intent только по явным токенам вроде `cron`, `scheduler`, `расписание`, `каждые`, `автопроверка`.
2. `scripts/telegram-e2e-on-demand.sh` использовал почти тот же narrow matcher для определения, что вопрос вообще относится к scheduler contract.

Из-за этого phrasing `Как часто обновляется навык codex-update?`:

- не считался scheduler-вопросом;
- уходил в generic codex-update family;
- не активировал authoritative scheduler-contract validation;
- давал ложнозелёный live UAT.

## Fixes Applied

1. `scripts/telegram-safe-llm-guard.sh`
   - scheduler matcher расширен под natural frequency phrasing:
     - `как часто ... обновля...`
     - `с какой периодичностью ...`
   - deterministic scheduler reply теперь явно называет интервал:
     - `каждые 6 часов`
2. `scripts/telegram-e2e-on-demand.sh`
   - authoritative scheduler question matcher синхронизирован с runtime matcher;
   - positive scheduler contract усилен: safe reply теперь обязан содержать explicit frequency (`каждые 6 часов`) плюс runtime boundary.
3. `tests/component/test_telegram_safe_llm_guard.sh`
   - добавлен regression на exact live phrase:
     - `Как часто обновляется навык codex-update?`
4. `tests/component/test_telegram_remote_uat_contract.sh`
   - добавлены positive и negative regression tests на ту же exact live phrase;
   - обновлены safe scheduler fixtures под strengthened contract.

## Verification

Подтверждено локально:

- `bash -n scripts/telegram-safe-llm-guard.sh`
- `bash -n scripts/telegram-e2e-on-demand.sh`
- `bash tests/component/test_telegram_safe_llm_guard.sh` -> `165/165`
- `bash tests/component/test_telegram_remote_uat_contract.sh` -> `67/67`

## Prevention

1. Для Telegram user prompts нужно покрывать не только canonical phrasing (`по какому расписанию`), но и естественные frequency-формулировки (`как часто`, `с какой периодичностью`).
2. Authoritative UAT не должен разделять с runtime один и тот же незамеченный blind spot без positive contract checks.
3. Если route отвечает на вопрос о расписании, ответ должен содержать сам интервал, а не только абстрактное упоминание scheduler path.
