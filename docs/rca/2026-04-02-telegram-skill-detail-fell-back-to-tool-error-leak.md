---
title: "Telegram skill-detail requests initially lacked a deterministic runtime path, then regressed on container-only parser/runtime drift"
date: 2026-04-02
tags: [telegram, moltis, skills, hooks, activity-log, mcp, tavily, rca]
root_cause: "The first failure was a missing deterministic skill-detail route in the Telegram-safe guard. The first repo-side fix then still depended on host-only assumptions: python3-based skill summarization/fuzzy resolve and a fragile custom awk parser for last-user extraction. In the live Moltis container python3 was absent and the parser behaved differently, so the same payload that direct-fastpathed on the host fell back to generic safe-lane / tool behavior in production."
---

# RCA: Telegram skill-detail requests initially lacked a deterministic runtime path, then regressed on container-only parser/runtime drift

## Ошибка

На вопрос пользователя вида `Расскажи мне про навык telegram-lerner` бот:

- не вернул нормальное краткое описание навыка из `SKILL.md`;
- начал объяснять, что "чтение файла навыка через инструмент не сработало";
- показал `Activity log`;
- показал внутреннюю tool-ошибку вроде `missing 'command' parameter`.

## Проверка прошлых уроков

**Проверенные источники:**
- `./scripts/query-lessons.sh --tag skills`
- `./scripts/query-lessons.sh --tag telegram`
- [docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md)
- [docs/rca/2026-04-01-telegram-skill-visibility-and-create-hook-modify-bypass.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-01-telegram-skill-visibility-and-create-hook-modify-bypass.md)
- [docs/rca/2026-03-27-moltis-repo-skill-discovery-contract-drift.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-03-27-moltis-repo-skill-discovery-contract-drift.md)

**Что уже было известно до этого инцидента:**
1. Для Telegram-safe delivery нельзя полагаться только на synthetic hook contract; live runtime может вести себя иначе.
2. Для user-facing skill flows уже понадобились deterministic repo-owned fastpath routes для `skills?`, `template` и `create skill`.
3. Runtime skill contract надо доказывать по live `/home/moltis/.moltis/skills` и реальному поведению, а не по repo mount или предположениям модели.

**Что оказалось новым в текущем кейсе:**
- skill-detail turn не попадал ни в один из уже существующих deterministic routes;
- live runtime skill file реально существовал и в repo, и в runtime discovery path;
- утечка шла не потому, что skill отсутствовал, а потому что вопрос про skill detail проваливался в tool path.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---------|--------|-------|
| 1 | Почему пользователь увидел `Activity log` и tool error вместо описания навыка? | Потому что turn ушёл в LLM/tool path и не был перехвачен deterministic skill-detail ответом. |
| 2 | Почему не было deterministic ответа? | Потому что guard покрывал visibility/template/create/apply/codex-update, но не покрывал запросы "расскажи про конкретный навык". |
| 3 | Почему модель вообще пыталась лезть в инструменты, хотя runtime `SKILL.md` уже существовал? | Потому что для такого типа вопроса в repo не было прямого runtime reader/summarizer из `SKILL.md`, и модель пыталась сама читать файл через tool path. |
| 4 | Почему tool path оказался пользовательски опасным? | Потому что при tool-schema/runtime failure live Telegram path снова потащил наружу внутренние шаги и ошибку валидации вместо чистого user-facing ответа. |
| 5 | Почему эта щель осталась после прошлых фиксов? | Потому что предыдущий инцидент закрывал другой slice (`skills?`, `template`, `create skill`, `codex-update`) и не расширил deterministic contract на skill-detail queries. |

## Корневая причина

Корневая причина оказалась двухслойной:

1. Изначально в `telegram-safe-llm-guard.sh` вообще отсутствовал deterministic runtime path для skill-detail вопросов о конкретном навыке.
2. После первой правки всплыл второй, более глубокий дефект portability:
   - skill-detail summary и fuzzy resolve зависели от `python3`;
   - извлечение последнего user turn зависело от кастомного `awk`-парсинга `messages[]`;
   - в live Moltis container `python3` отсутствовал, а этот self-made parser вёл себя иначе, чем на host replay.

Из-за этого получился ложный локальный успех: exact payload на host уже уходил в `direct_fastpath kind=skill_detail`, но тот же payload внутри live container всё ещё падал в generic `safe_lane`/tool path и выдавал пользователю ответ вида «не получилось прочитать файл навыка через инструменты».

## Внешние подтверждения

**Официальная документация:**
- hooks docs по-прежнему обещают outbound hook surface, но live behavior для Telegram уже раньше расходился с этим инвариантом: <https://docs.openclaw.ai/zh-CN/automation/hooks>

**Upstream issues, подтверждающие класс проблемы:**
1. `#21789` — `message_sent hook is never called in outbound delivery path`: <https://github.com/openclaw/openclaw/issues/21789>
2. `#52390` — `message:sent internal hook not firing for Telegram group deliveries (missing sessionKey)`: <https://github.com/openclaw/openclaw/issues/52390>
3. `#59150` — commentary leakage and duplicate visible replies after tool sends: <https://github.com/openclaw/openclaw/issues/59150>

**Честное уточнение:**
- exact upstream issue вида `skill detail over Telegram leaks missing command parameter` не найден;
- текущий кейс — ещё одно проявление уже известного runtime class problem: Telegram + tool/error path нельзя оставлять без deterministic repo-owned surface.

## Принятые меры

1. Добавлен deterministic skill-detail path:
   - skill name извлекается из текущего user turn;
   - live runtime skill name резолвится по runtime-discovered skills, включая fuzzy match для опечаток типа `telegram-lerner`;
   - user-facing summary строится прямо из runtime `SKILL.md`, без LLM speculation и без tool probes.
2. Добавлен direct fastpath для skill-detail turn через Bot API send, аналогично уже существующим safe routes.
3. Добавлен hard-override и final-delivery rewrite для skill-detail, чтобы даже при fallback/runtime drift Telegram видел deterministic summary, а не internal tool error.
4. Убрана host-only зависимость из critical path:
   - `extract_last_message_content_by_role` теперь сначала использует container-friendly `perl + JSON::PP`, а только потом старый awk fallback;
   - `resolve_runtime_skill_name_from_text` получил `perl`-based fuzzy match и исправленный CSV split fallback;
   - `build_skill_detail_reply_text` теперь умеет собирать deterministic summary через `perl` без `python3`.
5. Добавлены regression tests:
   - direct fastpath для `Расскажи мне про навык telegram-lerner`;
   - direct fastpath для skill-detail даже при сломанном `python3` и с prior history;
   - MessageSending rewrite для реального leakage-pattern с `missing 'command' parameter`.

## Проверка

- `bash -n scripts/telegram-safe-llm-guard.sh`
- `bash -n tests/component/test_telegram_safe_llm_guard.sh`
- `bash tests/component/test_telegram_safe_llm_guard.sh`

## Уроки

1. Skill contract в Telegram должен покрывать не только visibility/create/template, но и detail/describe path для уже существующих runtime skills.
2. Если user-facing answer можно построить из runtime `SKILL.md`, нельзя оставлять этот turn зависеть от best-effort tool path модели.
3. Нельзя принимать host replay за доказательство исправления для Moltis container/runtime path: hook code должен проверяться в той же среде исполнения, где он реально крутится.
4. Любой новый deterministic Telegram route должен сразу получать regression test не только на текст leakage, но и на отсутствие host-only зависимостей (`python3`, jq, locale/awk quirks).
