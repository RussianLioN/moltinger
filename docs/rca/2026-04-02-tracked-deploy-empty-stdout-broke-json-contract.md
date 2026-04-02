---
title: "Tracked deploy empty stdout broke GitHub Actions JSON contract"
date: 2026-04-02
severity: P2
category: cicd
tags: [deploy, github-actions, json-contract, bash, moltis]
root_cause: "run-tracked-moltis-deploy.sh treated empty deploy.sh stdout as valid jq input, so the workflow step could fail with an empty OUTPUT/STATUS instead of structured failure JSON."
---

# RCA: Tracked deploy empty stdout broke GitHub Actions JSON contract

**Дата:** 2026-04-02
**Статус:** Resolved
**Влияние:** Один и тот же deploy workflow мог фактически обновить прод и оставить сервис healthy, но пометить `Deploy to Production` красным без диагностического JSON для GitHub Actions.
**Контекст:** `Deploy Moltis` run `23917024642`, commit `4527b12`

## Ошибка

Первый attempt workflow `Deploy Moltis` завершился failure на step `Run tracked Moltis deploy control plane`, хотя сервер уже переключился на новый commit, контейнер `moltis` был healthy, а повторный Telegram UAT был зелёным.

В логах step выглядел так:

- `[run-tracked-moltis-deploy] Preparing writable Moltis runtime config`
- `[run-tracked-moltis-deploy] Validating tracked Moltis deploy contract`
- `[run-tracked-moltis-deploy] Running tracked Moltis deploy via scripts/deploy.sh`
- `[GitOps] No drift detected ✓`
- затем workflow видел только `Tracked deploy control plane failed`

При этом в `Deployment summary` поле `STATUS` было пустым, то есть GitHub Actions не получил ожидаемый JSON-ответ от control-plane.

## Проверка прошлых уроков

**Проверенные источники:**
- [docs/rca/2026-03-28-deploy-stall-watchdog-argjson-overflow.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-03-28-deploy-stall-watchdog-argjson-overflow.md)
- [docs/rca/2026-03-28-deploy-hardening-follow-up-verify-failure-and-watchdog-queue-semantics.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-03-28-deploy-hardening-follow-up-verify-failure-and-watchdog-queue-semantics.md)
- [docs/rca/2026-03-27-moltis-deploy-force-recreate-race-on-slow-stop.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-03-27-moltis-deploy-force-recreate-race-on-slow-stop.md)

**Что в текущем инциденте действительно новое:**
- проблема была не в долгом rollout и не в attestation после success, а в пустом stdout от `deploy.sh`, который ошибочно проходил как “допустимый JSON-кейс” внутри оболочки control-plane.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему GitHub Actions показал красный deploy-step? | Step `Run tracked Moltis deploy control plane` завершился `exit 1` и не отдал workflow нормальный JSON со `status`. | Failed attempt log `69753619065`; в `Deployment summary` `STATUS=""`. |
| 2 | Почему workflow не получил `status`? | `OUTPUT=$(bash ./scripts/ssh-run-tracked-moltis-deploy.sh ...)` оказался пустым. | Step log: после `No drift detected` нет JSON, только `Tracked deploy control plane failed`. |
| 3 | Почему control-plane мог завершиться без JSON? | В failure-path `run-tracked-moltis-deploy.sh` вызывает `append_result_context "$DEPLOY_OUTPUT" ...`, а та считала пустую строку валидным вводом для `jq empty`. | [scripts/run-tracked-moltis-deploy.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/scripts/run-tracked-moltis-deploy.sh#L85) |
| 4 | Почему `jq empty` это пропустил? | Для пустого stdin `jq empty` возвращает `0`, поэтому проверка “это JSON или нет” была слишком слабой. | Локальная проверка: `jq empty <<<\"\"` => `exit 0`. |
| 5 | Почему дефект дошёл до продового workflow? | Не было unit-регрессии на кейс “`deploy.sh` вернул non-zero и пустой stdout”. | До исправления в [tests/unit/test_deploy_workflow_guards.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/tests/unit/test_deploy_workflow_guards.sh) такого сценария не было. |

## Корневая причина

`run-tracked-moltis-deploy.sh` нарушал собственный JSON ABI-контракт с GitHub Actions: пустой stdout от `deploy.sh` не считался ошибочным payload до построения результата, поэтому failure-path мог закончиться пустым stdout и `exit 1`. Внешне это выглядело как загадочный красный deploy-step при фактически успешном или частично успешном rollout.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется локально в shell wrapper. |
| □ Systemic? | yes | Затрагивает любой deploy-run, где `deploy.sh` нарушит stdout-contract. |
| □ Preventable? | yes | Достаточно явной проверки на пустой payload + unit-регрессии. |

## Принятые меры

1. **Немедленное исправление:** в [scripts/run-tracked-moltis-deploy.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/scripts/run-tracked-moltis-deploy.sh) `append_result_context()` теперь считает пустой или whitespace-only `base_json` невалидным и принудительно возвращает structured failure JSON.
2. **Предотвращение:** добавлен unit-тест в [tests/unit/test_deploy_workflow_guards.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/tests/unit/test_deploy_workflow_guards.sh) на кейс “`deploy.sh` завершился non-zero и не вывел JSON”.
3. **Операционная проверка:** rerun того же workflow `23917024642` (attempt `2`) прошёл полностью зелёным; server markers обновились на `4527b12`.

## Связанные обновления

- [x] Тесты добавлены
- [x] Документация RCA обновлена

## Уроки

- Для CLI/CI JSON-контрактов одной проверки `jq empty` недостаточно: пустой stdout нужно проверять отдельно.
- Если workflow читает structured output из stdout, stderr нужно считать отдельным диагностическим каналом и не смешивать их в тестах.
- Красный deploy-step при healthy сервисе не всегда означает “ложную тревогу GitHub”; сначала нужно проверить, не нарушен ли ABI-контракт между shell-wrapper и workflow.
