---
title: "Deploy Clawdiy блокировался на dirty checkout без auditable repair path"
date: 2026-03-14
severity: P2
category: cicd
tags: [cicd, clawdiy, gitops, deploy, checkout-repair, drift, lessons]
root_cause: "Workflow Deploy Clawdiy требовал чистый server checkout, но не умел безопасно восстановить его через уже существующий auditable repair path при drift внутри Clawdiy-managed surface"
---

# RCA: Deploy Clawdiy блокировался на dirty checkout без auditable repair path

**Дата:** 2026-03-14  
**Статус:** Resolved in follow-up branch / pending rollout  
**Влияние:** Среднее; production-update Clawdiy на официальный образ `2026.3.13` был остановлен GitOps-gate до фактического deploy  
**Контекст:** workflow `Deploy Clawdiy` run `23090331854` упал на шаге `Verify server worktree is clean`

## Ошибка

Production workflow завершился ошибкой:

```text
Server working tree is dirty. Clawdiy deployment blocked by GitOps policy.
```

При этом live-проверка на сервере показала, что dirty state ограничен одним файлом:

```text
M scripts/preflight-check.sh
```

а сам diff был deploy-managed изменением из предыдущего Clawdiy fix:

```diff
+ if [[ "$CI_MODE" == "true" ]]; then
+   add_check "runtime_home_present" "pass" ...
+   return
+ fi
```

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему production update на `2026.3.13` не дошел до deploy? | Потому что `Deploy Clawdiy` остановился на грязном server checkout | GitHub run `23090331854` |
| 2 | Почему dirty checkout стал hard blocker? | Потому что workflow проверял `git status --porcelain`, но не умел repair ограниченного deploy-managed drift | `.github/workflows/deploy-clawdiy.yml` до исправления |
| 3 | Почему repair path был нужен именно здесь? | Потому что на сервере остался незакоммиченный deploy-managed drift в `scripts/preflight-check.sh` от предыдущего Clawdiy fix | `ssh root@ainetic.tech "cd /opt/moltinger && git diff -- scripts/preflight-check.sh"` |
| 4 | Почему аналогичный drift уже решается в Moltis workflow? | Потому что `Deploy Moltis` уже имел `repair_server_checkout` и `scripts/gitops-repair-managed-checkout.sh` | `.github/workflows/deploy.yml`, `scripts/gitops-repair-managed-checkout.sh` |
| 5 | Почему это системная ошибка? | Потому что GitOps guard для Clawdiy был менее зрелым, чем для Moltis: hard gate был, а controlled self-heal для deploy-managed surface отсутствовал | comparison of `deploy.yml` vs `deploy-clawdiy.yml` |

## Корневая причина

Workflow `Deploy Clawdiy` требовал чистый server checkout, но не умел безопасно восстановить его через уже существующий auditable repair path при drift внутри Clawdiy-managed surface.

## Принятые меры

1. В `deploy-clawdiy.yml` добавлен `workflow_dispatch` input `repair_server_checkout`.
2. Шаг `Verify server worktree is clean` теперь:
   - различает обычный dirty state и repairable drift;
   - допускает repair только для `docker-compose.clawdiy.yml`, `config/clawdiy`, `config/fleet`, `config/backup` и `scripts`;
   - вызывает `scripts/gitops-repair-managed-checkout.sh` с сохранением drift snapshot.
3. В `tests/static/test_config_validation.sh` добавлен guard, что `Deploy Clawdiy` обязан иметь auditable checkout repair path.
4. В `docs/runbooks/clawdiy-deploy.md` добавлен операторский путь повторного запуска с `repair_server_checkout=true`.

## Уроки

1. **Hard gate без controlled repair path превращается в операционный тупик**, если drift уже ограничен deploy-managed surface.
2. **Parity между Moltis и Clawdiy GitOps-guardrails должна поддерживаться осознанно**, а не по остаточному принципу.
3. **Dirty checkout нужно не только блокировать, но и классифицировать**: repairable deploy-managed drift против небезопасного drift вне разрешенной поверхности.

---

*Создано по протоколу RCA.*
