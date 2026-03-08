---
title: "Локальный runtime был поднят вместо работы с удалённым сервисом"
date: 2026-03-08
severity: P2
category: process
tags: [process, runtime-target, docker, remote-service, local-stack, boundary]
root_cause: "Не было обязательного target-boundary pre-check перед локальными runtime-действиями"
---

# RCA: Локальный runtime был поднят вместо работы с удалённым сервисом

**Дата:** 2026-03-08
**Статус:** Resolved
**Влияние:** Среднее; лишние локальные side effects, потеря времени и отклонение от реального target environment
**Контекст:** Во время refactor-а тестов был поднят локальный Moltis stack и временный port-forward, хотя пользователь явно уточнил, что работа должна вестись против удалённого сервиса

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-08T11:xx:xx+03:00 |
| PWD | /Users/rl/.codex/worktrees/da4f/moltinger |
| Git Branch | codex/full-review |
| Error Type | process/execution-target |
| Trigger | Локальный `docker compose` и port-forward были использованы для E2E/UI-исследования вместо удалённого сервиса |

## Ошибка

Был развёрнут локальный Moltis stack (`compose.test.yml`) и поднят временный port-forward для браузерной отладки, хотя фактический объект работы находился на удалённом сервисе.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему был поднят локальный runtime? | Для ускорения browser/E2E-исследования я выбрал локальный hermetic stack как ближайший доступный путь | История действий в текущей сессии: `docker compose -f compose.test.yml -p moltinger-inspect up ...`, временный `alpine/socat` port-forward |
| 2 | Почему локальный hermetic stack был принят за допустимую цель? | Я интерпретировал план refactor-а как разрешение сразу работать через локальный test stack | В плане был `compose.test.yml`, и я перенёс это из design-level в execution-level без дополнительной проверки target |
| 3 | Почему не был выполнен target-check перед side-effectful действиями? | В обязательных entrypoint-инструкциях был context-first протокол для секретов, но не было отдельного runtime target boundary rule | `.ai/instructions/shared-core.md` до фикса содержал только `Context-First Rule`, без правила про remote/local execution target |
| 4 | Почему это позволило сместиться от remote service к local clone? | Не был закреплён жёсткий запрет на локальные контейнеры/port-forward, если authoritative target уже задан как remote | Отсутствовал explicit guardrail в правилах и стартовых инструкциях |
| 5 | Почему ошибка может повторяться в будущих сессиях? | Без формального правила агент оптимизирует под самый быстрый воспроизводимый путь, а не под правильный target environment | Повторяемый риск для любых задач по E2E, UI-debug и runtime validation |

## Корневая причина

Не было обязательного и явно сформулированного target-boundary pre-check перед локальными runtime-действиями. В результате design artifact про локальный hermetic stack был ошибочно использован как operational target, несмотря на фактический remote-target контекст задачи.

## Принятые меры

1. **Немедленное исправление:** Локальный compose stack и временный port-forward удалены.
2. **Предотвращение:** Добавлено правило `docs/rules/target-boundary-before-local-runtime.md`.
3. **Инструкции:** В `.ai/instructions/shared-core.md` добавлен mandatory `Runtime Target Rule`; `AGENTS.md` пересинхронизирован.
4. **Откат:** Удалены локальные артефакты текущей ошибки и откатаны адресные кодовые изменения этого хода.

## Связанные обновления

- [X] Новый файл правила создан (`docs/rules/target-boundary-before-local-runtime.md`)
- [X] Shared instructions обновлены
- [X] `AGENTS.md` пересобран
- [X] Локальный runtime удалён
- [X] Индекс уроков пересобран (`./scripts/build-lessons-index.sh`)

## Уроки

1. **Сначала target, потом runtime** — перед любыми локальными контейнерами или port-forward нужно явно определить authoritative environment.
2. **Hermetic stack из плана не равен разрешению на запуск** — design artifact можно исполнять только после проверки, что задача действительно локальная.
3. **Remote-target исключает локальную подмену по умолчанию** — если пользователь и документация указывают на удалённый сервис, локальная реплика допустима только по явному запросу.

---

*Создано по протоколу rca-5-whys (RCA-009).*
