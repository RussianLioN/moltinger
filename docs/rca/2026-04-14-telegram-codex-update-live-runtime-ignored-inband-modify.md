---
title: "Telegram codex-update live runtime ignored in-band hook modify despite correct guard output"
date: 2026-04-14
severity: P1
category: product
tags: [telegram, codex-update, fastpath, hook, runtime, cron, rca]
root_cause: "Production Moltis Telegram runtime still ignored correct in-band hook `modify` outputs for the `codex-update` scheduler turn, so relying on hard-override/terminalization alone could not deliver the deterministic user-facing reply; the reliable contract remained the direct Bot API fastpath with same-turn suppression."
---

# RCA: Telegram codex-update live runtime ignored in-band hook modify despite correct guard output

Date: 2026-04-14  
Status: Resolved in source, pending merge/deploy/live re-verification  
Context: beads `moltinger-mvy8`, production regression after merge/deploy of `#177`

## Ошибка

После production deploy пользователь по-прежнему получал ложный ответ вида:

```text
Проверил — и да, тут инструмент расписания реально сломан...
...
📋 Activity log
• 🔧 cron
•   ❌ missing 'action' parameter
```

То есть Telegram-safe `codex-update` scheduler turn снова уходил в broken tool/memory path вместо канонического remote-safe contract reply.

## Проверка прошлых уроков

Проверены:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag codex-update`
- `./scripts/query-lessons.sh --tag hooks`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Релевантные прошлые RCA:

1. `docs/rca/2026-04-02-telegram-skill-detail-single-inband-path-regressed-live-runtime.md`  
   уже фиксировал, что live Telegram runtime может игнорировать корректный in-band hook path и что для некоторых user-facing turns надёжным контрактом остаётся direct Bot API fastpath.
2. `docs/rca/2026-04-14-telegram-codex-update-hard-override-did-not-terminalize-blocked-tool-followup.md`  
   уже показывал, что одного hard override недостаточно без terminal/suppression state machine.
3. `docs/rca/2026-04-14-telegram-codex-update-direct-fastpath-raced-underlying-run.md`  
   содержал гипотезу, что direct fastpath сам по себе является корнем проблемы для `codex-update`.

Что оказалось новым:

- production evidence после `#177` показал, что guard script уже выдавал правильные `modify` payloads, а ломался именно live runtime layer, который их не применял;
- значит, предыдущее решение “убрать direct fastpath и оставить чистый in-band hard override” было неправильным для этого конкретного live Telegram path;
- для `codex-update` надо вернуть direct fastpath, но сохранить same-turn suppression contract, чтобы underlying run не мог дописать второй хвост.

## Evidence

Собранная production evidence:

1. серверный script checksum совпал локально и на live host:
   - local `scripts/telegram-safe-llm-guard.sh` SHA256
   - live `/opt/moltinger/scripts/telegram-safe-llm-guard.sh` SHA256
   - значения совпали, то есть deploy drift guard script не было
2. hook был реально зарегистрирован в runtime:
   - `[[hooks.hooks]] name = "telegram-safe-llm-guard"` в `/opt/moltinger/config/moltis.toml`
   - `docker logs moltis` содержал `hook handler registered handler="telegram-safe-llm-guard"`
3. audit log внутри контейнера `/tmp/moltis-telegram-safe-llm-guard.audit.log` для проблемного nonce-turn показал:
   - `intent_set ... intent=codex_update_scheduler`
   - `before_modify reason=codex_update_hard_override`
   - `emit_modify event=AfterLLMCall reason=codex_update_reply_override`
   - `emit_modify event=BeforeToolCall reason=codex_update_terminal_tool_suppress tool=memory_search`
   - `emit_modify event=AfterLLMCall reason=codex_update_terminal_after_llm_suppress`
4. captured hook artefacts внутри контейнера показали корректные JSON outputs:
   - repeated `BeforeLLMCall` возвращал `action=modify` с terminal guard и `tool_count=0`
   - late `AfterLLMCall` возвращал `action=modify`, `text=""`, `tool_calls=[]`
5. при этом `docker logs moltis` для того же run показал фактическое поведение runtime:
   - tool `memory_search` всё равно был реально вызван
   - tool упал с `missing 'query' parameter`
   - late final bad reply всё равно был возвращён в `moltis_chat`
   - outbound Telegram send ушёл как `sent`

Это доказало, что сам guard уже работал корректно, но live runtime не уважал его in-band `modify` outputs для этого класса turns.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---|---|---|---|
| 1 | Почему пользователь снова увидел broken scheduler reply? | Потому что production turn снова дошёл до real `memory_search`/late bad text path. | `docker logs moltis`, nonce turn `run_id=889189a3-3d1d-487b-a683-8ff04e316b89` |
| 2 | Почему late bad path вообще исполнился после `#177`? | Потому что live runtime не применил корректные hook `modify` outputs, хотя guard их сгенерировал. | audit log + captured `*.output.json` inside container |
| 3 | Почему это не было просто deploy drift старого guard script? | Потому что live script и локальный script совпали по SHA256, а hook registration остался активным. | local/live SHA256 compare, `moltis.toml`, `docker logs moltis` |
| 4 | Почему hard override + terminalization не спасли пользовательский ответ? | Потому что этот механизм опирался на in-band hook application, а именно этот слой и оказался ненадёжным в live Telegram runtime. | audit says `modify`; runtime still executed tool and returned text |
| 5 | Почему прошлое решение оказалось неверным? | Потому что оно трактовало проблему как “direct fastpath race”, хотя новые production evidence показали другой корень: runtime игнорирует корректный in-band modify и поэтому direct fastpath остаётся live-proven delivery contract. | contradicted by post-deploy live audit and container captures |

## Root Cause

Корневая причина была не в текущем `telegram-safe-llm-guard.sh` script и не в его классификации prompt family.  
Корневая причина была в architectural mismatch между repo-owned guard contract и live Moltis Telegram runtime:

- guard возвращал правильные deterministic `modify` payloads;
- но production runtime для `codex-update` scheduler turn всё равно продолжал underlying LLM/tool loop и отправлял user-visible bad tail.

Следовательно, для этого user-facing Telegram scenario in-band hard override/terminalization path сам по себе не может считаться надёжным delivery contract. Надёжным contract остаётся direct Bot API fastpath с same-turn suppression, как и у ранее доказанных live scenarios.

## Fixes Applied

1. `scripts/telegram-safe-llm-guard.sh`
   - restored controlled direct fastpath for `codex-update` release/scheduler turns when `MOLTIS_TELEGRAM_SAFE_DIRECT_FASTPATH=true`
   - left hard-override path below as fallback when direct send is disabled or unavailable
2. `tests/component/test_telegram_safe_llm_guard.sh`
   - replaced regression that forbade direct fastpath for `codex-update`
   - added codex-update direct-fastpath regression that proves:
     - direct send is used
     - session/chat suppression markers are armed
     - repeated same-turn `BeforeLLMCall` is suppressed
     - follow-up tool, late `AfterLLMCall`, and `MessageSending` tail are suppressed
3. lessons flow
   - new RCA recorded
   - lessons index rebuilt

## Prevention

1. Не считать “чистый in-band hook path” улучшением сам по себе, если именно этот delivery path не подтверждён live Telegram evidence.
2. Для user-facing Telegram routes differentiator должен быть не “красивее архитектурно”, а “какой contract реально доходит до пользователя в production”.
3. Если audit log и captured hook outputs уже правильные, а live reply неправильный, следующий fix должен идти в delivery architecture, а не в очередной classifier tweak.

## Уроки

1. Для Telegram-safe routes “hook правильно сгенерировал modify” и “пользователь реально увидел modify-результат” — это разные утверждения.
2. Если production evidence опровергает предыдущий RCA, нужно не защищать старую гипотезу, а переписать source contract под новый факт.
3. `codex-update` и `skill_detail` теперь подтверждают один и тот же урок: для части live Telegram scenarios direct Bot API fastpath остаётся reliability contract, а не просто оптимизацией.
