---
title: "Telegram skill-detail remained non-terminal and repo skills lacked a shared Telegram-safe summary contract"
date: 2026-04-05
severity: P2
category: process
tags: [telegram, moltis, skills, skill-detail, hooks, activity-log, rca]
root_cause: "Two systemic gaps stacked together. First, `skill_detail` classification still allowed later tool dispatch in some paths, so deterministic answers could regress back into Tavily or exec/tool failures and leak `Activity log`. Second, repo-managed user-facing skills did not all define the same Telegram-safe summary contract, so even deterministic replies were inconsistent and too dependent on operator-heavy SKILL.md body text."
---

# RCA: Telegram skill-detail general hardening

**Дата:** 2026-04-05
**Статус:** Resolved
**Влияние:** Пользователь мог получить странный, слишком внутренний или грязный ответ при вопросах про навыки, включая следы `Activity log` и tool-ошибок
**Контекст:** Telegram-safe skill detail path для repo-managed Moltis skills

## Ошибка

После серии частичных фиксов отдельные skill-detail запросы всё ещё были не полностью надёжны.

Симптомы выглядели так:

- бот отвечал слишком внутренним пересказом навыка вместо короткого user-facing описания;
- в хвост ответа мог попасть `Activity log`;
- при неудачном tool path наружу протекали ошибки вроде `missing 'command' parameter` или `missing 'query' parameter`;
- разные навыки вели себя по-разному, хотя пользовательский сценарий у них один и тот же: "расскажи про навык".

## Проверка прошлых уроков

**Проверенные источники:**

- `docs/LESSONS-LEARNED.md`
- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag skills`
- `./scripts/query-lessons.sh --tag hooks`
- [docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md](/Users/rl/coding/moltinger/moltinger-main-040-telegram-skill-detail-hardening/docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md)
- [docs/rca/2026-04-02-telegram-learner-skill-detail-hardening.md](/Users/rl/coding/moltinger/moltinger-main-040-telegram-skill-detail-hardening/docs/rca/2026-04-02-telegram-learner-skill-detail-hardening.md)
- official docs:
  - <https://docs.openclaw.ai/skills>
  - <https://docs.openclaw.ai/tools/creating-skills>

**Релевантные прошлые RCA/уроки:**

1. `2026-04-02-telegram-direct-fastpath-tail-was-not-terminal` уже показывал, что Telegram turn нельзя считать завершённым только потому, что ранний ответ уже сформирован.
2. `2026-04-02-telegram-learner-skill-detail-hardening` уже показывал, что user-facing summary нельзя строить из operator-heavy handbook-а.

**Что могло быть упущено без этой сверки:**

- что learner fix устранял частный экземпляр, но не весь класс skill-detail запросов;
- что allowlisted Tavily всё ещё должен быть запрещён внутри уже классифицированного deterministic skill-detail turn;
- что отсутствие единого frontmatter contract делает даже "чистые" skill-detail ответы неодинаковыми и хрупкими.

**Что в текущем инциденте действительно новое:**

1. Проблема оказалась общей для нескольких repo-managed skills, а не только для `telegram-learner`.
2. Корень уже не в одной shell-unsafe ветке, а в смешении двух режимов внутри одного user turn:
   - deterministic skill detail;
   - research/tool lane.
3. Стало очевидно, что для repo-managed skills нужен единый Telegram-safe frontmatter contract, а не индивидуальные ad hoc summary-fixes.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему skill-detail запросы всё ещё могли давать странные или грязные ответы? | Потому что после classification turn не всегда становился полностью terminal и мог уйти в tool path. | Локальный regression test `component_before_tool_guard_blocks_allowlisted_tavily_when_skill_detail_intent_is_persisted`; пользовательские примеры с `Activity log` и `missing 'command' parameter`. |
| 2 | Почему tool path вообще ещё был доступен? | Потому что `skill_detail` intent раньше не подавлял все `BeforeToolCall` paths как отдельный no-tool mode. | Изменение в `scripts/telegram-safe-llm-guard.sh`: новый branch `reason=skill_detail_tool_suppress`. |
| 3 | Почему даже чистый deterministic ответ выглядел нестабильно между навыками? | Потому что repo skills не имели общего user-facing summary contract и зависели от body-текста `SKILL.md`. | Разница между `telegram-learner`, `codex-update` и `post-close-task-classifier` до правок; новые frontmatter fields в `skills/*/SKILL.md`. |
| 4 | Почему это не было поймано раньше как общий класс проблем? | Потому что прошлые фиксы были инцидентными и лечили конкретные сломанные навыки или отдельные leakage paths. | Отдельные RCA 2026-04-02 закрывали `learner` и `fastpath tail`, но не общий repo-managed skill-detail contract. |
| 5 | Почему потребовалось системное hardening-решение? | Потому что Telegram-safe path для skill-detail должен быть детерминированным и однообразным для всех user-visible skills, иначе каждый новый skill может снова открыть ту же дыру. | Новый Speckit package `specs/040-telegram-skill-detail-hardening/`, static validation и multi-skill component coverage. |

## Корневая причина

Корневая причина была составной.

### 1. Skill-detail turn не был жёстко отделён от tool/research lane

Даже после классификации skill-detail turn всё ещё мог дойти до `BeforeToolCall`, включая allowlisted Tavily path. Это нарушало основной contract deterministic Telegram-safe ответа и открывало дорогу повторному leakage внутренних ошибок.

### 2. Repo-managed skills не имели общего Telegram-safe summary contract

User-facing навыки внутри `skills/` описывались неравномерно: где-то summary уже был приведён к короткому виду, где-то ответ всё ещё зависел от длинного body-текста `SKILL.md`. Это делало поведение skill-detail path неоднородным и затрудняло системную проверку.

## Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется в repo guard, skill contract и test coverage |
| □ Systemic? | yes | Затрагивает весь класс repo-managed skill-detail запросов |
| □ Preventable? | yes | Нужны terminal no-tool mode, static validation и shared authoring rule |

## Принятые меры

1. **Немедленное исправление:** `scripts/telegram-safe-llm-guard.sh` теперь переводит `skill_detail` в terminal no-tool mode и подавляет даже allowlisted Tavily/tool dispatch.
2. **Предотвращение:** для repo-managed user-facing skills введён общий frontmatter contract:
   - `telegram_summary`
   - `value_statement`
   - `source_priority`
   - `telegram_safe_note`
3. **Документация:** обновлён [docs/moltis-skill-agent-authoring.md](/Users/rl/coding/moltinger/moltinger-main-040-telegram-skill-detail-hardening/docs/moltis-skill-agent-authoring.md), а общее решение оформлено в Speckit package `specs/040-telegram-skill-detail-hardening/`.
4. **Верификация:** добавлены multi-skill component tests и static validation:
   - `tests/component/test_telegram_safe_llm_guard.sh`
   - `tests/static/test_config_validation.sh`

## Финальная live-верификация

Post-deploy проверка сначала дала ложный след: один из старых ответов в чате выглядел как будто прод всё ещё отвечает прежним англоязычным summary. Чтобы отделить stale chat от реального current turn, были запущены authoritative nonce-UAT runs на `main`.

- `24009502940`: prompt `Расскажи мне про навык codex-update и начни ответ с МЕТКА-20260405`
- `24009548220`: prompt `Расскажи мне про навык telegram-lerner и начни ответ с МЕТКА-TL-20260405`

Оба прогона завершились `passed` с `attribution_confidence=proven` и показали уже новый Telegram-safe summary:

- `codex-update` отвечает новым русским user-facing summary без `Activity log`;
- `telegram-learner` отвечает новым русским user-facing summary без `Activity log`, `missing 'command' parameter` и `missing 'query' parameter`.

Итог: старый англоязычный ответ оказался не новой прод-поломкой runtime, а stale/misattributed хвостом из предыдущего состояния чата. Корневая проблема текущего инцидента была именно в общем hardening skill-detail path и skill contract; после фикса живой пользовательский сценарий восстановлен.

## Связанные обновления

- [ ] Новый файл правила создан
- [ ] Краткая ссылка добавлена в CLAUDE.md
- [ ] Новые навыки созданы
- [x] Тесты добавлены
- [x] Чеклисты обновлены

## Уроки

1. Для Telegram-safe `skill_detail` нельзя смешивать deterministic answer mode и tool/research mode внутри одного turn.
2. Allowlist для инструментов не должен применяться автоматически к уже классифицированному skill-detail intent.
3. User-facing repo skills обязаны иметь единый frontmatter contract; body `SKILL.md` не должен быть единственным источником Telegram summary.
4. Частный фикс одного навыка не закрывает общий класс skill-detail regressions; нужен общий runtime + authoring contract.
5. Static validation на frontmatter и component coverage по нескольким skill families дешевле, чем повторные live hotfixes после leakage в Telegram.
6. При remote Telegram UAT старые сообщения в чате могут выглядеть как свежий регресс; nonce в prompt и authoritative attribution artefacts обязательны, если нужно отделить stale chat от реального current turn.

---

*Создано с помощью навыка rca-5-whys*
