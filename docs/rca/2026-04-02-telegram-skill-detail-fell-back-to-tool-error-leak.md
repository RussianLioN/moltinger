---
title: "Telegram skill-detail requests lacked a deterministic runtime path, regressed on container drift, bypassed MessageSending rewrite, and reused skill-internal wording in user-visible replies"
date: 2026-04-02
tags: [telegram, moltis, skills, hooks, activity-log, mcp, tavily, rca]
root_cause: "The incident had five stacked causes. First, Telegram skill-detail turns had no deterministic runtime-owned route, so the model fell into exec/tool behavior. Second, the first repo-side fix still depended on host-only assumptions: python3-based summarization/fuzzy resolve, Perl snippets importing open.pm, and a fragile awk parser, while the live Moltis container lacked python3/open.pm and behaved differently. Third, once the reply degraded into plain prose without explicit Activity log markers, the MessageSending guard exited early for skill-detail turns, so the final deterministic rewrite never ran and the user still saw the wrong fallback text. Fourth, the supposedly fast deterministic path still had a hidden runtime bug: the Perl summary branch returned immediately even when it produced an empty result, so the function never reached the shell fallback in production; additionally, the shell fallback still contained a Bash-4-only lowercase expansion, which broke shell-only execution on Bash 3.2 during regression testing. Fifth, even after the deterministic reply began arriving, its wording still mirrored raw SKILL.md authoring structure ('Когда использовать', 'Workflow', 'Похоже, ты имеешь в виду'), so the authoritative Telegram probe correctly classified it as internal planning rather than clean user-facing prose."
---

# RCA: Telegram skill-detail requests lacked a deterministic runtime path, regressed on container drift, bypassed MessageSending rewrite, and reused skill-internal wording in user-visible replies

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
- после первой волны фикса остался ещё один слой: когда raw reply стал выглядеть как обычный текст про сломанный инструмент, а не как явный `Activity log`, финальный rewrite всё ещё мог не сработать;
- после починки final rewrite выяснилось, что сам быстрый `skill_detail` route в live контейнере вызывает `direct_fastpath`, но возвращает `reply_len=0`, то есть ломается уже на генерации deterministic summary.
- после починки runtime-builder и final rewrite обнаружился ещё один слой: deterministic reply уже приходил, но authoritative probe всё равно справедливо браковал его как внутреннее планирование из-за формулировок, взятых почти напрямую из структуры `SKILL.md`.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---------|--------|-------|
| 1 | Почему пользователь увидел плохой ответ вместо описания навыка? | Потому что turn ушёл в LLM/tool path и не был перехвачен deterministic skill-detail ответом. |
| 2 | Почему не было deterministic ответа? | Потому что guard покрывал visibility/template/create/apply/codex-update, но не покрывал запросы "расскажи про конкретный навык". |
| 3 | Почему модель вообще пыталась лезть в инструменты, хотя runtime `SKILL.md` уже существовал? | Потому что для такого типа вопроса в repo не было прямого runtime reader/summarizer из `SKILL.md`, и модель пыталась сама читать файл через tool path. |
| 4 | Почему после первого фикса пользователь всё ещё видел неправильный ответ, уже даже без явного `Activity log`? | Потому что runtime всё равно проваливался в exec/tool path, а модель возвращала уже не telemetry leak, а "чистый" prose fallback про то, что не может открыть `SKILL.md`. |
| 5 | Почему после этого быстрый deterministic route всё равно не отвечал сразу, а live turn доходил почти до timeout? | Потому что `build_skill_detail_reply_text` в проде мог вернуть пустую строку: Perl-ветка завершала функцию даже при пустом результате, не давая дойти до shell fallback, а сам shell fallback до этого ещё и содержал Bash-4-only `${var,,}`, несовместимый с Bash 3.2 в regression-среде. |
| 6 | Почему после починки fastpath authoritative UAT всё ещё падал, хотя ответ уже приходил? | Потому что deterministic summary был сформулирован как кусок внутренней инструкции навыка: `Похоже, ты имеешь в виду`, `Когда использовать`, `Workflow`, `Telegram-safe DM`. Probe правильно классифицировал такой текст как internal planning/error signature. |

## Корневая причина

Корневая причина оказалась пятислойной:

1. Изначально в `telegram-safe-llm-guard.sh` вообще отсутствовал deterministic runtime path для skill-detail вопросов о конкретном навыке.
2. После первой правки всплыл второй, более глубокий дефект portability:
   - skill-detail summary и fuzzy resolve зависели от `python3`;
   - Perl-ветка для summary/JSON parsing зависела от `use open qw(:std :utf8)`, а `open.pm` в live container отсутствует;
   - извлечение последнего user turn зависело от кастомного `awk`-парсинга `messages[]`;
   - в live Moltis container `python3` и `open.pm` отсутствовали, а этот self-made parser вёл себя иначе, чем на host replay.
3. После устранения portability-проблем остался ещё один дефект final-delivery logic:
   - ранний `MessageSending` early-exit пропускал "чистые", но неправильные skill-detail ответы без telemetry markers;
   - `skill_detail_reply_override` не исполнялся, если raw fallback выглядел как обычный текст, а не как `Activity log`.
4. После этого вскрылся ещё один дефект fastpath-реализации:
   - Perl-ветка в `build_skill_detail_reply_text` завершала функцию сразу, даже если фактически ничего не вывела;
   - из-за этого production fastpath не доходил до shell fallback и в audit появлялся `reply_len=0`;
   - в самом shell fallback оставалась непереносимая конструкция `${var,,}`, которая падала в Bash 3.2 и мешала полноценному regression-покрытию shell-only сценария.
5. Даже после этого deterministic reply всё ещё был не полностью user-facing:
   - summary строился слишком близко к authoring-структуре `SKILL.md`;
   - в пользовательский ответ утекали фразы уровня `Похоже, ты имеешь в виду`, `Когда использовать`, `Workflow`, `Telegram-safe DM`;
   - authoritative Telegram probe корректно считал это внутренним планированием, а не чистым кратким описанием навыка.

Из-за этого получилось два последовательных ложных сигнала успеха:
- сначала host replay показывал `direct_fastpath kind=skill_detail`, но live container всё ещё падал в generic `safe_lane`/tool path и выдавал пользователю ответ вида «не получилось прочитать файл навыка через инструменты»;
- затем, даже когда этот ответ уже приходил без явного `Activity log`, финальный rewrite его всё ещё не перехватывал из-за раннего выхода в `MessageSending`.
- после этого live audit уже показывал правильную классификацию `skill_detail`, но ранний fastpath всё равно не отправлял ответ сразу, потому что builder summary возвращал пустой результат.
- после этого fastpath уже стабильно отправлял deterministic summary, но сам текст summary ещё пришлось переписать в нормальную пользовательскую форму, чтобы убрать совпадение с `internal_planning`/`error_signature` эвристиками authoritative UAT.

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
   - `build_skill_detail_reply_text` теперь умеет собирать deterministic summary через `perl` без `python3`;
   - Perl snippets больше не зависят от `open.pm`, вместо этого используют portable `binmode`.
5. Добавлены regression tests:
   - direct fastpath для `Расскажи мне про навык telegram-lerner`;
   - direct fastpath для skill-detail даже при сломанном `python3` и с prior history;
   - MessageSending rewrite для реального leakage-pattern с `missing 'command' parameter`;
   - MessageSending rewrite для prod-паттерна, где raw reply уже не содержит `Activity log`, а выглядит как «не могу открыть `SKILL.md`».
6. Исправлен final-delivery early-exit:
   - `MessageSending` больше не делает ранний `exit 0` для текущего или persisted `skill_detail` turn;
   - это гарантирует, что блок `skill_detail_reply_override` успеет переписать даже "чистый", но неправильный prose fallback.
7. Исправлен сам builder для fastpath:
   - Perl-ветка теперь возвращает ответ только если реально вывела непустой summary;
   - при пустом или неуспешном Perl-результате функция продолжает путь к Python/shell fallback;
   - shell fallback получил простой skeleton-match по имени навыка без гласных, чтобы даже без `perl/python` тянуть типовую опечатку `telegram-lerner -> telegram-learner`;
   - shell fallback больше не использует Bash-4-only `${var,,}` и остаётся совместимым с Bash 3.2.
8. Переписан user-facing текст skill-detail summary:
   - убраны формулировки `Похоже, ты имеешь в виду`, `Когда использовать`, `Workflow`, `Telegram-safe DM`;
   - deterministic reply теперь собирается как нейтральное краткое описание навыка, его источников и основных шагов работы;
   - regression tests дополнительно проверяют не только наличие полезной информации, но и отсутствие этих внутренних фраз.

## Проверка

- `bash -n scripts/telegram-safe-llm-guard.sh`
- `bash -n tests/component/test_telegram_safe_llm_guard.sh`
- `bash tests/component/test_telegram_safe_llm_guard.sh`

## Уроки

1. Skill contract в Telegram должен покрывать не только visibility/create/template, но и detail/describe path для уже существующих runtime skills.
2. Если user-facing answer можно построить из runtime `SKILL.md`, нельзя оставлять этот turn зависеть от best-effort tool path модели.
3. Нельзя принимать host replay за доказательство исправления для Moltis container/runtime path: hook code должен проверяться в той же среде исполнения, где он реально крутится.
4. Любой новый deterministic Telegram route должен сразу получать regression test не только на текст leakage, но и на отсутствие host-only зависимостей (`python3`, `open.pm`, jq, locale/awk quirks).
5. Для детерминированных Telegram-сценариев нельзя полагаться только на поиск явных telemetry-маркеров. Если turn уже классифицирован как `skill_detail`, final `MessageSending` rewrite должен доходить до конца даже тогда, когда raw fallback выглядит как обычный пользовательский текст.
6. Для helper-функций fastpath нельзя делать "ранний return по ветке реализации" без проверки, что ветка реально выдала непустой результат. Иначе nominal fastpath будет числиться вызванным, но фактически продолжит сессию в медленный LLM/tool path.
7. User-facing deterministic reply нельзя собирать как сырой пересказ authoring-разметки `SKILL.md`. Даже без явного `Activity log` probe и пользователь справедливо воспримут такие маркеры как внутреннюю служебную речь.
