---
title: "Moltis update proposal workflow failed with workflow-file issue due to forbidden secrets context in step if"
date: 2026-03-20
severity: P2
category: cicd
tags: [cicd, github-actions, workflow-validation, moltis-update]
root_cause: "Step-level if expression referenced secrets.*; GitHub rejected the workflow as invalid and produced push runs with no jobs"
---

# RCA: Moltis update proposal workflow failed with workflow-file issue due to forbidden secrets context in step if

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** Новый workflow `moltis-update-proposal.yml` не стартовал как валидный pipeline; на каждый push появлялся failed run типа `workflow file issue` без jobs.

## Ошибка

После добавления `Moltis Update Proposal` появились повторяющиеся failed runs:

- `23322917773`
- `23323154406`
- `23323336980`

Все они показывали `This run likely failed because of a workflow file issue` и не содержали ни одного job.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему workflow падал без jobs? | GitHub отклонял файл workflow на этапе валидации | runs `23322917773`, `23323154406`, `23323336980` |
| 2 | Почему валидация отклоняла файл? | В step `if:` использовались `secrets.*` | `.github/workflows/moltis-update-proposal.yml` до фикса |
| 3 | Почему это недопустимо? | Для step/job `if` контекст `secrets` запрещён контрактом GitHub Actions | `actionlint` error: `context "secrets" is not allowed here` |
| 4 | Почему мы не поймали это до push? | Локально не был запущен workflow-линтер до отправки изменений | отсутствие `actionlint` шага в локальной pre-check последовательности |
| 5 | Почему риск повторяемый? | В mixed-trigger workflow условные проверки секретов часто пишутся прямо в `if`, что приводит к тому же классу ошибки | повторяющиеся failed runs при каждом push |

## Корневая причина

Неверный паттерн проверки секретов в step-level `if`: использование `secrets.*` в выражении, где GitHub разрешает только ограниченный набор контекстов.

## Принятые меры

1. Логика проверки SMTP prerequisites вынесена в отдельный shell step `Evaluate email prerequisites` с output `should_send`.
2. Email step переведён на безопасный `if: steps.email.outputs.should_send == 'true'`.
3. Введена локальная валидация `actionlint` для workflow перед push.

## Уроки

1. Секреты проверяем в `run`/`env`, а не в `if` для jobs/steps.
2. Если run в GitHub показывает `workflow file issue` и `jobs=[]`, первым шагом запускать `actionlint`.
3. Для proposal-only workflow важно не только отсутствие deploy-логики, но и валидность синтаксиса/контекстов на этапе парсинга.

