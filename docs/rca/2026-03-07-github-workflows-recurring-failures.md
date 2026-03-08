---
title: "Повторяющиеся падения GitHub Actions workflow (Drift + Deploy)"
date: 2026-03-07
severity: P2
category: cicd
tags: [github-actions, gitops, drift-detection, deploy, permissions]
root_cause: "Хрупкие проверки и зависимость от labels/permissions без graceful fallback приводили к ложным падениям workflow"
---

# RCA: Повторяющиеся падения GitHub Actions workflow (Drift + Deploy)

**Дата:** 2026-03-07
**Статус:** Resolved
**Влияние:** Среднее; шумные false-positive падения CI/CD и потеря доверия к алертам
**Контекст:** Анализ инцидентов из GitHub Actions email alerts и стабилизация workflow без усложнения пайплайна

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-07T07:19:57Z |
| PWD | /Users/rl/.codex/worktrees/27e8/moltinger |
| Shell | /bin/zsh |
| Git Branch | codex/better-deploy |
| Git Commit | e412200 |
| Git Status | modified (workflow files + RCA report) |
| Docker Version | Docker version 29.2.1, build a5c7197 |
| Disk Usage | 5% used on `/` |
| Memory | macOS vm_stat collected |
| Error Type | cicd |

## Error Classification (Chain-of-Thought)

| Field | Value |
|-------|-------|
| Error Type | process/config |
| Confidence | high |
| Context Quality | sufficient |

### Hypotheses

| # | Hypothesis | Confidence |
|---|------------|------------|
| H1 | Workflow падал из-за недостаточных permissions при работе с GitHub Issues labels | 85% |
| H2 | Smoke-check в deploy слишком жёстко проверял только один формат Traefik rule | 90% |
| H3 | Частота ошибок увеличивалась из-за отсутствия non-blocking fallback для вторичных операций (issue labels) | 75% |

## Ошибка

Наблюдались повторяющиеся ошибки в GitHub Actions:

1. `GitOps Drift Detection` run `22793973357` (2026-03-07T06:37:37Z) падал на шаге `Create issue on drift` с ошибкой:
   - `error fetching labels: GraphQL: Resource not accessible by integration (repository.labels)`
2. `Deploy Moltis` run `22793996452` (2026-03-07T06:39:12Z) падал на шаге `Run smoke tests`:
   - проверка ожидала только `Host(\`moltis.ainetic.tech\`)`,
   - но в `docker-compose.prod.yml` фактически использовался templated вариант `Host(\`${MOLTIS_DOMAIN:-moltis.ainetic.tech}\`)`.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему workflow падали часто? | Из-за hard-fail на вторичных/хрупких проверках | Runs `22793973357`, `22793996452` завершились `failure` |
| 2 | Почему `GitOps Drift Detection` падал при создании issue? | Использовалась label-зависимая операция без гарантированных прав и fallback | Лог: `Resource not accessible by integration (repository.labels)` |
| 3 | Почему `Deploy Moltis` падал при успешном фактическом деплое? | Smoke test проверял только один строковый вариант Host rule | Лог run `22793996452`: expected static rule, found templated rule |
| 4 | Почему такие проверки дошли в `main`? | Проверки workflow ориентированы на "строгое соответствие", но без допусков на эквивалентные конфигурации и без graceful degradation | В `deploy.yml` был один `grep`; в `gitops-drift-detection.yml` не было non-blocking path |
| 5 | Почему ошибка стала повторяющейся? | Не было унифицированного паттерна "critical vs non-critical step" в GitHub Actions | Повторяющиеся alert-падения при том, что суть drift detection/health уже была отработана |

## Корневая причина

В workflow отсутствовал системный шаблон надежности: операции уведомления (issue/labels) и проверка конфигурации использовали brittle правила и hard-fail без учета эквивалентных конфигураций и ограничений `GITHUB_TOKEN`.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется правками workflow |
| □ Systemic? | yes | Паттерн применим к нескольким pipeline |
| □ Preventable? | yes | Через least-privilege permissions + graceful fallback + tolerant checks |

## Принятые меры

1. **Немедленное исправление:** В `gitops-drift-detection.yml` добавлены `permissions` и non-blocking логика создания issue (без hard dependency на labels).
2. **Предотвращение:** В `deploy.yml` smoke-check Traefik Host rule теперь принимает оба валидных формата: static и templated.
3. **Документация:** Создан этот RCA-отчёт; уроки добавлены в индекс lessons.

## Связанные обновления

- [X] RCA-отчёт создан в `docs/rca/`
- [X] Раздел `## Уроки` добавлен
- [X] Индекс уроков пересобран (`./scripts/build-lessons-index.sh`)
- [ ] Новый файл правила создан (не требовалось)
- [ ] Ссылка в CLAUDE.md добавлена (не требовалось)

## Уроки

1. **Не завязывать алертинг на labels как обязательный путь** — issue creation должна деградировать в warning, а не валить job.
2. **Smoke-тесты должны проверять семантику, а не единственную строку** — эквивалентные конфиги (static/templated) должны считаться валидными.
3. **Разделять критичные и некритичные шаги CI/CD** — failure должен означать реальный инцидент, а не проблему оформления уведомления.

---

*Создано по протоколу RCA (5 Why) для инцидентов GitHub Actions runs `22793973357` и `22793996452`.*
