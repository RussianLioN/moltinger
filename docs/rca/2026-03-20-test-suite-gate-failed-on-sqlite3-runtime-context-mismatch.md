---
title: "Test Suite gate failed again because sqlite3 was installed on host runner but missing in test-runner container runtime"
date: 2026-03-20
severity: P2
category: cicd
tags: [cicd, github-actions, test-suite, sqlite3, container-runtime]
root_cause: "Dependency fix targeted the host runner, while pr lane executes component suite inside test-runner container where sqlite3 was still absent"
---

# RCA: Test Suite gate failed again because sqlite3 was installed on host runner but missing in test-runner container runtime

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** PR `#74` снова блокировался gate step, несмотря на прошлый фикс `apt-get install sqlite3` в workflow.

## Ошибка

В run `23323436265`:

- `Run pr` завершился `success`, но aggregate `summary.status=failed`;
- `Gate` упал на `Gate failed because summary.json status is failed`;
- fail-case снова: `component_codex_session_path_repair`.

Лог suite:

- `/workspace/tests/component/test_codex_session_path_repair.sh: line 37: sqlite3: command not found`

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему gate снова упал? | Потому что в `summary.json` остался failed suite | run `23323436265`, job `Gate` |
| 2 | Почему упал тот же suite? | В runtime suite не было `sqlite3` | artifact log `component_codex_session_path_repair.log` |
| 3 | Почему `sqlite3` не было, хотя workflow его ставил? | Установка была на host runner, а suite исполнялась в `test-runner` контейнере | `tests/run.sh` (`run_locally_in_container` для `pr` lane) |
| 4 | Почему suite исполнялась в контейнере? | `pr` lane включает `integration_local`, что включает container recursion для всего запуска | `tests/run.sh` (`lane_needs_stack`, `group_to_lanes(pr)`) |
| 5 | Почему это не было покрыто static policy? | Guard проверял только `.github/workflows/test.yml`, но не `tests/Dockerfile.runner` | `tests/static/test_config_validation.sh` до фикса |

## Корневая причина

Dependency contract был зафиксирован в неправильном execution-context: `sqlite3` добавили только на host runner, тогда как фактическое исполнение проблемной suite происходило внутри `test-runner` контейнера.

## Принятые меры

1. В `tests/Dockerfile.runner` добавлен пакет `sqlite3`.
2. Static guard обновлён: теперь проверяет `sqlite3` и в workflow host dependencies, и в `tests/Dockerfile.runner`.
3. Выполнено локальное воспроизведение CI-контракта:
   - `./tests/run.sh --lane pr --filter component_codex_session_path_repair --json ...`
   - результат: `passed`.

## Уроки

1. Для CI обязательно фиксировать *execution context* (host vs container) до исправления dependency-ошибок.
2. Static guard должен валидировать именно тот runtime, где реально исполняется suite.
3. “Повторный падёж того же кейса после частичного фикса” — сигнал, что исправлен не корень, а соседний слой инфраструктуры.

