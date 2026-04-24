---
title: "Telegram intent routing broke under POSIX locale and broken-perl fallback"
date: 2026-04-24
severity: P2
category: shell
tags: [telegram, skills, hook, locale, perl, fallback, rca]
root_cause: "Repo-owned Telegram-safe guard classified Russian Telegram turns with locale-sensitive matching and trusted any discovered perl binary without a fallback path, so production POSIX locale and broken perl/python toolchains pushed valid skill CRUD and codex-update context turns into the wrong intent buckets."
---

# RCA: Telegram intent routing broke under POSIX locale and broken-perl fallback

**Дата:** 2026-04-24
**Статус:** In Progress
**Влияние:** Через Telegram пользователь не мог надёжно создавать, обновлять и удалять навыки; create/update turns ошибочно уходили в `skill_detail`, exact `codex-update` history/scheme questions деградировали в release summary или generic skill-detail, а no-perl/no-python fastpath терял fuzzy-match имени навыка.
**Контекст:** repair-lane `fix/telegram-skill-crud-routing`, `scripts/telegram-safe-llm-guard.sh`, `scripts/telegram-e2e-on-demand.sh`

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-04-24T00:00:00+03:00 |
| PWD | `/Users/rl/coding/moltinger/moltinger-main-fix-telegram-skill-crud-routing` |
| Shell | `zsh` |
| Git Branch | `fix/telegram-skill-crud-routing` |
| Git Status | modified runtime guard + UAT wrapper + component tests |
| Docker Version | production evidence collected from `docker exec moltis ...` |
| Disk Usage | not material |
| Memory | not material |
| Error Type | shell |

## Error Classification (Chain-of-Thought)

| Field | Value |
|-------|-------|
| Error Type | code/config |
| Confidence | high |
| Context Quality | sufficient |

### Hypotheses

| # | Hypothesis | Confidence |
|---|------------|------------|
| H1 | Russian skill CRUD detection depended on locale-sensitive regex/lowercasing and broke in production POSIX locale | 70% |
| H2 | Skill-name parsing/fuzzy fallback trusted a broken `perl` binary and therefore skipped the shell fallback path | 25% |
| H3 | The failure still came from Telegram Web probe artifacts rather than the live guard | 5% |

## Ошибка

Authoritative Telegram UAT на production показал два симптома одного класса:

1. точный запрос `Создай навык ...` не создаёт навык, а получает ответ в стиле `Не нашёл точного подтверждённого runtime-навыка ...`;
2. точные вопросы `Почему раньше ты присылал три одинаковых сообщения подряд...` и `Что изменилось в навыке codex-update после починки?` не попадают в context contract и отвечают release summary / generic skill summary.

Дополнительно component guard test показал вторую связанную поломку: при отсутствии рабочего `perl` и `python3` fastpath `Расскажи мне про навык telegram-lerner` терял fuzzy-match и отвечал generic summary вместо `telegram-learner`.

## Проверка прошлых уроков

**Проверенные источники:**
- `docs/LESSONS-LEARNED.md`
- `docs/rca/2026-04-01-telegram-skill-visibility-and-create-hook-modify-bypass.md`
- `docs/rca/2026-04-20-telegram-safe-maintenance-turns-fell-into-upstream-tool-boundary-errors.md`

**Релевантные прошлые RCA/уроки:**
1. `2026-04-01-telegram-skill-visibility-and-create-hook-modify-bypass` — уже фиксировал mismatch между hook modify и live Telegram path, поэтому текущий инцидент нужно было проверять authoritative probe, а не только synthetic hook replay.
2. `2026-04-20-telegram-safe-maintenance-turns-fell-into-upstream-tool-boundary-errors` — уже требовал отдельного intent routing для maintenance/debug; отсюда вывод, что новые Telegram-safe turn classes надо фиксировать на boundary-уровне, а не маскировать ответ.

**Что могло быть упущено без этой сверки:**
- можно было снова принять synthetic/local pass за доказательство исправности live Telegram;
- можно было бы чинить только поздний reply rewrite, не устранив ошибочную раннюю классификацию `skill_detail`.

**Что в текущем инциденте действительно новое:**
- production container работает в POSIX locale и ломает именно Russian CRUD classification;
- shell fallback path ломался не из-за полного отсутствия `perl`, а из-за присутствия неработающего бинаря, который guard считал рабочим.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему `Создай навык ...` и exact `codex-update` history questions попадали не в тот контракт? | Потому что guard классифицировал turn в неверный intent bucket (`skill_detail`/release summary) и terminalized именно его. | production audit for create: `message_received_direct_fastpath kind=skill_detail`; authoritative UAT failures for context questions: `semantic_codex_update_context_contract_mismatch` |
| 2 | Почему guard не распознал valid CRUD/context turn корректно? | Потому что Russian intent detectors использовали locale-sensitive matching, который в production POSIX locale возвращал false. | production reproduction в container: raw `grep -Eiq` patterns failed under `LC_CTYPE=\"POSIX\"`; local POSIX regression tests reproduced the miss before the fix |
| 3 | Почему helper override не компенсировал этот дефект? | Потому что helper опирался на Perl regex над ENV-строками без явного UTF-8 decode и на `tr`/casefold path, который в POSIX среде не давал надёжного Unicode поведения. | component failures: POSIX create/update and exact live codex-update context questions misclassified before the fix |
| 4 | Почему no-perl/no-python skill-detail fastpath деградировал до generic summary? | Потому что `trim_trailing_skill_token_punctuation` верил `command -v perl`; если бинарь находился, но завершался ошибкой, функция падала раньше shell fallback. | local reproduction with fake `perl`/`python3`: audit showed `requested=missing resolved=missing` and direct fastpath token `skill_detail:generic` |
| 5 | Почему это системная, а не точечная ошибка? | Потому что repo-owned hook/UAT contract не различал `perl exists` и `perl works`, а Telegram-safe Russian intent routing не был закреплён как locale-robust boundary rule для production runtime. | failures lived in repo-owned shell helpers (`telegram-safe-llm-guard.sh`, `telegram-e2e-on-demand.sh`), not in external Telegram transport |

## Корневая причина

Repo-owned Telegram-safe routing был написан с двумя неверными предпосылками:

1. Russian CRUD intent можно безопасно распознавать через locale-sensitive shell matching/ASCII lowercasing.
2. Найденный в PATH `perl` можно считать рабочим и не держать downstream shell fallback.

В production эти предпосылки нарушились одновременно: POSIX locale сорвал Russian intent classification для skill CRUD и `codex-update` context/history questions, а broken-perl path ломал fallback parsing/resolution. В результате valid user turns уходили в `skill_detail`/release summary, а typo/fuzzy matching деградировал до generic reply.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется в repo-owned hook helpers |
| □ Systemic? | yes | Ошибка затрагивает весь Telegram-safe CRUD boundary |
| □ Preventable? | yes | Нужны locale-robust helpers и fallback-on-exec-failure |

## Принятые меры

1. **Немедленное исправление:** в `scripts/telegram-safe-llm-guard.sh` добавлен UTF-8 decode-aware regex helper с корректным fallback, сужен create-intent до реальных CRUD-команд, `codex-update` context/scheduler/release intent переведены на тот же Unicode-safe matcher, добавлен fallback при нерабочем `perl` для trimming/parser path, исправлен deterministic skill-apply reply contract.
2. **Предотвращение:** те же parsing rules синхронизированы в `scripts/telegram-e2e-on-demand.sh`, чтобы authoritative UAT и live guard использовали одну и ту же Russian intent semantics.
3. **Документация:** эта RCA добавлена в `docs/rca/`, lessons index будет пересобран.

## Связанные обновления

- [ ] Новый файл правила создан (docs/rules/ или .claude/skills/)
- [ ] Краткая ссылка добавлена в CLAUDE.md (1-2 строки)
- [ ] Новые навыки созданы
- [x] Тесты добавлены
- [ ] Чеклисты обновлены

## Уроки

- Для Telegram-safe shell hooks недостаточно проверки `command -v`; нужен contract `tool exists and executes`, иначе fallback path не работает именно в деградированном окружении.
- Russian intent classification в production нельзя опирать на ASCII lowercasing/locale-sensitive grep; либо нужен explicit UTF-8 decode path, либо regex с гарантированным Unicode behavior.
- Если authoritative production evidence показал wrong intent bucket (`skill_detail`/release summary вместо context/CRUD), нельзя чинить только reply rewrite; нужно исправлять первичную turn classification.

## Regression Test (Optional - for code errors only)

**Test File:** `tests/component/test_telegram_safe_llm_guard.sh`, `tests/component/test_telegram_remote_uat_contract.sh`

**Test Status:**
- [x] Test created
- [x] Test fails (reproduces bug)
- [x] Fix applied
- [x] Test passes

---

*Создано вручную по production evidence и component regression tests*
