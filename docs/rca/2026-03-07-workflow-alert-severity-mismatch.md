---
title: "Ложные error-сигналы в успешных GitHub workflow"
date: 2026-03-07
severity: P3
category: cicd
tags: [github-actions, alerts, rca, drift-detection, signal-noise]
root_cause: "Несоответствие уровня лог-аннотации (`::error::`) фактической non-blocking политике workflow"
---

# RCA: Ложные error-сигналы в успешных GitHub workflow

**Дата:** 2026-03-07
**Статус:** Resolved
**Влияние:** Среднее; повышенный шум в операционных сигналах и ложное впечатление, что свежие workflow «падают»
**Контекст:** Проверка жалобы на ошибки после недавних изменений CI/CD

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-07T07:54:33Z |
| PWD | /Users/rl/.codex/worktrees/27e8/moltinger |
| Shell | /bin/zsh |
| Git Branch | codex/better-deploy |
| Error Type | cicd |

## Ошибка

Пользователь наблюдал «ошибки» в workflow после изменений. Проверка логов показала:

1. Последние прогоны на `main` успешны:
   - `Deploy Moltis` run `22795114509` — `success`
   - `Test Suite` run `22795114507` — `success`
   - `GitOps Drift Detection` run `22794925363` — `success`
2. Реальные `failure` были ранее:
   - `22793996452` (Deploy Moltis, 2026-03-07T06:39:12Z)
   - `22793973357` (GitOps Drift Detection, 2026-03-07T06:37:37Z)
3. Обнаружено несоответствие severity:
   - в drift workflow при `drift_found=true` использовалась аннотация `::error::`, хотя job задуман non-blocking.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему возникло ощущение, что workflow продолжает ломаться? | В логах присутствовали error-аннотации/шумные сигналы | Жалоба пользователя + проверка run logs |
| 2 | Почему error-аннотация была в успешном сценарии? | Drift-детектор писал `::error::` без `exit 1` | `.github/workflows/gitops-drift-detection.yml:101` (до фикса) |
| 3 | Почему это проблема? | `error`-сигнал семантически равен инциденту, даже если pipeline зелёный | Непоследовательность “signal vs outcome” |
| 4 | Почему такое не поймали раньше? | Не было правила на согласованность уровня аннотаций с blocking policy | Отсутствие отдельной проверки alert severity |
| 5 | Почему ситуация повторяется? | Смешиваются старые реальные падения и новые non-fatal сигналы | История run’ов: старые `failure` + новые `success` |

## Корневая причина

Несоответствие уровня лог-аннотации (`::error::`) фактической non-blocking политике drift workflow создавало ложные error-сигналы при отсутствии падения job.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется изменением одного шага workflow |
| □ Systemic? | yes | Применимо к другим workflow с non-blocking логикой |
| □ Preventable? | yes | Через единый policy для severity-аннотаций |

## Принятые меры

1. **Немедленное исправление:** В `gitops-drift-detection.yml` заменена аннотация `::error::` на `::warning::` для случая `drift_found=true`.
2. **Предотвращение:** Сохранена non-blocking модель, но убрана ложная error-семантика.
3. **Документация:** Создан RCA-отчёт и обновлён индекс lessons.

## Связанные обновления

- [X] RCA-отчёт создан в `docs/rca/`
- [X] Раздел `## Уроки` добавлен
- [X] Индекс уроков пересобран (`./scripts/build-lessons-index.sh`)
- [ ] Новый файл правила создан (не требовалось)
- [ ] Ссылка в CLAUDE.md добавлена (не требовалось)

## Уроки

1. **Severity логов должна совпадать с политикой шага** — если шаг non-blocking, default уровень сигнала `warning`, а не `error`.
2. **Разделять исторические падения и текущие сигналы** — RCA должен опираться на timestamp и status свежих run’ов.
3. **Снижать alert noise** — уменьшение ложных `error` повышает доверие к CI/CD мониторингу.

---

*Создано по RCA-протоколу (5 Why) после анализа run’ов GitHub Actions и сигналов workflow.*
