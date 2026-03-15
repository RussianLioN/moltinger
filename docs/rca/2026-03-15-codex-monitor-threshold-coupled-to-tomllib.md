---
title: "Codex monitor threshold coupled to tomllib availability"
date: 2026-03-15
severity: P3
category: cicd
tags: [ci, tests, codex, beads, python, tomllib]
root_cause: "Monitor Beads-resolution tests assumed an upgrade-now recommendation, but CI downgraded the fixture to upgrade-later when python3.tomllib was unavailable."
---

# RCA: Codex monitor threshold coupled to tomllib availability

**Дата:** 2026-03-15
**Статус:** Resolved
**Влияние:** PR/main `Test Suite` стабильно падал на двух кейсах `component_codex_cli_update_monitor`, хотя сам resolver path работал корректно.
**Контекст:** Post-merge разбор после `feat/beads-root-write-guard`, follow-up PR `#69`.

## Ошибка

В GitHub Actions два monitor-теста ожидали implicit upsert/block path, но получали `issue_action.mode=skipped`.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему monitor-тесты падали? | `issue_action.mode` оставался `skipped`, а не `created`/explicit block path. | `component_codex_cli_update_monitor.log` из ранна `23115604479` |
| 2 | Почему `issue_action` оставался `skipped`? | `perform_issue_sync` останавливался на threshold gate раньше, чем path доходил до проверки Beads DB routing. | `report.json.issue_action.notes` в diagnostic log |
| 3 | Почему threshold gate срабатывал? | Recommendation в CI была `upgrade-later`, а тесты рассчитывали на action при дефолтном `--issue-threshold upgrade-now`. | `report.json.recommendation=upgrade-later` |
| 4 | Почему recommendation в CI была слабее, чем локально? | В CI monitor не смог распарсить config traits и не нашёл repo-workflow signals. | Evidence: `python3 tomllib is unavailable; config traits not parsed` |
| 5 | Почему тесты зависели от этого? | Они проверяли Beads-resolution path, но не фиксировали threshold явно, поэтому неявно зависели от optional Python feature availability в runner-е. | Текущий test contract в `tests/component/test_codex_cli_update_monitor.sh` |

## Корневая причина

Тесты смешали две независимые вещи: `recommendation` classification и Beads DB resolution. Из-за этого CI-only отсутствие `python3.tomllib` меняло recommendation до `upgrade-later`, а тесты интерпретировали это как поломку resolver path.

## Принятые меры

1. **Немедленное исправление:** в двух Beads-resolution monitor-тестах threshold задан явно через `--issue-threshold upgrade-later`.
2. **Предотвращение:** test contract больше не зависит от optional `tomllib` availability в CI runner-е.
3. **Документация:** root cause зафиксирован в этом RCA.

## Уроки

- Тесты на routing/mutation path должны явно фиксировать gating inputs и не зависеть от environment-sensitive recommendation heuristics.
- Optional parser availability вроде `tomllib` легко превращает “integration-like” тест в CI-specific flaky contract, если threshold не закреплён явно.
