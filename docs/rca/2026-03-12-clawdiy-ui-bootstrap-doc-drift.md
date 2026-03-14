---
title: "Clawdiy UI bootstrap был задокументирован как Settings/OAuth flow вместо реального browser bootstrap"
date: 2026-03-12
severity: P2
category: process
tags: [process, docs, openclaw, clawdiy, ui, onboarding, pairing, oauth, lessons]
root_cause: "Проектная документация смешала browser access bootstrap и provider OAuth lifecycle без повторной проверки official docs и live first-screen behavior"
---

# RCA: Clawdiy UI bootstrap был задокументирован как Settings/OAuth flow вместо реального browser bootstrap

**Дата:** 2026-03-12  
**Статус:** Resolved  
**Влияние:** Среднее; пользователь шел по неверному UI пути и не видел обещанного стартового экрана/настройки, хотя live Clawdiy уже работал  
**Контекст:** После исправления gateway token auth выяснилось, что локальная документация все еще отправляет нового оператора в несуществующий `Settings/OAuth` first-run flow

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-12T23:40:00+03:00 |
| PWD | /Users/rl/coding/moltinger-openclaw-control-plane |
| Shell | /bin/zsh |
| Git Branch | 019-clawdiy-ui-onboarding-doc-correction |
| Runtime Target | `ainetic.tech` / `https://clawdiy.ainetic.tech` |
| Error Type | process / docs / ui-bootstrap |

## Ошибка

В документации репозитория было записано, что первый practical path для Clawdiy идет через live `Settings` area и запуск `OpenAI Codex` login прямо оттуда.

Фактическое live поведение оказалось другим:

- fresh browser profile получает `Version n/a` и `Health Offline`
- первая полезная точка входа находится в `Overview -> Gateway Access`
- подключение требует `Gateway Token` и device pairing
- отдельного welcome wizard или подтвержденного provider-auth UI на первом экране нет

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему пользователь не смог пройти “с первого экрана” по docs? | Потому что live UI не показывал обещанный Settings/OAuth start path | Live Playwright snapshots on `https://clawdiy.ainetic.tech` |
| 2 | Почему docs обещали не тот путь? | Потому что репо зафиксировало `web Settings OAuth` как preferred first attempt | `docs/runbooks/clawdiy-repeat-auth.md`, `docs/deployment-strategy.md`, `specs/017...` до правки |
| 3 | Почему это попало сразу в несколько артефактов? | Потому что предположение из OAuth research было распространено в runbook/spec docs как уже подтвержденный UI contract | `docs/research/clawdiy-openclaw-remote-oauth-runtime-2026-03-12.md` + downstream docs до правки |
| 4 | Почему assumption не был пойман раньше? | Потому что мы проверяли server/runtime blockers и поздний chat path, но не перезаписали first-run browser path отдельным live verification шагом | Session evidence: UI shell was checked later than docs wording was updated |
| 5 | Почему это системная проблема? | Потому что browser bootstrap и provider OAuth были смешаны в одну абстракцию “UI-first auth” | Official docs split dashboard/control-ui/device flow from provider auth flow |

## Корневая причина

Проектная документация смешала browser access bootstrap и provider OAuth lifecycle без повторной проверки official docs и live first-screen behavior. В результате операторский путь был описан как `Settings/OAuth`, хотя реальный hosted Clawdiy first-run path начинается с `Overview -> Gateway Access -> token -> pairing`.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется правкой docs/runbooks/spec artifacts и добавлением отдельного browser-bootstrap runbook |
| □ Systemic? | yes | Повторится для любого hosted OpenClaw UI, если first-screen path не проверять отдельно |
| □ Preventable? | yes | Через правило: сначала live browser bootstrap verification, потом документация provider auth |

## Принятые меры

1. **Немедленное исправление:** Обновлены runbook/spec docs, где `Settings/OAuth` был записан как first-run path.
2. **Предотвращение:** Добавлено правило [docs/rules/clawdiy-browser-bootstrap-before-provider-auth.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/rules/clawdiy-browser-bootstrap-before-provider-auth.md).
3. **Документация:** Создан отдельный operator runbook [docs/runbooks/clawdiy-browser-bootstrap.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-browser-bootstrap.md) и research note [docs/research/clawdiy-openclaw-browser-bootstrap-2026-03-12.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/clawdiy-openclaw-browser-bootstrap-2026-03-12.md).

## Связанные обновления

- [X] Новый файл правила создан (`docs/rules/clawdiy-browser-bootstrap-before-provider-auth.md`)
- [X] Краткая ссылка добавлена в `MEMORY.md`
- [X] `SESSION_SUMMARY.md` обновлён
- [X] Индекс уроков пересобран (`./scripts/build-lessons-index.sh`)
- [X] Индексация проверена через `./scripts/query-lessons.sh`

## Уроки

1. **Не путать browser bootstrap и provider auth** — hosted OpenClaw сначала требует browser/device bootstrap, и только потом имеет смысл обсуждать OAuth провайдера.
2. **Нельзя документировать UI path только по inference** — first-run flow надо перепроверять и по official docs, и глазами в live browser.
3. **Отсутствие welcome wizard не означает поломку сервиса** — для hosted Clawdiy нормальный first screen это disconnected dashboard shell с `Gateway Access`.

---

*Создано по протоколу rca-5-whys (RCA-012).*
