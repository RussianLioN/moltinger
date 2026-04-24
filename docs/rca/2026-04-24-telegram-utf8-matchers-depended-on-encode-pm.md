---
title: "Telegram UTF-8 matchers depended on Encode.pm that the live container did not ship"
date: 2026-04-24
severity: P2
category: shell
tags: [telegram, hooks, shell, perl, utf8, encode, codex-update, rca]
root_cause: "Repo-owned Telegram-safe UTF-8 regex helpers depended on Perl Encode.pm, but the live Moltis container shipped perl without that module, so the exact codex-update context questions silently fell back to POSIX-unsafe matching and were classified into the wrong intent bucket."
---

# RCA: Telegram UTF-8 matchers depended on Encode.pm that the live container did not ship

**Дата:** 2026-04-24
**Статус:** In Progress
**Влияние:** После merge/deploy PR `#215` exact Telegram questions про историю дублей `codex-update` всё ещё отвечали release summary вместо context contract, хотя локальные POSIX tests уже были зелёными.
**Контекст:** repair-lane `fix/telegram-safe-unicode-runtime-no-encode`, `scripts/telegram-safe-llm-guard.sh`, `scripts/telegram-e2e-on-demand.sh`

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-04-24T03:00:00+03:00 |
| PWD | `/Users/rl/coding/moltinger/moltinger-main-fix-telegram-safe-unicode-runtime-no-encode` |
| Shell | `zsh` |
| Git Branch | `fix/telegram-safe-unicode-runtime-no-encode` |
| Git Status | modified guard + UAT wrapper + component tests + RCA |
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
| H1 | Live container still ran an old hook version after deploy | 15% |
| H2 | New UTF-8 matcher logic still relied on a Perl module missing from production, so runtime silently fell back to POSIX-unsafe matching | 80% |
| H3 | Telegram Web authoritative probe was again misclassifying a correct reply | 5% |

## Ошибка

После deploy PR `#215` authoritative Telegram UAT на exact prompt `Почему раньше ты присылал три одинаковых сообщения подряд про обновление Codex CLI?` всё ещё падал с `semantic_codex_update_context_contract_mismatch`.

Production evidence showed:

1. audit log on live container still classified the exact question as `direct_fastpath kind=codex_update ... mode=release`;
2. captured `MessageReceived` payload contained the exact Russian user text, so the input itself was correct;
3. manual replay of that payload inside the production container crashed with `Can't locate Encode.pm in @INC`;
4. the container had `/usr/bin/perl`, but not the `Encode.pm` module;
5. local tests were green because the host perl did ship `Encode.pm`.

То есть проблема уже не была в формулировке intent patterns и не в Telegram probe. Проблема была в том, что repo-owned UTF-8 matcher helper использовал host-only Perl dependency.

## Проверка прошлых уроков

**Проверенные источники:**
- `docs/LESSONS-LEARNED.md`
- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag hooks`
- `./scripts/query-lessons.sh --tag shell`

**Релевантные прошлые RCA/уроки:**
1. `2026-04-24-telegram-skill-crud-posix-locale-and-perl-fallback` — уже зафиксировал, что Telegram-safe routing нельзя опирать на locale-sensitive shell matching и что `command -v perl` не равен “perl рабочий”.
2. `2026-04-02-telegram-skill-detail-fell-back-to-tool-error-leak` — уже предупреждал, что для Telegram-safe сценариев нельзя считать host-only зависимости допустимыми, если контейнерный runtime их не гарантирует.
3. `2026-04-23-telegram-direct-fastpath-before-llm-must-block` — уже отделял `hook сгенерировал правильный JSON` от `runtime реально прошёл нужную ветку`; здесь тот же принцип проявился на matcher helper.

**Что могло быть упущено без этой сверки:**
- можно было бы ошибочно считать, что PR `#215` “почти починил” проблему, и лечить оставшийся симптом новыми reply-rewrite эвристиками;
- можно было бы продолжить верить локальному POSIX replay вместо проверки container/runtime execution path.

**Что в текущем инциденте действительно новое:**
- новый matcher path сам был Unicode-aware только на хосте, потому что зависел от `Encode.pm`, отсутствующего в live container.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему exact `codex-update` history question после deploy всё ещё уходил в release summary? | Потому что live audit по-прежнему классифицировал turn как `mode=release`, а не `mode=context`. | production audit: `direct_fastpath kind=codex_update ... mode=release` |
| 2 | Почему live runtime не использовал уже добавленный UTF-8 matcher как ожидалось? | Потому что helper вызывал `perl -MEncode=...`, а в контейнере этого модуля не было. | manual payload replay in container: `Can't locate Encode.pm in @INC` |
| 3 | Почему это не было видно по локальным тестам до merge? | Потому что локальный perl на хосте модуль `Encode.pm` имел, поэтому matcher branch проходил и тесты были зелёными. | local suite `160/160` green before this follow-up; production-only replay failed |
| 4 | Почему failure снова деградировал именно в wrong intent bucket, а не в явный hard crash? | Потому что helper path silently fell back from Perl matcher to plain `grep -Eiq`, а под `LC_CTYPE=POSIX` этот fallback не держит Russian uppercase/context semantics. | live symptom returned after deploy; prior RCA and local reproduction showed POSIX fallback misclassifies the same question |
| 5 | Почему это системная, а не единичная ошибка? | Потому что repo-owned Telegram-safe helper был написан с неявной предпосылкой “perl ships Encode.pm”, хотя production contract этого не гарантирует. | both `telegram-safe-llm-guard.sh` and `telegram-e2e-on-demand.sh` used the same `-MEncode=` dependency |

## Корневая причина

Repo-owned Telegram-safe UTF-8 regex helpers were implemented with a non-portable Perl dependency (`Encode.pm`). The live Moltis container had perl installed but did not ship that module, so the helper failed and silently fell back to POSIX-unsafe shell matching. As a result, exact Russian `codex-update` context/history questions were again classified into the wrong intent bucket even though the higher-level routing logic had already been fixed in the previous PR.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется в repo-owned shell helpers and regression tests |
| □ Systemic? | yes | Один и тот же helper path used by live guard and authoritative UAT wrapper |
| □ Preventable? | yes | Нужен module-free UTF-8 decode path and explicit regression coverage for host-only Perl deps |

## Принятые меры

1. **Немедленное исправление:** в `scripts/telegram-safe-llm-guard.sh` и `scripts/telegram-e2e-on-demand.sh` заменён `Encode.pm`-based decode на built-in `utf8::decode`, не требующий внешнего Perl модуля.
2. **Предотвращение:** добавлены regression tests, которые:
   - проверяют отсутствие `Encode.pm` dependency в guard и UAT wrapper;
   - воспроизводят exact live `codex-update` context question через подменный `perl`, который специально заваливает любой вызов с `Encode`.
3. **Документация:** создан этот RCA; `docs/LESSONS-LEARNED.md` будет пересобран после добавления файла.

## Связанные обновления

- [ ] Новый файл правила создан (docs/rules/ или .claude/skills/)
- [ ] Краткая ссылка добавлена в CLAUDE.md (1-2 строки)
- [ ] Новые навыки созданы
- [x] Тесты добавлены
- [ ] Чеклисты обновлены

## Уроки

- Для Telegram-safe shell helpers недостаточно требования “perl есть”; нужен контракт “используем только built-in perl surface, гарантированную в live container”.
- Если локальный POSIX regression зелёный, но authoritative production UAT всё ещё красный, следующим источником истины должен быть container replay exact payload-а, а не ещё одна эвристика переписывания ответа.
- Shared helper logic нужно проверять не только на корректность текста/intent, но и на отсутствие host-only module dependencies.

## Regression Test (Optional - for code errors only)

**Test File:** `tests/component/test_telegram_safe_llm_guard.sh`, `tests/component/test_telegram_remote_uat_contract.sh`

**Test Status:**
- [x] Test created
- [x] Test reproduces the live container dependency gap
- [x] Fix applied
- [x] Test passes

---

*Создано вручную по live container evidence и component regression tests*
