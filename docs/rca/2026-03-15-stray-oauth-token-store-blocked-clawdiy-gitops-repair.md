---
title: "Stray runtime oauth_tokens.json blocked Clawdiy GitOps repair"
date: 2026-03-15
severity: P2
category: cicd
tags: [clawdiy, moltis, gitops, oauth, deploy, runtime-artifacts, lessons]
root_cause: "Временный Moltis OAuth runtime писал token store рядом с config path внутри /opt/moltinger git checkout, а Clawdiy checkout repair не классифицировал config/oauth_tokens.json как известный runtime-артефакт"
---

# RCA: Stray runtime `oauth_tokens.json` blocked Clawdiy GitOps repair

**Дата:** 2026-03-15  
**Статус:** Resolved in branch `024-clawdiy-oauth-store-drift-fix`  
**Влияние:** Среднее; повторный deploy/update Clawdiy мог блокироваться на dirty `/opt/moltinger` даже при исправимом drift  
**Контекст:** follow-up bug `molt-uc1`

## Ошибка

При разборе blocked deploy для Clawdiy историческим hard blocker оказался untracked файл:

```text
/opt/moltinger/config/oauth_tokens.json
```

Он не относится к tracked GitOps-конфигу, но появлялся внутри git checkout и ломал `repair_server_checkout` для Clawdiy, потому что workflow считал его drift вне Clawdiy-managed surface.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему production deploy Clawdiy мог блокироваться даже после появления auditable repair path? | Потому что dirty path `config/oauth_tokens.json` классифицировался как чужой drift вне разрешенной поверхности | `.github/workflows/deploy-clawdiy.yml` до фикса |
| 2 | Почему этот файл вообще появлялся в `/opt/moltinger/config/`? | Потому что один из временных Moltis OAuth runtime-проходов писал token store рядом со своим config path | исторический issue `molt-uc1`, server checkout drift evidence |
| 3 | Почему это не выглядит как tracked repo-файл? | Потому что в git истории и текущем repo нет `config/oauth_tokens.json`, `oauth-config` или `oauth-runtime-test-config-v1` как управляемых артефактов | `git log --all -- config/oauth_tokens.json data/oauth-config/moltis.toml data/oauth-runtime-test-config-v1/moltis.toml` -> пусто |
| 4 | Почему источник уверенно связан с временным runtime, а не с live Clawdiy? | Потому что на сервере нашлись только ignored runtime-пути `data/oauth-config/oauth_tokens.json` и `data/oauth-runtime-test-config-v1/oauth_tokens.json`, а в логе тестового runtime зафиксированы отдельные `config`/`data` пути и `moltis gateway v0.10.18` | `find /opt/moltinger -maxdepth 3 -name oauth_tokens.json -o -name auth-profiles.json`, `grep -n 'oauth-runtime-test-config-v1\\|moltis gateway v0.10.18' /opt/moltinger/data/oauth-runtime-test-data-v1/logs.jsonl` |
| 5 | Почему это стало системной GitOps-проблемой? | Потому что repair path умел только snapshot + reset/clean, но не умел безопасно эвакуировать известный runtime OAuth store из tracked checkout в ignored data path | `scripts/gitops-repair-managed-checkout.sh` до фикса |

## Корневая причина

Временный Moltis OAuth runtime писал token store рядом с config path внутри `/opt/moltinger` git checkout, а Clawdiy GitOps repair не классифицировал `config/oauth_tokens.json` как известный runtime-артефакт и не умел безопасно переносить его в ignored `data/`-хранилище до очистки checkout.

## Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Добавляется controlled evacuation path и явная классификация артефакта |
| □ Systemic? | yes | Без этого любой повторный OAuth runtime test мог снова заблокировать deploy |
| □ Preventable? | yes | Правило и статические guard'ы предотвращают повтор |

## Принятые меры

1. **Немедленное исправление:** `scripts/gitops-repair-managed-checkout.sh` теперь перед очисткой checkout переносит stray `config/oauth_tokens.json` в `data/oauth-config/oauth_tokens.json`, а при конфликте сохраняет timestamped recovered-copy.
2. **Предотвращение:** `deploy-clawdiy.yml` теперь считает `config/oauth_tokens.json` известным repairable runtime-артефактом вместо hard blocker'а вне управляемой поверхности.
3. **Документация:** добавлены правило `docs/rules/runtime-oauth-token-stores-must-stay-out-of-git-checkout.md` и обновления в runbook / existing repair rule.
4. **Проверка:** статические проверки закрепляют и саму эвакуацию в repair script, и исключение в Clawdiy workflow.

## Уроки

1. **Runtime OAuth state нельзя хранить рядом с tracked config**, даже если это временный тестовый runtime.
2. **GitOps repair должен различать tracked drift и известные runtime-артефакты**, иначе production deploy застревает на исправимой грязи.
3. **Источник stray-файла нужно подтверждать фактическим runtime evidence**, а не только по имени файла: здесь это был не live Clawdiy, а отдельный Moltis runtime test.

---

*Создано по протоколу RCA.*
