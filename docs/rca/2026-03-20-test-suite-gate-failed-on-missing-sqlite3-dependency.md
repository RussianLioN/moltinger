---
title: "Test Suite gate failed because CI runner missed sqlite3 dependency for component_codex_session_path_repair"
date: 2026-03-20
severity: P3
category: cicd
tags: [cicd, github-actions, test-suite, sqlite3, regression-prevention]
root_cause: "Test workflow installed jq only, while component suite required sqlite3; gate correctly failed on summary status=failed"
---

# RCA: Test Suite gate failed because CI runner missed sqlite3 dependency for component_codex_session_path_repair

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** PR checks блокировались на gate step (`summary.json status=failed`), merge был невозможен до исправления CI dependency.

## Ошибка

В run `23322926890` job `Run pr` выполнил почти весь lane, но suite `component_codex_session_path_repair` упал с:

- `sqlite3: command not found`
- итоговый gate получил `summary.status=failed` и завернул PR.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему упал gate? | Потому что aggregate status в `summary.json` был `failed` | Gate log `Evaluate summary.json` |
| 2 | Почему aggregate status был `failed`? | Потому что упал suite `component_codex_session_path_repair` | `/tmp/pr74-artifacts-1/summary.json` |
| 3 | Почему упал этот suite? | В runner отсутствовал бинарь `sqlite3` | `component_codex_session_path_repair.log` |
| 4 | Почему `sqlite3` отсутствовал? | В `test.yml` ставились только `jq` | `.github/workflows/test.yml` step `Install OS dependencies` |
| 5 | Почему это не было зафиксировано политикой заранее? | Не было static guard на обязательный `sqlite3` для component lane | отсутствие соответствующей проверки в `tests/static/test_config_validation.sh` до фикса |

## Корневая причина

CI workflow имел неполный список системных зависимостей для тестовых suite: dependency contract component lane и install step в `test.yml` разошлись.

## Принятые меры

1. В `.github/workflows/test.yml` добавлен `sqlite3` в OS dependencies.
2. В `tests/static/test_config_validation.sh` добавлен guard `static_test_workflow_installs_sqlite3_for_component_lane`.

## Уроки

1. Любая suite-зависимость на системный бинарь должна быть отражена в CI install step явно.
2. Для критичных test dependencies нужен static guard, иначе ошибка проявляется только в PR gate.
3. Gate по `summary.json` сработал корректно; исправлять нужно dependency contract, а не ослаблять gate.

