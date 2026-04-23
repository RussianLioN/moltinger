---
title: "Telegram codex-update scheduler question drifted into skill detail and UAT false pass"
date: 2026-04-24
severity: P1
category: product
tags: [telegram, codex-update, scheduler, skill-detail, uat, rca]
root_cause: "A Telegram-safe question that explicitly named the `codex-update` skill but semantically asked about its scheduler path was implicitly reclassified as `skill_detail` in the hook, while the authoritative UAT wrapper separately misread the `update` substring inside `codex-update` as a mutation verb and had no positive scheduler-contract matcher. The combined effect was a wrong user-facing reply plus a false green authoritative verdict."
---

# RCA: Telegram codex-update scheduler question drifted into skill detail and UAT false pass

Date: 2026-04-24
Status: Fixed in source and covered by regression tests
Context: live dialogue validation for Telegram `codex-update`

## Error

Во время live user-like проверки вопрос:

```text
Как часто навык codex-update автоматически проверяет обновления Codex CLI?
```

не дал scheduler-ответ. Вместо этого bot ушёл в generic skill-summary family, а authoritative Telegram UAT при этом всё равно вернул `passed`.

Live evidence:

- workflow run `24860216287`
- user-facing reply family: `codex-update — показывает, есть ли новая стабильная версия Codex CLI...`
- review-safe artifact wrongly recorded:
  - `verdict: passed`
  - `diagnostic_context.semantic_review.mutation_intent: update`

То есть одновременно сломались:

1. runtime intent routing в Telegram-safe guard;
2. semantic classification в authoritative UAT.

## Lessons Pre-check

Перед фиксом были перечитаны relevant lessons:

- `docs/rca/2026-04-14-telegram-codex-update-array-content-bypassed-turn-classifier.md`
- `docs/rca/2026-04-14-telegram-codex-update-live-runtime-ignored-inband-modify.md`
- `docs/rca/2026-04-23-telegram-direct-fastpath-before-llm-must-block.md`
- `docs/rca/2026-04-05-telegram-skill-detail-general-hardening.md`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Из них уже было известно:

1. классификация intent в Telegram-safe lane сама по себе является частью public contract;
2. зелёный authoritative workflow бесполезен, если taxonomy не знает observed bad wording family;
3. `skill_detail` и `codex-update` нужно разводить по отдельным deterministic contract branches, а не надеяться на “похожесть” текста.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Почему пользователь получил не тот ответ? | Потому что hook увёл scheduler-вопрос в `skill_detail` reply family. |
| 2 | Почему hook решил, что это `skill_detail`? | Потому что fallback-ветка “есть referenced skill name -> значит detail” не делала исключения для уже распознанного `codex_update_scheduler` intent. |
| 3 | Почему authoritative UAT не остановил такой ответ? | Потому что wrapper не требовал положительного совпадения со scheduler contract reply. |
| 4 | Почему artifact ещё и записал `mutation_intent=update`? | Потому что UAT matcher принимал `update` внутри skill slug `codex-update` за action token для skill mutation. |
| 5 | Почему это системно опасно? | Потому что один и тот же user turn мог давать одновременно wrong reply и false green verdict, то есть defect проходил бы дальше по deploy/verification цепочке. |

## Root Cause

Корневая причина состояла из трёх связанных ошибок:

1. `scripts/telegram-safe-llm-guard.sh` имел слишком широкий implicit `skill_detail` fallback для сообщений с referenced skill name. Если пользователь явно называл `codex-update`, но вопрос был про scheduler/cron, fallback всё равно мог перетереть правильный codex-update branch.
2. `scripts/telegram-e2e-on-demand.sh` использовал слишком наивный update-matcher: standalone mutation verb и substring внутри skill slug (`codex-update`) не различались.
3. В authoritative UAT не было positive scheduler-contract check. Wrapper умел ловить memory/tool leakage, но не умел сказать: “ответ вообще не того семейства, это skill-detail summary вместо scheduler contract”.

## Fixes Applied

1. `scripts/telegram-safe-llm-guard.sh`
   - implicit `skill_detail` fallback больше не перетирает уже распознанный `codex_update_scheduler` turn.
2. `scripts/telegram-e2e-on-demand.sh`
   - mutation classifier теперь ищет standalone English action tokens, а не любые substrings вроде `update` внутри skill name;
   - добавлен positive matcher `reply_matches_codex_update_scheduler_contract()`;
   - scheduler questions теперь fail-closed с `semantic_codex_update_scheduler_contract_mismatch`, если reply скатывается в generic skill-detail wording.
3. `tests/component/test_telegram_safe_llm_guard.sh`
   - добавлен regression на live-shaped prompt:
     - `Как часто навык codex-update автоматически проверяет обновления Codex CLI?`
   - тест доказывает, что guard остаётся в `codex_update:scheduler`, а не уходит в `skill_detail`.
4. `tests/component/test_telegram_remote_uat_contract.sh`
   - добавлен regression на false-pass family, где scheduler question получает generic skill summary.

## Verification

Подтверждено локально:

- `bash tests/component/test_telegram_safe_llm_guard.sh` -> `147/147`
- `bash tests/component/test_telegram_remote_uat_contract.sh` -> `56/56`
- `git diff --check`

## Prevention

1. Для intent matcher нельзя считать skill slug одновременно и subject, и action token.
2. Domain-specific Telegram UAT должен иметь не только negative leak detectors, но и positive contract matchers для high-risk routes.
3. Если `referenced skill name` используется как fallback trigger, он обязан уважать более узкие, уже распознанные intent branches вроде scheduler/maintenance/state.
