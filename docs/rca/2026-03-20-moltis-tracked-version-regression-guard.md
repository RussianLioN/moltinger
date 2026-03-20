---
title: "Deploy workflow allowed tracked-version regression risk against newer running Moltis baseline"
date: 2026-03-20
severity: P1
category: cicd
tags: [moltis, deploy, gitops, versioning, regression-guard, rollback-safety]
root_cause: "Preflight validated tracked version format and branch source, but did not compare tracked git version with currently running production baseline, so stale main state could trigger an unintended downgrade rollout"
---

# RCA: Deploy workflow allowed tracked-version regression risk against newer running Moltis baseline

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** Высокий риск повторного незаметного downgrade при merge stale-ветки в `main` и обычном production deploy.

## Ошибка

После стабилизации прода на `0.10.18` был выявлен незакрытый путь:

- deploy использует tracked версию из `main` (это корректно),
- но до фикса не было preflight-проверки, что tracked версия не ниже уже работающей на сервере.

В результате stale merge в `main` потенциально мог инициировать downgrade через стандартный workflow, без явного rollback-сценария.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему downgrade мог пройти через обычный deploy? | Потому что workflow не сравнивал tracked git версию с текущей running version на сервере. | `.github/workflows/deploy.yml` до фикса: отсутствовал compare gate `running vs tracked`. |
| 2 | Почему это не ловили текущие проверки? | Проверки валидировали формат/version-source (`main`, tag->main, pinned semver), но не semantic monotonicity. | `scripts/moltis-version.sh`, static tests до фикса. |
| 3 | Почему это опасно именно после стабилизации на `0.10.18`? | Любой stale merge в `main` с более старым tag мог запустить “легальный” deploy и вернуть старую версию. | Deploy trigger: `push` на `main`; tracked version из compose. |
| 4 | Почему rollback-механизм не решал эту проблему? | Rollback — это recovery path, а не защита от неверного normal rollout. | Политика runbook: rollback должен быть осознанным recovery, не побочным эффектом deploy. |
| 5 | Почему риск был системным? | Контракт не фиксировал правило “normal deploy не имеет права понижать версию относительно текущего baseline”. | Отсутствовал explicit anti-regression gate в CI/CD и static-guard. |

## Корневая причина

В production deploy-контракте отсутствовал fail-closed anti-regression gate для сравнения tracked git версии и текущего running baseline на сервере.

## Принятые меры

1. `.github/workflows/deploy.yml`:
   - добавлен preflight шаг `Prevent tracked version regressions against running production baseline`;
   - если running semver-tag выше tracked semver-tag, deploy блокируется;
   - сообщение явно направляет в explicit rollback flow.
2. `tests/static/test_config_validation.sh`:
   - добавлен guard `static_deploy_blocks_tracked_version_regression_against_running_baseline`.
3. Документация:
   - `docs/version-update.md` обновлён: tracked-version downgrade через normal deploy запрещён;
   - `docs/runbooks/moltis-backup-safe-update.md` обновлён: downgrade только через явный rollback path.

## Подтверждение устранения

- `bash tests/static/test_config_validation.sh` — pass.
- В `deploy.yml` присутствует anti-regression preflight gate.
- Runtime baseline остаётся `0.10.18`, deploy по `main` продолжает работать.

## Уроки

1. Pinned version и semver-валидность недостаточны без monotonicity guard относительно текущего production baseline.
2. Rollback должен оставаться отдельным recovery-контуром и не подменяться обычным deploy.
3. Любой production version contract должен иметь static test на anti-regression поведение.
