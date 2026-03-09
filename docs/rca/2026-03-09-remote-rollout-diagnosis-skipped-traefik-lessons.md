---
title: "Диагностика remote rollout началась без повторного применения Traefik-first уроков"
date: 2026-03-09
severity: P2
category: process
tags: [process, rollout-diagnosis, traefik, infrastructure, lessons, remote-service]
root_cause: "При переходе от implementation к remote rollout diagnosis не был заново запущен обязательный lessons/artifacts pass по MEMORY, LESSONS-LEARNED и INFRASTRUCTURE"
---

# RCA: Диагностика remote rollout началась без повторного применения Traefik-first уроков

**Дата:** 2026-03-09  
**Статус:** Resolved  
**Влияние:** Среднее; диагностика пошла в сторону нового внутреннего network blocker, хотя в проекте уже были зафиксированы более приоритетные Traefik/routing invariants для продакшена  
**Контекст:** После merge Clawdiy feature-ветки началась подготовка к первому same-host rollout на `ainetic.tech`

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-09T21:14:37+03:00 |
| PWD | /Users/rl/coding/moltinger-openclaw-control-plane |
| Shell | /bin/zsh |
| Git Branch | 008-clawdiy-rollout-bootstrap-fix |
| Git Status | modified (deploy-clawdiy workflow, preflight, docs, tests) |
| Docker Version | not available from sandbox context collector |
| Disk Usage | 86% used, 261Gi available |
| Memory | N/A |
| Error Type | process/rollout-diagnosis |

## Error Classification (Chain-of-Thought)

| Field | Value |
|-------|-------|
| Error Type | process / diagnosis-order |
| Confidence | high |
| Context Quality | sufficient |

### Hypotheses

| # | Hypothesis | Confidence |
|---|------------|------------|
| H1 | Я принял первый failing remote prerequisite за главный источник проблемы, не перезапустив lessons/artifacts check | 90% |
| H2 | При переходе из implementation-mode в operator-diagnosis-mode не сработал отдельный Traefik-first protocol | 85% |
| H3 | Feature-specific docs про `fleet-internal` временно перевесили production lessons про `traefik-net`, Host rule и DNS selection | 75% |

## Ошибка

После remote проверки сервера я увидел, что:

- `server_git_status=0`
- `traefik-net=ok`
- `moltinger_monitoring=ok`
- `fleet-internal=missing`
- `moltis_local_health=ok`
- DNS для `clawdiy.ainetic.tech` существует

И сразу начал двигаться к automation-fix вокруг bootstrap `fleet-internal`, не сделав отдельный повторный проход по:

- `MEMORY.md`
- `docs/LESSONS-LEARNED.md`
- `docs/INFRASTRUCTURE.md`
- историческим notes в `SESSION_SUMMARY.md`

Пользователь справедливо остановил этот ход и напомнил, что большинство сетевых проблем на `ainetic.tech` исторически связаны с Traefik, а не с произвольным новым network prerequisite.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему диагностика ушла в сторону `fleet-internal`? | Я взял первый failing prerequisite из deploy/preflight path как основной blocker и начал чинить именно его | Remote check этой сессии: `fleet-internal=missing`, при этом `traefik-net=ok`, `moltis_local_health=ok` |
| 2 | Почему первый failing prerequisite был принят за главный диагноз? | Я продолжил reasoning от workflow/preflight semantics, а не перезапустил production incident triage с опорой на lessons и infrastructure artifacts | Действия в сессии: проверка сервера → поиск в `docker-compose.clawdiy.yml` / `preflight-check.sh` / `deploy-clawdiy.yml` → patch bootstrap path |
| 3 | Почему не был выполнен повторный lessons/artifacts pass? | Сработал `target-boundary` guard против локального runtime, но не было отдельного шага, который бы принудительно переводил reasoning в `Traefik-first remote diagnosis` mode | `docs/rules/target-boundary-before-local-runtime.md` предотвращает локальный runtime drift, но не задаёт порядок remote rollout triage |
| 4 | Почему это особенно опасно в данном репозитории? | Здесь уже есть зафиксированная история продакшен-сетевых сбоев именно из-за Traefik network/rule/DNS mismatch, поэтому игнорирование этих уроков смещает приоритет диагностики | `MEMORY.md` требует проверять deploy/docker/traefik заранее; `SESSION_SUMMARY.md` и historical fixes (`e47e309`, `5572c0c`, `df36060`) фиксируют Traefik-first lessons |
| 5 | Почему ошибка может повторяться в будущих сессиях? | Без явного протокола на фазовый переход `implementation -> remote rollout diagnosis` агент будет оптимизироваться по ближайшему failing check, а не по иерархии уже извлечённых production lessons | Отсутствовал отдельный rule/checklist для remote rollout diagnosis order |

## Корневая причина

При переходе от implementation к remote rollout diagnosis не был заново запущен обязательный lessons/artifacts pass по `MEMORY.md`, `docs/LESSONS-LEARNED.md`, `docs/INFRASTRUCTURE.md` и relevant `SESSION_SUMMARY.md` notes. В результате reasoning началcя с первого нового failing prerequisite, а не с уже известных Traefik-first production invariants.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется отдельным protocol rule и короткими ссылками в project context |
| □ Systemic? | yes | Повторяемо для любых remote deploy / rollout / incident triage задач |
| □ Preventable? | yes | Через mandatory re-check порядка источников и Traefik-first triage |

## Принятые меры

1. **Немедленное исправление:** Диагностика была остановлена и возвращена к project context с повторным чтением `MEMORY.md`, `docs/LESSONS-LEARNED.md`, `docs/INFRASTRUCTURE.md`, `SESSION_SUMMARY.md`.
2. **Предотвращение:** Создано правило `docs/rules/remote-rollout-diagnosis-traefik-first.md`.
3. **Документация:** В `MEMORY.md` добавлена короткая ссылка на новый rollout-diagnosis protocol; `SESSION_SUMMARY.md` пополнен этим инцидентом.

## Связанные обновления

- [X] Новый файл правила создан (`docs/rules/remote-rollout-diagnosis-traefik-first.md`)
- [X] Краткая ссылка добавлена в `MEMORY.md`
- [X] `SESSION_SUMMARY.md` обновлён
- [X] Индекс уроков пересобран (`./scripts/build-lessons-index.sh`)
- [X] Индексация проверена через `./scripts/query-lessons.sh`

## Уроки

1. **Remote rollout blocker требует второго входа в контекст** — после первого unexpected blocker нужно заново пройти `MEMORY.md` → `docs/LESSONS-LEARNED.md` → `docs/INFRASTRUCTURE.md` → relevant `SESSION_SUMMARY.md`, а не продолжать reasoning инерцией implementation-фазы.
2. **Traefik-first before new-network-first** — на `ainetic.tech` любые routing/network симптомы сначала проверяются через `traefik-net`, `traefik.docker.network`, Host rule и DNS/IP selection, и только потом через новые internal networks.
3. **Первый failing preflight check не равен корневой причине** — workflow или preflight могут показать ближайший blocker, но production diagnosis должен учитывать уже накопленную историю инцидентов.

---

*Создано по протоколу rca-5-whys (RCA-010).*
