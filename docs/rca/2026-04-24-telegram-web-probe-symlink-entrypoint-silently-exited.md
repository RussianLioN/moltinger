---
title: "Telegram Web probe silently exited when invoked through the active-root symlink path"
date: 2026-04-24
severity: P2
category: shell
tags: [telegram, probe, node, symlink, realpath, wrapper, uat, rca]
root_cause: "Repo-owned Telegram Web probe used an entrypoint check that compared import.meta.url against argv[1] without realpath normalization, so invocation through /opt/moltinger-active/... silently skipped main() and returned exit 0 with empty stdout."
---

# RCA: Telegram Web probe silently exited when invoked through the active-root symlink path

**Дата:** 2026-04-24
**Статус:** In Progress
**Влияние:** Post-deploy authoritative Telegram UAT could fail before semantic review with `jq: invalid JSON text passed to --argjson`, because the Telegram Web helper returned exit `0` and empty stdout instead of the required JSON payload.
**Контекст:** repair-lane `fix/telegram-web-probe-entrypoint-realpath`, `scripts/telegram-e2e-on-demand.sh`, `scripts/telegram-web-user-monitor.sh`, `scripts/telegram-web-user-probe.mjs`

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-04-24T04:00:00+03:00 |
| PWD | `/Users/rl/coding/moltinger/moltinger-main-fix-telegram-web-probe-entrypoint-realpath` |
| Shell | `zsh` |
| Git Branch | `fix/telegram-web-probe-entrypoint-realpath` |
| Git Status | modified probe + component tests + RCA |
| Docker Version | production evidence collected from `ssh root@ainetic.tech` |
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
| H1 | The authoritative wrapper corrupted probe JSON after a valid helper run | 20% |
| H2 | `telegram-web-user-monitor.sh` invoked the Node probe through a symlinked absolute path that made the probe silently skip `main()` | 75% |
| H3 | Telegram Web or browser automation itself stopped producing a reply for the exact prompt | 5% |

## Ошибка

После deploy `#216` первый же server-side authoritative UAT по exact `codex-update` question упал не на semantic mismatch, а раньше:

- `scripts/telegram-e2e-on-demand.sh` завершился с `jq: invalid JSON text passed to --argjson`;
- trace показал, что `normalize_from_authoritative_helper` получил пустой `helper_json`;
- прямой запуск `telegram-web-user-monitor.sh` на production host вернул `exit=0`, `stdout=0 bytes`, `stderr=0 bytes`;
- при этом прямой запуск `node scripts/telegram-web-user-probe.mjs ...` с теми же аргументами возвращал валидный JSON.

Дальнейшее сравнение трёх путей на production host показало:

1. `node scripts/telegram-web-user-probe.mjs ...` -> JSON есть;
2. `node /opt/moltinger-active/scripts/telegram-web-user-probe.mjs ...` -> `exit=0`, `stdout=0`;
3. `node $(readlink -f /opt/moltinger-active/scripts/telegram-web-user-probe.mjs) ...` -> JSON есть.

То есть silent failure был связан не с содержанием Telegram ответа, а с symlink-vs-realpath entrypoint drift.

## Проверка прошлых уроков

**Проверенные источники:**
- `docs/LESSONS-LEARNED.md`
- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag hooks`
- `./scripts/query-lessons.sh --tag shell`

**Релевантные прошлые RCA/уроки:**
1. `2026-04-24-telegram-utf8-matchers-depended-on-encode-pm` — уже показал, что authoritative Telegram UAT нельзя считать “вспомогательной обвязкой”; её helper contracts сами по себе являются production-critical surface.
2. `2026-04-14-telegram-chat-probe-skill-pointed-to-missing-wrapper-entrypoint` — уже предупреждал, что wrapper/entrypoint layer является public repo contract, а наличие underlying helper не спасает при broken invocation path.
3. `2026-04-02-telegram-skill-detail-fell-back-to-tool-error-leak` — уже зафиксировал, что host-only assumptions нельзя считать доказательством для live/container/runtime path.

**Что могло быть упущено без этой сверки:**
- можно было бы ошибочно чинить `capture_helper_json` и `jq --argjson`, хотя пустой JSON рождался раньше;
- можно было бы принять direct `node scripts/...` green за доказательство исправности helper wrapper, не заметив symlink absolute path drift в live active-root invocation.

**Что в текущем инциденте действительно новое:**
- Node probe itself had an entrypoint guard that silently skipped execution when `argv[1]` came through the symlinked active root.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему authoritative UAT упал на `jq --argjson` вместо semantic verdict? | Потому что wrapper получил пустой `helper_json` и попытался передать его в `--argjson helper`. | production trace of `telegram-e2e-on-demand.sh` |
| 2 | Почему `helper_json` оказался пустым? | Потому что `telegram-web-user-monitor.sh` вернул exit `0`, но не вывел JSON в stdout. | server reproduction: `stdout=0 bytes`, `stderr=0 bytes` |
| 3 | Почему thin helper не вывел JSON, хотя underlying probe умеет это делать? | Потому что helper вызывал Node probe через `/opt/moltinger-active/...`, а probe's entrypoint guard не считал такой symlink path корректным entrypoint. | direct comparison: relative path and realpath produced JSON; absolute symlink path produced empty stdout |
| 4 | Почему probe silently exited вместо явной ошибки? | Потому что `if (isEntrypoint()) await main();` просто не вызывал `main()` при false и не генерировал failure payload. | `scripts/telegram-web-user-probe.mjs` before fix |
| 5 | Почему это системная ошибка, а не разовый host quirk? | Потому что repo-owned production helper intentionally invokes the probe from the symlinked active deploy root, which is normal for this project. | `scripts/telegram-web-user-monitor.sh` builds `${SCRIPT_DIR}/telegram-web-user-probe.mjs` under `/opt/moltinger-active/...` |

## Корневая причина

The owning layer was the repo-managed Node probe entrypoint contract. `telegram-web-user-probe.mjs` compared `import.meta.url` and `process.argv[1]` without realpath normalization. When the probe was invoked through the normal symlinked active root (`/opt/moltinger-active/...`), `isEntrypoint()` returned false, `main()` was silently skipped, and the process exited `0` without emitting the required JSON payload.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется в probe entrypoint helper and regression tests |
| □ Systemic? | yes | Affects authoritative Telegram UAT through the standard active-root wrapper path |
| □ Preventable? | yes | Realpath-normalized entrypoint detection and symlink regression tests close the class |

## Принятые меры

1. **Немедленное исправление:** `telegram-web-user-probe.mjs` now resolves realpaths for both `import.meta.url` and `argv[1]` before deciding whether to run `main()`.
2. **Предотвращение:** added component regression coverage that proves a symlinked absolute path is still treated as a valid entrypoint.
3. **Документация:** this RCA records the server reproduction evidence; `docs/LESSONS-LEARNED.md` will be regenerated after adding the file.

## Связанные обновления

- [ ] Новый файл правила создан (docs/rules/ или .claude/skills/)
- [ ] Краткая ссылка добавлена в CLAUDE.md (1-2 строки)
- [ ] Новые навыки созданы
- [x] Тесты добавлены
- [ ] Чеклисты обновлены

## Уроки

- Для CLI/Node helper entrypoint checks symlink-vs-realpath is part of the public contract whenever the project uses active-root symlinks.
- `exit 0` без stdout в probe/helper path — это отдельный defect class; wrapper не должен first-fix-ить downstream JSON parsing, пока не доказано, что helper вообще вернул payload.
- Для Telegram/Web UAT надо тестировать не только imported functions, но и entrypoint resolution semantics, иначе live wrapper path остаётся без покрытия.

## Regression Test (Optional - for code errors only)

**Test File:** `tests/component/test_telegram_web_probe_correlation.sh`

**Test Status:**
- [x] Test created
- [x] Test reproduces the symlink entrypoint mismatch class
- [x] Fix applied
- [x] Test passes

---

*Создано вручную по production server reproduction и component regression tests*
