---
title: "Tracked Moltis deploy failed because backup restore-check logs polluted deploy.sh JSON stdout contract"
date: 2026-03-20
severity: P1
category: cicd
tags: [cicd, deploy, json-contract, backup, restore-check, moltis, production]
root_cause: "In --json mode, deploy.sh executed backup restore-check with stdout attached, so informational logs preceded JSON payload; tracked deploy wrapper treated mixed output as non-JSON and failed despite successful rollout"
---

# RCA: Tracked Moltis deploy failed because backup restore-check logs polluted deploy.sh JSON stdout contract

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** production deploy run `23361033522` завершился `failure` в control-plane step, хотя Moltis контейнеры фактически перезапустились успешно.

## Ошибка

В run `23361033522` step `Run tracked Moltis deploy control plane` завершился с:

- `deploy.sh returned non-JSON output despite --json contract`

Симптомы:

- Docker operations прошли успешно (`moltis`/`watchtower`/`ollama` были запущены).
- wrapper отказался принимать результат из-за некорректного JSON envelope.

## Анализ 5 Почему

| Уровень | Почему | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему workflow пометил deploy как failed? | Wrapper `run-tracked-moltis-deploy.sh` не смог распарсить stdout `deploy.sh` как JSON | run `23361033522` failed log |
| 2 | Почему stdout не был валидным JSON? | Перед JSON payload в stdout попали INFO-логи restore-check (`Verifying backup...`) | remote repro `/opt/moltinger/scripts/deploy.sh --json moltis deploy` |
| 3 | Почему restore-check писал в stdout в JSON-режиме? | В `backup_current_state` команда `"$BACKUP_SCRIPT" restore-check "$backup_path"` вызывалась без перенаправления в stderr | `scripts/deploy.sh` до фикса |
| 4 | Почему это ломает tracked control-plane? | Wrapper требует fail-closed contract: stdout должен быть единственным JSON объектом | `scripts/run-tracked-moltis-deploy.sh` (`jq empty` check) |
| 5 | Почему дефект проявился только после предыдущего фикса? | Ранее deploy падал раньше (port/name conflicts); после устранения этих падений pipeline дошёл до restore-check и вскрыл новый контрактный дефект | последовательность run `23360516210` -> `23361033522` |

## Корневая причина

Нарушен stdout/stderr контракт `deploy.sh --json`: restore-check печатал операционные логи в stdout, из-за чего wrapper получал mixed output вместо чистого JSON.

## Принятые меры

1. В `scripts/deploy.sh` для `TARGET=moltis` в JSON-режиме restore-check принудительно уходит в stderr:
   - `"$BACKUP_SCRIPT" restore-check "$backup_path" 1>&2`
2. В статические проверки добавлен guard:
   - `static_deploy_script_keeps_json_stdout_clean` теперь валидирует stderr-redirect restore-check.

## Проверка после исправлений

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash tests/static/test_config_validation.sh` | pass | 91/91 |
| JSON stdout guard | pass | `static_deploy_script_keeps_json_stdout_clean` |
| Remote dry verification of contract path | pass | stderr содержит restore logs, stdout остаётся JSON payload |

## Уроки

1. Для всех `--json` entrypoint-скриптов stdout должен быть зарезервирован только под machine-readable payload.
2. Любые диагностические/операционные сообщения в JSON-режиме должны быть строго перенаправлены в stderr.
