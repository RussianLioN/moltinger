---
title: "Telegram codex-update direct fastpath cleared fallback state too early"
date: 2026-04-14
severity: P1
category: product
tags: [telegram, codex-update, direct-fastpath, suppression, semantic-review, rca]
root_cause: "After a successful codex-update direct fastpath send, the guard immediately cleared persisted turn intent and relied only on suppression markers. If same-turn suppression lookup was later unavailable, late tool calls and final MessageSending tails no longer had codex-update fallback context, so memory-based false positives could escape. The authoritative UAT semantic layer also prioritized generic activity-leak classification ahead of codex-update scheduler semantics and underfit replies that claimed cron existence from chat memory."
---

# RCA: Telegram codex-update direct fastpath cleared fallback state too early

Date: 2026-04-14  
Status: Fixed in source, pending PR review / merge / live verification  
Context: beads `moltinger-ch8h`

## Error

Пользователь снова получил live Telegram ответ, который нельзя считать корректным user-facing contract:

```text
Да — есть.

В памяти у меня явно записано:
«Ежедневно проверяю стабильные обновления Codex CLI и присылаю краткое уведомление только если вышла новая стабильная версия.»

...
📋 Activity log
• 🔧 cron
• 🧠 Searching memory...
• ❌ missing 'action' parameter
• ❌ missing 'query' parameter
• ❌ missing 'command' parameter
```

Это уже не старый false-negative вида «не подтверждено», а новый false-positive: бот утверждает наличие cron по памяти чата и одновременно протекает внутренними tool errors.

## Lessons Pre-check

Перед фиксом были проверены lessons и связанные правила:

- `docs/LESSONS-LEARNED.md`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`
- `docs/rca/2026-04-14-telegram-codex-update-live-runtime-ignored-inband-modify.md`
- `docs/rca/2026-04-14-telegram-codex-update-direct-fastpath-raced-underlying-run.md`
- `docs/rca/2026-04-14-telegram-codex-update-hard-override-did-not-terminalize-blocked-tool-followup.md`

Что уже было известно:

1. `codex-update` на Telegram-safe surface должен отвечать deterministic scheduler contract-ом, а не уходить в memory/tool speculation.
2. Ранний direct fastpath не является эквивалентом true short-circuit, если underlying run ещё может прислать поздний хвост.
3. Для same-turn follow-up нужны terminal markers и fail-closed suppression semantics.

Что оставалось непокрытым:

1. direct fastpath всё ещё считал suppression markers единственным источником истины и очищал `turn_intent` слишком рано;
2. semantic review в authoritative UAT первым срабатывал на generic `semantic_activity_leak`, а не на codex-update scheduler contract violation;
3. reply taxonomy в web probe была узкой и выделяла только `missing 'action' parameter`, но не `query/command`.

## Evidence

1. Пользовательский live reply содержал сразу три симптома:
   - memory-based proof: `В памяти у меня явно записано`
   - scheduler claim: `Да — есть`
   - leaked tool errors: `missing 'action'/'query'/'command' parameter`
2. В локальном component-repro текущий guard после успешного direct fastpath действительно:
   - ставил `.suppress`
   - но очищал `turn_intent`
   - и не оставлял отдельный fallback path, если suppression files потом исчезали.
3. После точечного source fix локальный repro с искусственно потерянными `.suppress` файлами показал:
   - `BeforeToolCall` всё ещё terminalizes same-turn follow-up через preserved codex-update context
   - `MessageSending` переписывается обратно в deterministic scheduler reply вместо memory-based false positive.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Почему пользователю снова пришёл плохой ответ про cron/Codex CLI? | Потому что поздний same-turn tail дошёл до user-facing delivery и ответил от лица “памяти”, а не от deterministic codex-update contract. |
| 2 | Почему late tail вообще смог пройти после успешного direct fastpath? | Потому что direct fastpath оставлял только suppression markers и сразу очищал persisted `turn_intent`. |
| 3 | Почему этого оказалось недостаточно? | Потому что при потере или недоступности suppression lookup у поздних `BeforeToolCall`/`MessageSending` событий больше не оставалось codex-update fallback context. |
| 4 | Почему authoritative UAT не формулировал это как codex-update scheduler contract breach? | Потому что semantic review сначала видел generic activity leak и только потом codex-update-specific semantics; positive memory-proof reply попадал под более грубую классификацию. |
| 5 | Почему reply taxonomy дополнительно недооценивала такой ответ? | Потому что error signature and scheduler-memory heuristics были заточены под старый negative false-negative и не покрывали positive memory assertion плюс `missing 'query'/'command' parameter`. |

## Root Cause

Корневой дефект состоял из двух связанных частей:

1. `scripts/telegram-safe-llm-guard.sh` после успешного `codex-update` direct fastpath очищал persisted `turn_intent` слишком рано и полагался только на `.suppress` markers. При потере suppression-state поздний same-turn tail больше не знал, что это `codex-update` turn, и мог уйти в memory/tool leakage.
2. `scripts/telegram-e2e-on-demand.sh` и `scripts/telegram-web-user-probe.mjs` были недоделаны для этой новой формы дефекта: semantic/UAT слой видел generic activity leak раньше domain-specific scheduler breach, а probe taxonomy недооценивала `missing 'query'/'command' parameter`.

## Fixes Applied

1. `scripts/telegram-safe-llm-guard.sh`
   - после успешного `codex-update` direct fastpath больше не очищает fallback state сразу;
   - сохраняет terminal marker для same-turn recovery;
   - оставляет persisted codex-update intent до тех пор, пока terminal delivery действительно не завершит turn.
2. `tests/component/test_telegram_safe_llm_guard.sh`
   - добавлен regression на искусственную потерю suppression-state после successful direct fastpath;
   - проверяется, что поздний `BeforeToolCall` и `MessageSending` всё равно terminalize/rewrite dirty tail.
3. `scripts/telegram-e2e-on-demand.sh`
   - расширен matcher `reply_has_codex_update_scheduler_memory_false_negative()` под positive memory assertions и leaked `action/query/command` parameter variants;
   - codex-update semantic checks подняты выше generic activity leak classification.
4. `tests/component/test_telegram_remote_uat_contract.sh`
   - добавлен authoritative semantic regression на positive memory-based false positive reply.
5. `scripts/telegram-web-user-probe.mjs`
   - расширен error-signature regex для `missing 'query' parameter` и `missing 'command' parameter`.
6. `tests/component/test_telegram_web_probe_correlation.sh`
   - добавлен regression на mixed `action/query/command` parameter error signature.

## Verification

Локально подтверждено:

- `bash -n scripts/telegram-safe-llm-guard.sh`
- `bash -n scripts/telegram-e2e-on-demand.sh`
- `bash tests/component/test_telegram_safe_llm_guard.sh`
- `bash tests/component/test_telegram_remote_uat_contract.sh`
- `bash tests/component/test_telegram_web_probe_correlation.sh`
- `git diff --check`

## Prevention

1. Для high-risk Telegram-safe routes нельзя очищать domain-specific fallback state сразу после direct fastpath send; suppression markers сами по себе недостаточны.
2. Если defect имеет явную domain семантику (`codex-update scheduler contract breach`), authoritative UAT должен классифицировать её раньше generic leak buckets.
3. Reply taxonomy для Telegram UAT должна покрывать не только один observed error string, а всё семейство близких tool-parameter leaks.

## Lessons

1. `direct fastpath delivered` не означает `fallback state больше не нужен`; same-turn recovery нужно держать до фактического terminal completion.
2. Generic leak detector не должен затмевать более полезную domain-specific классификацию, если prompt family уже распознан.
3. Один новый production reply variant обычно означает не только runtime defect, но и пробел в semantic/UAT taxonomy; чинить надо оба слоя сразу.
