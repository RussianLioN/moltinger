---
title: "Tracked Moltis deploy failed because the repo skill sync helper crashed in its EXIT trap under set -u"
date: 2026-03-28
severity: P1
category: cicd
tags: [cicd, deploy, skills, bash, trap, set-u, moltis, rollback, verification, github-actions]
root_cause: "scripts/moltis-repo-skills-sync.sh stored its staging directory in a local variable and registered `trap 'rm -rf \"$staging_root\"' EXIT` under `set -u`; when the trap executed outside the local scope, the variable was unbound, the sync helper exited non-zero, and deploy verification treated repo skill sync as failed"
---

# RCA: Tracked Moltis deploy failed because the repo skill sync helper crashed in its EXIT trap under set -u

**Дата:** 2026-03-28  
**Статус:** Resolved  
**Влияние:** production workflow `Deploy Moltis` run `23669994700` failed in `Deploy to Production -> Run tracked Moltis deploy control plane`. Live production stayed available and already moved to commit `835aab8bb8ec5c24072f21817b2c73950f878bab`, but the deployment pipeline reported failure and auto-rollback because repo-managed skill sync verification crashed.

## Ошибка

Ключевой сигнал из failed workflow:

- `verify_failure_reason`: `Moltis runtime contract mismatch: failed to sync repo-managed skills into runtime discovery path`

Manual reproduction on the live container showed the exact shell failure:

```text
/server/scripts/moltis-repo-skills-sync.sh: line 1: staging_root: unbound variable
```

При этом live production оставался в рабочем состоянии:

- image: `ghcr.io/moltis-org/moltis:0.10.18`
- container: `running healthy`
- `/health`: `200`
- checkout: `835aab8bb8ec5c24072f21817b2c73950f878bab`

## Что было доказано

1. Падение происходило не в Docker image pull и не в Moltis startup.
2. Pipeline доходил до live rollout и стартовал новый контейнер корректно.
3. Failure происходил именно в repo skill sync verification path.
4. `moltis-repo-skills-sync.sh` падал не на копировании файлов, а на cleanup trap:
   - script работал под `set -euo pipefail`;
   - staging path хранился в локальной переменной `staging_root`;
   - `trap 'rm -rf "$staging_root"' EXIT` исполнялся уже вне локальной области видимости;
   - `set -u` превращал cleanup в hard failure.
5. Existing component test уже мог воспроизвести баг, но этот тест не был частью `Deploy Moltis -> Pre-deployment Tests`, поэтому дефект дошёл до production deploy stage.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему `Deploy to Production` упал после старта контейнера? | `deploy.sh` не смог пройти verify path и ушёл в failure/rollback envelope | failed run `23669994700` |
| 2 | Почему verify path считал repo skill sync сломанным? | `moltis-repo-skills-sync.sh` завершался non-zero | manual live reproduction |
| 3 | Почему sync helper завершался non-zero? | EXIT trap ссылался на локальную переменную `staging_root`, уже недоступную на момент cleanup | `scripts/moltis-repo-skills-sync.sh` before fix |
| 4 | Почему это не было поймано раньше? | Production deploy workflow не запускал component test для sync helper до remote rollout | `deploy.yml` before fix |
| 5 | Почему failure path выглядел как skill-contract mismatch, а не как shell bug? | Верхний deploy verification корректно репортил symptom-level contract failure, но без отдельного direct reproduction root cause оставался скрыт в helper | failed JSON + manual `docker exec` reproduction |

## Корневая причина

### Primary root cause

`scripts/moltis-repo-skills-sync.sh` использовал cleanup trap, завязанный на локальную переменную функции, что несовместимо с `set -u` при выполнении `EXIT` trap вне локальной области видимости.

### Contributing root cause

`Deploy Moltis` workflow не запускал component test sync helper до production SSH stage, поэтому дефект обнаруживался слишком поздно.

## Принятые меры

1. В `scripts/moltis-repo-skills-sync.sh` staging directory переведён на process-level variable `STAGING_ROOT`.
2. Cleanup вынесен в отдельную функцию `cleanup_staging_root`, которую безопасно вызывает `trap`.
3. `Deploy Moltis -> Pre-deployment Tests` теперь выполняет:
   - `bash tests/component/test_moltis_repo_skills_sync.sh`
4. Static guard обновлён, чтобы deploy workflow не потерял этот component test и timeout для `test` job.

## Проверка после исправления

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash -n scripts/moltis-repo-skills-sync.sh` | pass | local |
| `bash tests/component/test_moltis_repo_skills_sync.sh` | pass | 3/3 |
| `bash tests/unit/test_deploy_workflow_guards.sh` | pass | 28/28 |
| `bash tests/static/test_config_validation.sh` | pass | 115/115 |
| manual live reproduction before fix | reproduced | `staging_root: unbound variable` |

## Уроки

1. Под `set -u` cleanup trap нельзя привязывать к локальным переменным функции без гарантии scope-safe lifetime.
2. Если production deploy relies on a helper script, у helper должен быть blocking component test в pre-deployment workflow, а не только локальный test file в репозитории.
3. Controlled deploy verification полезен тем, что он показывает symptom (`repo skill sync failed`), но для RCA всё равно нужен direct reproduction на live code path.
