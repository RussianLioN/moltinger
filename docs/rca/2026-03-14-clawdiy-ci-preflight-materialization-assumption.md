---
title: "CI preflight ошибочно требовал materialized Clawdiy runtime home до deploy/render шага"
date: 2026-03-14
severity: P2
category: process
tags: [process, clawdiy, preflight, ci, deploy, runtime-home, lessons]
root_cause: "Проверка перед запуском перенесла host-level требование о writable runtime home в локальный CI checkout, где каталог по контракту еще не материализован"
---

# RCA: CI preflight ошибочно требовал materialized Clawdiy runtime home до deploy/render шага

**Дата:** 2026-03-14  
**Статус:** Resolved in follow-up branch / pending rollout  
**Влияние:** Среднее; production workflow `Deploy Clawdiy` упал на локальном preflight шаге до выката исправления `runtime home` на сервер  
**Контекст:** После merge PR `#56` workflow `23083872438` завершился fail в шаге `Run local Clawdiy preflight`

## Ошибка

Локальный шаг CI:

```bash
./scripts/preflight-check.sh --ci --target clawdiy --json
```

падал с ошибкой:

```text
Clawdiy runtime home is missing: <repo>/data/clawdiy/runtime
```

Хотя это не ошибка deploy-target. В CI checkout GitHub runner каталог `data/clawdiy/runtime` по контракту еще не обязан существовать: он создается и нормализуется позже через `render` и `deploy` шаги.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему production workflow упал до deploy? | Потому что `preflight --ci --target clawdiy` завершился с кодом 4 | GitHub Actions run `23083872438`, job `Clawdiy Preflight` |
| 2 | Почему `preflight` посчитал состояние ошибкой? | Потому что требовал существующий `data/clawdiy/runtime` уже в локальном checkout раннера | Local repro: `./scripts/preflight-check.sh --ci --target clawdiy --json` |
| 3 | Почему это требование неверно для CI? | Потому что каталог `runtime home` создается и нормализуется позже на шаге deploy/render, а не хранится как обязательный материализованный артефакт в git checkout | `deploy-clawdiy.yml`, `scripts/deploy.sh`, `scripts/render-clawdiy-runtime-config.sh` |
| 4 | Почему проверка стала слишком ранней? | Потому что предыдущий live-fix для writable runtime home был механически перенесен в общий `preflight`, без разделения CI checkout и target host | change in `scripts/preflight-check.sh` from branch `022` |
| 5 | Почему это системная ошибка? | Потому что `preflight` смешал две разные среды: локальную валидацию репозитория и реальный deploy-target контракт | behavior of `--ci` mode vs host-level runtime ownership contract |

## Корневая причина

Проверка перед запуском перенесла host-level требование о writable runtime home в локальный CI checkout, где каталог по контракту еще не материализован.

## Принятые меры

1. В `scripts/preflight-check.sh` проверка `check_clawdiy_runtime_home` стала target-aware.
2. В режиме `--ci` отсутствие `data/clawdiy/runtime` больше не считается ошибкой; скрипт фиксирует, что каталог должен быть создан на следующих шагах deploy/render.
3. В режиме `--ci` проверка владельца `1000:1000` тоже больше не является блокирующей.
4. В `tests/static/test_config_validation.sh` добавлен guard, что CI-режим не должен валиться на нематериализованном `runtime home`.

## Уроки

1. **`preflight` обязан различать checkout и deploy-target** — иначе защитная проверка превращается в ложный блокер.
2. **Нельзя переносить host-only инвариант в CI без явной target-aware развилки**.
3. **Проверка существования пути и проверка его будущего materialization — разные вещи**.

---

*Создано по протоколу RCA.*
