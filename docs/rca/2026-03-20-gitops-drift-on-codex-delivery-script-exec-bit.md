---
title: "Push deploy blocked by GitOps drift from exec-bit mismatch on codex-cli-update-delivery.sh"
date: 2026-03-20
severity: P1
category: cicd
tags: [cicd, gitops, drift, permissions, deploy, moltis]
root_cause: "Tracked file scripts/codex-cli-update-delivery.sh was committed as 100644 while managed server surface enforced executable bit (100755), causing persistent dirty checkout and push-deploy hard block"
---

# RCA: Push deploy blocked by GitOps drift from exec-bit mismatch on codex-cli-update-delivery.sh

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** push deploy `23359426197` блокировался на `GitOps Compliance Check`, deployment stage даже не запускался.

## Ошибка

В run `23359426197` GitOps gate показал:

- `Server working tree is dirty before deploy.`
- dirty path: `M scripts/codex-cli-update-delivery.sh`

Проверка на сервере показала, что отличие только в mode:

- `old mode 100644`
- `new mode 100755`

## Анализ 5 Почему

| Уровень | Почему | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему deploy блокировался до rollout? | `GitOps Compliance Check` видел dirty server checkout | run `23359426197` |
| 2 | Почему checkout был dirty? | `scripts/codex-cli-update-delivery.sh` отличался по mode | `git diff` на сервере |
| 3 | Почему mode отличался? | На server managed surface файл становился executable (`100755`) | `/opt/moltinger` status/diff |
| 4 | Почему это считалось drift? | В git файл был зафиксирован как `100644` | `git ls-files --stage` в репозитории |
| 5 | Почему дефект не ловился раньше? | Не было статического контракта на executable-бит именно этого deploy-managed скрипта | отсутствие explicit static test до фикса |

## Корневая причина

Несогласованный executable contract: серверный managed surface требовал executable-bit для `scripts/codex-cli-update-delivery.sh`, но tracked git mode оставался `100644`, что создавало постоянный GitOps drift.

## Принятые меры

1. Файл `scripts/codex-cli-update-delivery.sh` переведён в executable mode (`100755`) в git.
2. Добавлен static guard:
   - `static_codex_cli_update_delivery_script_is_executable`
3. После фикса deploy должен проходить GitOps compliance без ручного repair для этого path.

## Проверка после исправлений

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash tests/static/test_config_validation.sh` | pass | 90/90 |
| executable guard | pass | `static_codex_cli_update_delivery_script_is_executable` |

## Уроки

1. Для deploy-managed shell entrypoints mode (`100755`) является частью GitOps-контракта наравне с content hash.
2. Если managed sync/host automation нормализует executable-биты, такие файлы должны быть зафиксированы executable в git, иначе push-deploy будет циклически блокироваться на drift gate.
