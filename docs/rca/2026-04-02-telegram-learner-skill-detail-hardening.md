---
title: "Telegram learner skill-detail still leaked tool failures because the summary builder kept a shell-unsafe Perl branch and the skill contract was too operator-heavy"
date: 2026-04-02
tags: [telegram, moltis, skills, learner, hooks, activity-log, rca]
root_cause: "Two causes stacked. First, `build_skill_detail_reply_text()` still entered an optional Perl branch that was shell-unsafe under `set -u` in the live hook path and aborted with `display_summary: unbound variable` before any deterministic reply could be sent. Second, `skills/telegram-learner/SKILL.md` still looked like a long operator handbook, so even when a deterministic summary was produced it was too close to internal workflow prose instead of a concise Telegram-safe user answer. The fix was to rewrite learner skills as thin official-first contracts, localize the broken Perl path to the skill-detail builder only, and prove the new value-first replies with regression coverage."
---

# RCA: Telegram learner skill-detail hardening

## Ошибка

На вопрос вида:

- `Расскажи мне про навык telegram-lerner`

бот всё ещё мог:

- отвечать странным полумета-текстом вместо краткого описания навыка;
- протекать в `Activity log`;
- показывать `missing 'command' parameter`;
- дублировать слишком внутренние формулировки про workflow и инструментальное чтение `SKILL.md`.

## Проверка прошлых уроков

Проверены:

- [docs/rca/2026-04-02-telegram-skill-detail-fell-back-to-tool-error-leak.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-02-telegram-skill-detail-fell-back-to-tool-error-leak.md)
- [docs/rca/2026-04-02-telegram-skill-detail-single-inband-path-regressed-live-runtime.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-02-telegram-skill-detail-single-inband-path-regressed-live-runtime.md)
- [docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-02-telegram-direct-fastpath-tail-was-not-terminal.md)
- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag skills`

Что уже было известно:

1. Telegram-safe skill flows нельзя оставлять на best-effort tool path модели.
2. Live Telegram требует deterministic reply contract и явные regression-проверки на leakage.
3. User-facing summary нельзя строить как сырой пересказ операторского handbook-а.

Что оказалось новым:

1. Даже после прошлых фиксов внутри `build_skill_detail_reply_text()` оставалась отдельная optional Perl-ветка, которая роняла hook до отправки deterministic ответа.
2. Ошибка происходила раньше final rewrite, поэтому пользователь снова видел не корень, а следствие в виде tool failure/`Activity log`.
3. Сам `telegram-learner` был оформлен как длинный operator workflow, а не как тонкий learner contract для Telegram-safe detail reply.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---------|--------|-------|
| 1 | Почему пользователь снова видел странный ответ и `Activity log`? | Потому что skill-detail turn не дошёл до безопасного deterministic текста и провалился в tool/fallback path. |
| 2 | Почему deterministic skill-detail ответ не отправился? | Потому что `build_skill_detail_reply_text()` падал раньше генерации ответа. |
| 3 | Почему он падал? | Потому что optional Perl-ветка summary-builder-а была shell-unsafe в реальном hook path и под `set -u` роняла скрипт с `display_summary: unbound variable`. |
| 4 | Почему даже после получения summary ответ выглядел не по-пользовательски? | Потому что `telegram-learner/SKILL.md` был handbook-ом с operator workflow, фазами и внутренними формулировками, а не коротким learner contract для Telegram. |
| 5 | Почему тесты не закрывали весь класс проблемы раньше? | Потому что до этой итерации не было отдельного набора ожиданий на concise learner-summary, похожий learner-skill и shell-only path без Python. |

## Корневая причина

Корневая причина была двойной.

### 1. Нестабильный optional Perl path в skill-detail builder

`build_skill_detail_reply_text()` всё ещё содержал Perl summary branch. На реальном hook path под строгим shell mode этот branch не был надёжным и падал с:

- `display_summary: unbound variable`

Из-за этого deterministic skill-detail ответ не отправлялся вообще, а дальше turn снова скатывался в model/tool failure pattern.

### 2. Неправильный формат самого learner skill

`skills/telegram-learner/SKILL.md` был оформлен как длинный внутренний runbook:

- phase-by-phase workflow;
- сохранение knowledge;
- operator-heavy guardrails;
- служебные детали, не предназначенные для короткого Telegram ответа.

Когда такой skill-summary даже успешно строился, он получался слишком похож на внутреннюю инструкцию, а не на clean user-facing description.

## Исправление

Сделано:

1. `skills/telegram-learner/SKILL.md` переписан как thin official-first learner contract:
   - `telegram_summary`
   - `value_statement`
   - `source_priority`
   - `telegram_safe_note`
2. Добавлен похожий regression-skill:
   - `skills/openclaw-improvement-learner/SKILL.md`
3. Обновлён authoring guide:
   - [docs/moltis-skill-agent-authoring.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/moltis-skill-agent-authoring.md)
   - новый паттерн: learner skill для Telegram должен разделять explainer surface и operator surface.
4. В `scripts/telegram-safe-llm-guard.sh` локализован дефектный путь:
   - broken Perl-ветка отключена только для `build_skill_detail_reply_text()`;
   - остальные Perl-based helper paths оставлены рабочими.
5. Builder теперь стабильно доходит до Python/shell fallback и выдаёт value-first summary без workflow/operator markup.
6. Обновлены regression tests:
   - concise learner summary;
   - negative checks на `Activity log`, `SKILL.md`, file paths и internal wording;
   - coverage для похожего learner skill;
   - shell-only skill-detail path без Python/Perl.
7. Собран отдельный guidance artifact с official/community input:
   - [docs/research/2026-04-02-telegram-learner-official-community-guidance.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/research/2026-04-02-telegram-learner-official-community-guidance.md)

## Проверка

- `bash tests/component/test_telegram_safe_llm_guard.sh`
- `bash tests/component/test_telegram_remote_uat_contract.sh`
- `make codex-check`

Локальный результат после фикса:

- `test_telegram_safe_llm_guard.sh` → `101/101`
- `test_telegram_remote_uat_contract.sh` → `36/36`
- `make codex-check` → passed

## Уроки

1. Optional implementation branch нельзя оставлять в critical Telegram-safe path, если branch не доказан в той же shell/runtime среде.
2. Learner skill для Telegram должен быть thin contract, а не operator handbook.
3. `SKILL.md` authoring format напрямую влияет на user-facing reply hygiene, если summary строится deterministically из runtime файла.
4. Для learner-skill reply нужны отдельные negative checks на internal wording, а не только на явные `Activity log` markers.
5. Исправление одной leakage-эвристики недостаточно, если сам deterministic summary-path ещё может аварийно завершаться до отправки ответа.
