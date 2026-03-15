---
title: "Clawdiy upgrade to official Docker latest regressed live health and required baseline rollback"
date: 2026-03-14
severity: P1
category: cicd
tags: [clawdiy, openclaw, docker, latest, rollout, health, rollback, lessons]
root_cause: "Clawdiy repo defaults were switched to the floating OpenClaw Docker latest channel before that exact image had been verified against the live Clawdiy runtime contract"
---

# RCA: Clawdiy upgrade to official Docker latest regressed live health and required baseline rollback

**Дата:** 2026-03-14  
**Статус:** Resolved  
**Влияние:** Высокое; production Clawdiy временно ушел в `unhealthy`, внешний `https://clawdiy.ainetic.tech/health` отвечал `404`, потребовался срочный откат на `2026.3.11`  
**Контекст:** `Deploy Clawdiy` run `23090853145` после перевода repo-default на `ghcr.io/openclaw/openclaw:latest`

## Ошибка

После успешного pull и recreate контейнера `clawdiy` на официальном Docker channel `latest` deploy workflow завершился ошибкой:

```text
DEPLOY_ERROR: clawdiy is unhealthy
DEPLOY_ERROR: Clawdiy deployment verification failed
```

Live-проверка показала:

- `docker inspect clawdiy` -> `ghcr.io/openclaw/openclaw:latest unhealthy`
- `https://clawdiy.ainetic.tech/health` -> `404 page not found`
- внутри контейнера OpenClaw не начинал слушать `127.0.0.1:18789`

Восстановление было выполнено официальным deploy workflow с явным образом `ghcr.io/openclaw/openclaw:2026.3.11`, run `23090952913`, после чего Clawdiy снова стал healthy.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему production Clawdiy перестал проходить health-check? | Потому что deploy на `ghcr.io/openclaw/openclaw:latest` поднял контейнер, который не вышел в слушающий gateway | run `23090853145`, `docker inspect`, `curl https://clawdiy.ainetic.tech/health` |
| 2 | Почему workflow вообще использовал `latest` как repo-default? | Потому что exact tag `2026.3.13` отсутствовал в GHCR, а официальный Docker channel был интерпретирован как безопасный default для немедленного переключения | `docker manifest inspect ghcr.io/openclaw/openclaw:2026.3.13` -> `manifest unknown`; PR `#60` |
| 3 | Почему это допущение оказалось неверным именно для Clawdiy? | Потому что конкретный floating image за `latest` не был верифицирован против нашего live runtime contract: Traefik, writable runtime-home, gateway token flow, existing state/auth store | live rollout `23090853145` |
| 4 | Почему сбой оказался production-рискованным? | Потому что repo-default был изменен до завершения отдельного upgrade canary, поэтому следующий обычный deploy сразу стал использовать непроверенный образ | `.github/workflows/deploy-clawdiy.yml` до фикса |
| 5 | Почему это системная ошибка, а не единичный инцидент? | Потому что не было явного правила: Clawdiy Docker image по умолчанию должен оставаться pinned на последнем live-verified baseline, а upgrade candidate должен запускаться только как opt-in rollout с post-deploy canary | отсутствие соответствующего правила и pinned default до этого RCA |

## Корневая причина

Clawdiy repo defaults были переключены на плавающий OpenClaw Docker `latest` до того, как этот конкретный image был проверен на совместимость с live Clawdiy runtime contract.

## Принятые меры

1. Выполнен production rollback на `ghcr.io/openclaw/openclaw:2026.3.11` через официальный workflow `Deploy Clawdiy` run `23090952913`.
2. Repo-default для Clawdiy возвращен на `ghcr.io/openclaw/openclaw:2026.3.11`:
   - `.github/workflows/deploy-clawdiy.yml`
   - `scripts/deploy.sh`
   - `scripts/preflight-check.sh`
   - `scripts/health-monitor.sh`
   - `tests/static/test_config_validation.sh`
   - operator docs
3. Зафиксировано правило: floating `latest` не становится tracked default для Clawdiy без отдельного live-verified rollout.

## Уроки

1. **Официальный Docker channel сам по себе не равен безопасному repo-default** для long-lived production runtime; для tracked defaults требуется live verification именно в нашей topology.
2. **Upgrade candidate должен идти через явный `clawdiy_image` override**, а не через изменение базового значения workflow до прохождения канарейки.
3. **Последний live-verified pinned image должен оставаться точкой восстановления**, пока новый образ не пройдет health, smoke и реальный ответ агента.

---

*Создано по протоколу RCA.*
