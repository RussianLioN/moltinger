---
title: "Telegram codex-update direct fastpath must terminalize the initial pass"
date: 2026-04-14
severity: P1
category: product
tags: [telegram, codex-update, fastpath, terminalization, hook, cron, rca]
root_cause: "After the codex-update direct Bot API fastpath was restored for live reliability, the successful BeforeLLMCall path still exited without modifying the current LLM payload. That left the original model pass alive and relied on late same-turn suppression to clean up downstream tails. Live Telegram evidence showed that this was not a safe invariant: the initial pass still produced a memory-based cron false positive even though the direct fastpath and late suppressors both fired."
---

# RCA: Telegram codex-update direct fastpath must terminalize the initial pass

Date: 2026-04-14  
Status: Fixed in source, pending PR review / merge / live verification  
Context: beads `moltinger-1d69`, residual live Moltis Telegram regression after deploy of `#180`

## Error

После deploy предыдущего фикса пользователь всё ещё получал live Telegram ответ с ложным подтверждением cron “по памяти”, например:

```text
Да — есть.

По сохранённой памяти зафиксировано такое поведение...
```

При этом свежий authoritative UAT artifact уже классифицировал ответ как:

`semantic_codex_update_scheduler_memory_false_negative`

То есть проблема оставалась именно user-facing и semantic, а не только transport-level.

## Lessons Pre-check

Перед новым source fix были повторно проверены lessons:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag codex-update`
- `./scripts/query-lessons.sh --tag fastpath`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Самые релевантные прошлые уроки:

1. `2026-04-14-telegram-codex-update-direct-fastpath-raced-underlying-run.md`  
   Ранний direct fastpath не равен true short-circuit, если underlying run остаётся жив.
2. `2026-04-14-telegram-codex-update-live-runtime-ignored-inband-modify.md`  
   Для части live Telegram routes direct Bot API fastpath является reliability contract, а не просто оптимизацией.
3. `2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md`  
   Direct fastpath должен быть terminal для остатка same-turn runtime, а не полагаться на позднюю эвристику.

Что уже было покрыто:

- user-visible direct fastpath без terminalization опасен;
- live audit важнее старого зелёного smoke;
- late same-turn tails нужно гасить deterministic state machine.

Что оставалось непокрытым:

- для `codex-update` direct fastpath success path всё ещё не гасил именно самый первый LLM-pass;
- regression suite всё ещё считала “пустой stdout на initial BeforeLLMCall” корректным контрактом для этого route;
- поздние suppressors были доказаны, но initial pass всё ещё жил слишком долго.

## Evidence

Production evidence после deploy `#180`:

1. authoritative Telegram UAT run `24413404585` завершился semantic failure:
   - `verdict = failed`
   - `failure.code = semantic_codex_update_scheduler_memory_false_negative`
2. review-safe artifact зафиксировал живой bad reply с memory-based cron claim.
3. container audit log `/tmp/moltis-telegram-safe-llm-guard.audit.log` показал, что hook в том же turn реально делал:
   - `intent_set ... intent=codex_update_scheduler`
   - `direct_fastpath kind=codex_update ... mode=scheduler`
   - `terminal_set ... token=scheduler`
   - позже `emit_modify ... reason=direct_fastpath_after_llm_suppress`
4. raw capture в контейнере показал:
   - поздний `AfterLLMCall` output уже действительно был `{"action":"modify","data":{"text":"","tool_calls":[]}}`
   - но initial successful `BeforeLLMCall` direct fastpath не отдавал `modify` payload и просто завершался `exit 0`

Это доказывает: late suppression работала, но initial model pass всё равно успевал породить bad semantic reply.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Почему пользователь снова увидел memory-based false positive reply? | Потому что живой initial model pass всё ещё дошёл до генерации bad текста про cron “по памяти”. |
| 2 | Почему initial model pass вообще продолжал жить после successful direct fastpath? | Потому что `BeforeLLMCall` success path отправлял direct Bot API reply и сразу делал `exit 0`, не заменяя текущий prompt terminal guard-ом. |
| 3 | Почему поздние suppressors не считались достаточной защитой? | Потому что они срабатывали уже после того, как initial pass был допущен к модели и мог породить bad semantic content. |
| 4 | Почему это не было видно в локальной regression suite? | Потому что tests закрепляли старый контракт: “успешный codex-update direct fastpath должен оставить stdout пустым”. |
| 5 | Почему system contract остался неполным? | Потому что direct fastpath воспринимался как delivery-only shortcut, а не как full terminalization requirement для high-risk Telegram-safe route. |

## Root Cause

После возврата `codex-update` на live-proven direct Bot API fastpath hook уже:

- отправлял правильный канонический reply напрямую в Telegram,
- сохранял suppression markers,
- сохранял terminal marker,
- гасил поздние tails на `AfterLLMCall`/`BeforeToolCall`/`MessageSending`.

Но success path на самом первом `BeforeLLMCall` всё ещё не делал `emit_before_llm_modified_payload(...)`.  
Он отправлял direct reply и просто завершался `exit 0`, оставляя исходный LLM-pass нетерминализированным.

Для `codex-update` это оказалось недопустимо: live runtime всё ещё успевал сгенерировать bad memory-based cron reply до того, как поздние same-turn suppressors его дочищали.

## Fixes Applied

1. `scripts/telegram-safe-llm-guard.sh`
   - после успешного `codex-update` direct fastpath hook теперь сразу отдаёт terminal `BeforeLLMCall` modify payload;
   - initial pass получает:
     - system guard `Telegram-safe codex-update terminal guard`
     - user prompt `Верни пустую строку. Не вызывай инструменты.`
     - `tool_count=0`
   - direct Bot API delivery остаётся, но теперь initial model pass тоже явно терминализирован в том же событии.
2. `tests/component/test_telegram_safe_llm_guard.sh`
   - обновлены codex-update direct-fastpath regressions;
   - success path теперь обязан выдавать `modify`, а не пустой stdout;
   - отдельно проверяется, что terminal guard выдаётся и для array-shaped live payload.
3. `scripts/telegram-e2e-on-demand.sh` и `tests/component/test_telegram_remote_uat_contract.sh`
   - semantic matcher расширен под exact live wording family:
     - `по сохранённой памяти зафиксировано такое поведение`
     - `по сохранённому контексту крон есть`
   - добавлен отдельный regression, чтобы такой ответ больше не мог пройти authoritative UAT как `passed`.
4. existing same-turn recovery regressions
   - сохранены и подтверждают, что поздние tool/AfterLLM/MessageSending tails остаются подавленными поверх нового initial terminalization.

## Verification

Локально подтверждено:

- `bash tests/component/test_telegram_safe_llm_guard.sh` → `121/121 PASS`
- `bash tests/component/test_telegram_remote_uat_contract.sh` → `46/46 PASS`
- `git diff --check`

## Prevention

1. Для high-risk Telegram-safe direct fastpaths “reply already delivered” недостаточно; initial LLM pass тоже обязан быть terminalized в том же `BeforeLLMCall`.
2. Regression suite не должна считать пустой stdout признаком успеха, если route по продуктовой логике требует explicit prompt replacement.
3. Если late suppressors зелёные, это ещё не доказывает корректность initial pass; для таких routes нужны отдельные проверки initial terminalization.

## Lessons

1. Direct Bot API delivery и terminalization initial LLM pass — это два разных инварианта, и для Telegram-safe `codex-update` нужны оба сразу.
2. Поздний `AfterLLMCall` suppression не может компенсировать уже живой initial model pass.
3. Если live evidence показывает residual semantic bug после “правильного” fastpath, нужно проверять не только downstream cleanup, но и самый первый `BeforeLLMCall` contract.
