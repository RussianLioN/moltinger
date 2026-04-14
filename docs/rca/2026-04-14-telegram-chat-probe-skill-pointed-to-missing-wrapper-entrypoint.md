---
title: "Telegram chat probe skill pointed to a missing wrapper entrypoint"
date: 2026-04-14
severity: P1
category: process
tags: [telegram, skills, wrapper, helper-contract, probe, rca]
root_cause: "The repo-managed `telegram-chat-probe` skill declared `scripts/telegram-chat-probe.sh` as its one-command entrypoint, but the wrapper was absent from the tracked scripts surface and had no regression guard in the manifest or tests."
---

# RCA: Telegram chat probe skill pointed to a missing wrapper entrypoint

Date: 2026-04-14  
Status: Resolved  
Context: beads `moltinger-2b2s`, post-deploy live verification of Moltis Telegram behavior

## Error

Во время повторной live-проверки Moltis после production deploy skill `telegram-chat-probe` оказался unusable:

```text
zsh:1: no such file or directory: scripts/telegram-chat-probe.sh
```

Это заблокировало sanctioned one-command path для real_user Telegram probe и вынудило остановить продуктовую проверку до починки repo-owned helper contract.

## Lessons Pre-check

Перед фиксом были проверены lessons и связанные правила:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag skills`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Релевантные прошлые уроки:

1. `2026-04-09-skill-execution-and-reporting-contract-drift.md`  
   repo-managed skill/helper path нужно чинить в owning layer, а не обходить вручную.
2. `2026-03-28-moltis-repo-skill-sync-trap-broke-deploy-verification.md`  
   verification helpers тоже являются контрактом и требуют blocking regression coverage.

Что эти уроки уже покрывали:

- abnormal helper behavior надо переводить в RCA/root-fix mode;
- verification path нельзя считать "второстепенным" только потому, что он не user-facing.

Что оставалось непокрытым:

- отдельный guard, что `telegram-chat-probe` skill ссылается на реально существующий wrapper entrypoint;
- runtime-тест на mapping wrapper-а при `precondition_failed`, `timeout` и `upstream_failed`.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Почему live Telegram probe остановился? | Потому что skill запускал `scripts/telegram-chat-probe.sh`, а такого файла в repo не было. |
| 2 | Почему отсутствующий wrapper не был замечен раньше? | Потому что не было ни manifest entry, ни static/runtime regression test на этот entrypoint contract. |
| 3 | Почему skill мог ссылаться на несуществующий script? | Потому что contract skill-а и tracked scripts surface разошлись: underlying Python helper существовал, а compatibility wrapper не был материализован. |
| 4 | Почему drift дошёл до использования в живой сессии? | Потому что verification path опирался на документацию skill-а, но не имел автоматической проверки "skill path -> executable wrapper -> upstream helper". |
| 5 | Почему это стало системной проблемой, а не единичной опечаткой? | Потому что wrapper compatibility layer была не оформлена как first-class repo contract с manifest coverage и unit mapping tests. |

## Root Cause

Repo-managed `telegram-chat-probe` skill обещал one-command shell entrypoint `scripts/telegram-chat-probe.sh`, но этот wrapper не существовал в tracked scripts surface.  
Underlying helper `scripts/telegram-user-probe.py` был на месте, однако compatibility layer между skill contract и helper implementation не была закреплена как versioned script с manifest entry и regression coverage.

## Fixes Applied

1. Добавлен новый tracked wrapper:
   - `scripts/telegram-chat-probe.sh`
   - wrapper транслирует skill contract в `scripts/telegram-user-probe.py`
   - сохраняет агрегированный JSON contract для `completed`, `timeout`, `precondition_failed`, `upstream_failed`
2. Обновлён `scripts/manifest.json`, чтобы wrapper стал частью проверяемого scripts surface.
3. Усилен static guard в `tests/static/test_config_validation.sh`, чтобы skill не мог снова ссылаться на несуществующий wrapper.
4. Добавлен unit test `tests/unit/test_telegram_chat_probe_wrapper.sh` на runtime mapping wrapper-а:
   - missing env -> `precondition_failed`
   - upstream success -> `completed`
   - helper timeout -> `timeout`
   - helper failure / invalid JSON -> `upstream_failed`

## Prevention

1. Skill entrypoint contract должен существовать как tracked executable script, а не только как текст в `SKILL.md`.
2. Compatibility wrapper для user/test workflows нужно хранить в `scripts/manifest.json`, иначе drift между skill doc и repo surface остаётся невидимым.
3. Для verification helpers нужна не только static existence check, но и runtime unit coverage на output contract.

## Уроки

1. Если skill обещает one-command path, wrapper entrypoint является частью public repo contract.
2. Наличие underlying helper-а не спасает, если compatibility layer между skill и helper не материализована.
3. Verification tooling требует тех же fail-closed guard-ов, что и deploy/runtime helpers.
