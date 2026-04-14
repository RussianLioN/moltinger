---
title: "Telegram codex-update hard override did not terminalize blocked tool follow-up"
date: 2026-04-14
severity: P1
category: product
tags: [telegram, codex-update, hook, terminalization, cron, rca]
root_cause: "The Telegram-safe codex-update hard override still allowed a blocked cron tool follow-up to create a second internal LLM pass; terminal recovery depended on brittle iteration/order assumptions, and the final MessageSending recovery path could fail open if suppression state was not armed successfully."
---

# RCA: Telegram codex-update hard override did not terminalize blocked tool follow-up

Date: 2026-04-14  
Status: Resolved in source, pending landing/deploy/live re-verification  
Context: follow-up to `2026-04-14-telegram-codex-update-direct-fastpath-raced-underlying-run`, beads lane `moltinger-mcgq`

## Error

После production fix-а, который убрал ранний `codex-update` direct fastpath, authoritative Telegram Web path уже начал проходить. Но live audit показал, что внутри того же turn проблема ещё жила:

- `BeforeLLMCall` делал `codex_update_hard_override`;
- затем runtime всё равно входил в `BeforeToolCall` на `cron`;
- после synthetic tool block происходил ещё один `BeforeLLMCall`/`AfterLLMCall`;
- поздний internal answer всё ещё формулировался как сломанный `cron`/`missing 'action' parameter`.

То есть пользовательский ответ мог уже не течь наружу, но корень проблемы оставался: turn после deterministic hard override не становился truly terminal.

## Lessons Pre-check

Проверены lessons:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag codex-update`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Релевантные прошлые RCA:

1. `2026-04-14-telegram-codex-update-direct-fastpath-raced-underlying-run.md`  
   Уже покрывал запрет раннего direct fastpath и требование смотреть на live audit, а не только на ранний green smoke.
2. `2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md`  
   Уже фиксировал, что same-turn suppression must stay alive, если runtime продолжает хвост после user-visible ответа.

Что оставалось непокрытым:

- deterministic `hard override` сам по себе не считался “terminal”, если runtime успел войти в blocked tool branch;
- persisted `codex-update` reply override для recovered empty delivery всё ещё стоял после слишком раннего generic `MessageSending` short-circuit;
- repeat-guard зависел от `iteration > 1`, хотя повторный same-turn hook мог прийти без `iteration`;
- terminal marker жил на коротком suppression TTL и не был fail-closed, если финальная arm-фаза suppression state ломалась.

## Evidence

Production evidence из `/tmp/moltis-telegram-safe-llm-guard.audit.log` и `docker logs moltis` на `root@ainetic.tech`:

- `2026-04-14T12:16:44Z` `BeforeLLMCall` с intent `codex_update_scheduler`
- `2026-04-14T12:16:45Z` `before_modify reason=codex_update_hard_override`
- `2026-04-14T12:16:49Z` `emit_modify event=AfterLLMCall reason=codex_update_reply_override mode=scheduler`
- `2026-04-14T12:16:50Z` `emit_modify event=BeforeToolCall reason=disallowed_tool_block tool=cron`
- `2026-04-14T12:16:52Z` повторный `BeforeLLMCall` на тот же turn
- `2026-04-14T12:16:59Z` поздний `AfterLLMCall` всё ещё содержал bad scheduler false-negative candidate
- `2026-04-14T12:17:00Z` app log завершал run текстом про сломанный scheduler tool

Локальное воспроизведение на branch подтвердило тот же sequence: без отдельной terminalization blocked tool branch запускал повторный LLM pass.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Почему после `codex_update_hard_override` ещё появлялся второй internal reply? | Потому что runtime всё равно продолжал tool-follow-up branch и создавал второй LLM pass. |
| 2 | Почему hard override не остановил этот branch? | Потому что hook переписывал prompt/text, но не держал отдельное same-turn terminal state после blocked tool follow-up. |
| 3 | Почему blocked `cron` follow-up не считался терминальным событием? | Потому что логика guard различала direct-fastpath suppression, но не имела отдельного состояния для deterministic hard-override turn, который уже “решён”, но ещё не доставлен. |
| 4 | Почему recovered empty final delivery не превращался гарантированно в канонический `codex-update` reply? | Потому что persisted `codex-update` rewrite стоял после generic `MessageSending` short-circuit, а arm suppression state в финальной доставке не проверялся fail-closed. |
| 5 | Почему это стало системной проблемой? | Потому что инварианта была неполной: мы зафиксировали “не использовать ранний direct fastpath”, но не оформили вторую половину контракта — blocked tool follow-up после hard override должен переводить turn в terminal recovery path без зависимости от `iteration`, порядка хуков и удачного best-effort write suppression-файлов. |

## Root Cause

Telegram-safe `codex-update` path после удаления раннего direct fastpath всё ещё не имел достаточно жёсткой terminalization-фазы для same-turn blocked tool follow-up.

В результате:

1. `BeforeToolCall` на `cron` блокировался, но turn не помечался как terminal recovery turn;
2. runtime входил во второй `BeforeLLMCall`/`AfterLLMCall`, а repeat recovery зависел от наличия `iteration > 1`;
3. поздний internal bad reply снова формировался;
4. terminal marker мог утечь через turn boundary или истечь слишком рано, потому что жил на suppression TTL и не был жёстко ограждён codex-update intent;
5. при попытке чинить это empty final delivery generic `MessageSending` short-circuit ещё и мог обойти persisted `codex-update` rewrite, а сама arm-фаза suppression state была fail-open.

## Fixes Applied

1. `scripts/telegram-safe-llm-guard.sh`
   - добавлен session-scoped `.terminal` marker для `codex-update` blocked tool follow-up;
   - `BeforeToolCall` на `codex-update` теперь переводит turn в terminal recovery mode;
   - terminal marker больше не зависит от `iteration > 1`: repeated `BeforeLLMCall` теперь может быть terminal-marker-driven даже без `iteration` и без reclassification из user text;
   - terminal marker очищается на non-`codex-update` user turn, чтобы не течь в чужой следующий turn;
   - terminal marker живёт на отдельном `TERMINAL_TTL_SEC`, а не на коротком suppression TTL;
   - повторный `AfterLLMCall` при активном terminal marker принудительно обнуляет text/tool calls;
   - arm suppression state для финальной codex-update доставки переведён в fail-closed helper: если suppression не arm'ится, guard сохраняет terminal marker и intent, а поздние dirty tails продолжают переписываться в детерминированный safe reply вместо выхода в fail-open.
2. `tests/component/test_telegram_safe_llm_guard.sh`
   - добавлен regression на полный live-like sequence:
     `BeforeLLM hard override -> BeforeToolCall cron -> repeated BeforeLLM -> repeated AfterLLM -> final MessageSending -> repeated dirty tail`;
   - добавлен regression на marker-driven repeat без `iteration` и без user-text reclassification;
   - добавлен regression на cleanup safety следующего user turn в том же chat;
   - добавлен regression на fail-closed поведение, когда suppression arm ломается.

## Prevention

1. Для Telegram-safe deterministic routes нужен не только prompt override, но и явный terminal recovery state на blocked tool follow-up.
2. Recovery path не должен зависеть от наличия `iteration`, если persisted turn state уже доказывает same-turn continuation.
3. Любая финальная arm-фаза suppression state на границе user-visible delivery должна быть fail-closed, а не `|| true`.
4. Generic `MessageSending` early-exit нельзя ставить раньше persisted reply rewrites для recovery turns.
5. Если live audit показывает второй internal pass, bug не считается закрытым даже при внешне корректном пользовательском reply.

## Уроки

1. `hard override` и `terminal turn` — не синонимы; blocked tool branch после hard override требует отдельного state machine шага.
2. Recovery reply для empty final payload должен быть расположен раньше generic short-circuit, иначе fix останется полу-рабочим.
3. После любого Telegram-safe live fix нужно проверять не только user-visible verdict, но и audit sequence внутри turn.
