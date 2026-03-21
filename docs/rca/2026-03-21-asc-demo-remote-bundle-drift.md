---
title: "ASC demo: расхождение локального и удалённого frontend bundle"
date: 2026-03-21
severity: P1
category: process
tags: [asc-demo, web, deploy, gitops, state-machine]
root_cause: "Проверка выполнялась на локально задеплоенном контейнере, тогда как пользователь тестировал удалённый demo.ainetic.tech со старым bundle."
---

# RCA: ASC demo — расхождение локального и удалённого frontend bundle

**Дата:** 2026-03-21  
**Статус:** Resolved  
**Влияние:** пользователь продолжал видеть старый UI/роутинг (`brief` corrections), несмотря на локально исправленный код.  
**Контекст:** ветка `024-web-factory-demo-adapter`, контур `demo.ainetic.tech`.

## Ошибка

Исправления проходили локальные тесты и локальный deploy, но на `https://demo.ainetic.tech` оставался старый `app.js`.  
Из-за этого в боевом демо воспроизводились уже исправленные баги (в частности, неверный роутинг `business_rules` и нестабильное поведение composer после первого ответа).

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---|---|---|---|
| 1 | Почему пользователь видел старое поведение? | На `demo.ainetic.tech` был старый frontend bundle. | `curl -sk https://demo.ainetic.tech/app.js` не содержал `target: "business_rules"`. |
| 2 | Почему bundle был старый? | Выполнялся локальный `./scripts/deploy.sh asc-demo deploy`, который обновляет локальный контейнер, а не remote worktree. | Локальный `curl http://127.0.0.1:18791/app.js` показывал новый код, remote — нет. |
| 3 | Почему это не поймали раньше? | Не было обязательного шага «сравнить локальный и удалённый bundle signature» после фикса P0. | Расхождение обнаружено только после явного сравнения `curl .../app.js`. |
| 4 | Почему процесс позволил это пропустить? | В рабочем цикле не был закреплён порядок: `commit -> push -> remote pull -> remote deploy -> live verify`. | До этого использовался частичный путь с локальным deploy. |
| 5 | Почему это системно? | Нет явного guard/checklist на «authoritative target first» для web-demo hotfix. | Симптом повторялся в нескольких итерациях UX/logic фиксов. |

## Корневая причина

Процессная ошибка в цепочке выката: проверка и deploy проводились преимущественно локально, при том что источником истины для пользовательского UAT был удалённый `demo.ainetic.tech`.

## Принятые меры

1. **Немедленное исправление**
   - Выполнен `git push` ветки `024-web-factory-demo-adapter`.
   - На сервере `ainetic.tech` выполнен `git pull --rebase` в `/opt/moltinger-asc-demo`.
   - Выполнен remote deploy: `GITOPS_CONFIRM_SKIP=true ./scripts/deploy.sh --json asc-demo deploy`.
2. **Валидация результата**
   - Проверено, что remote `app.js` содержит `target: "business_rules"`.
   - Прогнаны live smoke тесты: `LIVE_WEB_DEMO_URL=https://demo.ainetic.tech ... test_web_factory_demo_smoke` — pass.
   - Прогнан remote API-сценарий `request_brief_correction` с проверкой:
     - правка уходит в `business_rules`,
     - `expected_outputs` не перезаписывается.
3. **Предотвращение**
   - Для P0 фиксов web-demo добавлен обязательный пост-фикс шаг:
     - сравнение локального и удалённого `app.js` по целевым сигнатурам до завершения цикла.

## Уроки

- Для `asc-demo` локальный deploy полезен только как предварительная проверка; финальная проверка должна быть на удалённом authoritative контуре.  
- Любой фикс state-machine/front routing считается незавершённым без верификации remote bundle и live API-сценария.

