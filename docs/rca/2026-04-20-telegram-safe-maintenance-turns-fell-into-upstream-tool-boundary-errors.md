---
title: "Telegram-safe maintenance turns fell into upstream tool-boundary errors"
date: 2026-04-20
severity: P1
category: product
tags: [telegram, skills, codex-update, hook, runtime, maintenance, rca]
root_cause: "Live Moltis runtime accepted correct tool arguments from the model but still raised missing-parameter errors at the execution boundary, while the repo-owned Telegram-safe guard had no dedicated maintenance/debug intent for skill/codex-update repair turns and therefore failed to terminalize those turns before tool/runtime chatter leaked into user-visible Telegram replies."
---

# RCA: Telegram-safe maintenance turns fell into upstream tool-boundary errors

Date: 2026-04-20  
Status: Resolved in source, pending landing/deploy/live re-verification  
Context: beads `moltinger-evgq`, Telegram-safe Moltis lane for skill/codex-update questions

## Ошибка

В user-facing Telegram бот отвечал не итогом, а смесью обычного текста и внутренних runtime-ошибок:

```text
Если хочешь, я сразу напишу готовую новую версию инструкции...
📋 Activity log
• 💻 Running: `sed -n '1,220p' /home/moltis/.moltis/skills/codex-update/SKILL.md`
• 🧠 Searching memory...
• ❌ missing 'command' parameter
• ❌ missing 'query' parameter
```

Пользовательский запрос был по сути maintenance/debug turn: починить `codex-update`/skill-path и убрать leakage.  
Вместо deterministic Telegram-safe boundary runtime ушёл в tool-backed path и показал сырой хвост.

## Проверка прошлых уроков

Проверены:

- `docs/LESSONS-LEARNED.md`
- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag codex-update`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Релевантные прошлые RCA:

1. `docs/rca/2026-04-14-telegram-codex-update-live-runtime-ignored-inband-modify.md`  
   Уже фиксировал, что live Telegram runtime может игнорировать красивый in-band path и что надо смотреть на production evidence, а не только на локальную логику.
2. `docs/rca/2026-04-14-telegram-codex-update-hard-override-did-not-terminalize-blocked-tool-followup.md`  
   Уже покрывал тему terminalization после blocked tool follow-up.
3. `docs/rca/2026-04-05-telegram-skill-detail-general-hardening.md`  
   Уже показывал, что skill-related Telegram turns нельзя оставлять на filesystem/tool-heavy explanations.

Что оказалось новым:

- текущий инцидент был не scheduler/release question, а maintenance/debug turn по skill/codex-update;
- production logs показали, что model/runtime формировали корректные аргументы для `exec` и `memory_search`, но execution boundary всё равно терял их и возвращал `missing 'command' parameter` / `missing 'query' parameter`;
- repo-owned guard не имел отдельного класса для maintenance/debug turn и поэтому не переводил такие turns в fail-closed text-only boundary заранее.

## Evidence

Authoritative evidence была собрана с live host `root@ainetic.tech`:

1. `docker logs moltis` показал фактические tool calls с корректными аргументами:
   - `exec` с `{"command":"sed -n '1,220p' /home/moltis/.moltis/skills/codex-update/SKILL.md", ...}`
   - `memory_search` с `{"query":"codex-update уведомление версия cron ...","limit":10}`
2. Тот же live runtime сразу после этого возвращал:
   - `missing 'command' parameter`
   - `missing 'query' parameter`
3. Checksums repo script и live script совпали:
   - local `scripts/telegram-safe-llm-guard.sh`
   - live `/server/scripts/telegram-safe-llm-guard.sh`
4. Hook registration в live config была активна:
   - `telegram-safe-llm-guard`
   - `events = ["BeforeLLMCall", "AfterLLMCall", "BeforeToolCall", "MessageSending"]`
5. Live runtime version была `moltis 0.10.18`, что подтверждало известную ненадёжность некоторых hook/delivery surfaces и необходимость repo-owned fail-closed containment.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Почему пользователь увидел `Activity log` и `missing 'query' parameter`? | Потому что maintenance/debug turn ушёл в tool-backed path и поздний runtime tail не был переведён в deterministic Telegram-safe reply. |
| 2 | Почему turn вообще ушёл в tool-backed path? | Потому что guard не распознал запрос как отдельный maintenance/debug класс и не сделал раннюю terminalization через text-only boundary. |
| 3 | Почему отсутствие отдельного maintenance intent оказалось критичным? | Потому что существующие special cases покрывали skill visibility/template/create/detail и codex-update release/scheduler, но не generic repair/debug/log/root-cause turns. |
| 4 | Почему поздний tool tail был особенно вредным? | Потому что upstream runtime boundary на live Moltis 0.10.18 терял уже корректно сформированные tool arguments и превращал их в ложные `missing parameter` ошибки, которые потом протекали наружу. |
| 5 | Почему это стало системной проблемой, а не единичной ошибкой исполнения? | Потому что repo-owned containment полагался на то, что generic turn либо пройдёт нормально, либо будет пойман существующими overrides, но новый класс maintenance/debug turns не был формально описан и поэтому не имел ни intent persistence, ни BeforeToolCall suppression, ни dedicated MessageSending rewrite. |

## Root Cause

Корень проблемы состоял из двух слоёв:

1. **External/upstream runtime defect**  
   Live Moltis tool execution boundary в `0.10.18` принимал корректно сформированные model arguments, но местами терял их и возвращал ложные `missing required parameter` ошибки.
2. **Repo-owned containment gap**  
   Telegram-safe guard не выделял maintenance/debug turns по skill/codex-update в отдельный intent и не терминализировал их заранее, поэтому upstream runtime bug получал шанс стать user-visible.

## Fixes Applied

1. `scripts/telegram-safe-llm-guard.sh`
   - добавлен отдельный maintenance/debug intent для:
     - skill repair/debug/log/root-cause turns;
     - `codex-update` repair/debug/log/root-cause turns;
   - maintenance turns теперь принудительно переводятся в text-only boundary до запуска инструментов;
   - добавлена intent persistence для поздних `AfterLLMCall` / `MessageSending` hooks;
   - добавлен dedicated `BeforeToolCall` suppression для maintenance turns;
   - добавлен dedicated reply override для leaked maintenance/runtime chatter;
   - bare `update` больше не считается release-signal для любого упоминания `codex-update`, чтобы `codex-update` maintenance turns не путались с advisory/release path.
2. `config/moltis.toml`
   - закреплён операторский контракт: maintenance/debug/log inspection по skill/codex-update не обслуживаются в user-facing Telegram/DM;
   - отдельно зафиксировано, что простые CRUD-правки навыков допустимы только по явной команде через `create_skill/update_skill/delete_skill`.
3. `.moltis/hooks/telegram-safe-llm-guard/HOOK.md`
   - обновлено hook-level описание boundary для maintenance/debug turns.
4. `tests/component/test_telegram_safe_llm_guard.sh`
   - добавлены regressions на:
     - early hard override для `почини codex-update`;
     - exact live-style `Activity log` leak;
     - plain runtime-failure leak без явного `Activity log`;
     - контроль, что explicit `update_skill` остаётся allowlisted CRUD flow, а не попадает в maintenance bucket.

## Prevention

1. Любой новый user-facing Telegram turn family должен иметь явный intent class, если он отличается по risk profile от уже существующих safe routes.
2. Для live Moltis `0.10.18` нельзя считать upstream tool boundary надёжным доказательством корректности user-facing reply даже при правильных model arguments.
3. Skill/codex-update repair/debug/log turns должны закрываться fail-closed ещё на `BeforeLLMCall`, а не надеяться на generic fallback после tool execution.
4. Если live evidence показывает “правильные аргументы вошли, но runtime сказал missing parameter”, проблема классифицируется как execution-boundary defect, а не как модельный prompt bug.

## Уроки

1. Maintenance/debug turns по skill/codex-update — это отдельный Telegram-safe contract, а не частный случай skill detail или codex-update advisory.
2. Для user-facing Telegram нужно отдельно защищать turns, где пользователь просит “починить/отладить/посмотреть логи”, даже если похожие informational turns уже покрыты другими guard branches.
3. В presence upstream runtime defects repo-owned guard обязан fail-close на уровне intent routing, иначе даже корректные аргументы и корректные tool names всё равно могут протечь наружу как ложные runtime errors.
