---
title: "Hosted Clawdiy Control UI был развернут с password auth вместо token auth"
date: 2026-03-12
severity: P2
category: process
tags: [process, openclaw, clawdiy, auth, control-ui, oauth, hosted-ui, lessons]
root_cause: "При проектировании hosted Clawdiy UI секрет human/web auth был смоделирован как server-side password presence, а не как browser-facing Control UI auth flow OpenClaw"
---

# RCA: Hosted Clawdiy Control UI был развернут с password auth вместо token auth

**Дата:** 2026-03-12  
**Статус:** Resolved  
**Влияние:** Среднее; live Clawdiy на `https://clawdiy.ainetic.tech` был доступен, но hosted Control UI не годился для нормального operator flow и блокировал UI-first OAuth bootstrap  
**Контекст:** После перехода к UI-first OAuth for `gpt-5.4` стало видно, что Clawdiy UI показывает `unauthorized: gateway password missing`

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-12T15:30:00+03:00 |
| PWD | /Users/rl/coding/moltinger-openclaw-control-plane |
| Shell | /bin/zsh |
| Git Branch | 018-clawdiy-gateway-password-ui-fix |
| Runtime Target | `ainetic.tech` / `https://clawdiy.ainetic.tech` |
| Error Type | auth / hosted-control-ui |

## Ошибка

Пользователь открыл live Clawdiy UI и получил:

- `unauthorized: gateway password missing (enter the password in Control UI settings)`
- `Disconnected from gateway`
- `Health Offline`

При этом read-only live inspection подтвердила:

- `CLAWDIY_PASSWORD` и `OPENCLAW_GATEWAY_PASSWORD` реально присутствуют в `/opt/moltinger/clawdiy/.env`
- runtime config у Clawdiy был валиден и явно стоял на `gateway.auth.mode=password`
- live server-side проблема с потерей секрета отсутствовала

То есть сбой был не в CI/CD rendering и не в runtime env, а в самом выборе auth mode для hosted Control UI сценария.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему UI писал `gateway password missing`? | В браузерной Control UI state не был введен gateway password | Live screenshot пользователя + reproduce reasoning по OpenClaw Control UI |
| 2 | Почему это происходило, хотя пароль был в runtime env? | Потому что server env не подставляется автоматически в browser-side Control UI settings | Read-only SSH inspection: `CLAWDIY_PASSWORD` и `OPENCLAW_GATEWAY_PASSWORD` есть, но UI все равно просит пароль |
| 3 | Почему hosted UI в таком режиме неудобен? | Потому что OpenClaw хранит токены для Control UI, а пароли держит только в памяти/текущей browser session | Official docs: Control UI token flow documented as default/persistable; password flow не является удобным hosted UX |
| 4 | Почему Clawdiy оказался именно в password mode? | В нашей модели human/web auth для Clawdiy был спроектирован как `CLAWDIY_PASSWORD` и `OPENCLAW_GATEWAY_PASSWORD` | `config/clawdiy/openclaw.json`, `deploy-clawdiy.yml`, `docker-compose.clawdiy.yml`, `policy.json` до фикса |
| 5 | Почему это не было поймано на этапе дизайна? | Мы валидировали наличие секрета и fail-closed поведение, но не проверили соответствие hosted Control UI UX официальной OpenClaw auth model | Specs/docs до фикса описывали UI-first OAuth, но gateway auth оставался password-based |

## Корневая причина

При проектировании hosted Clawdiy UI секрет human/web auth был смоделирован как server-side password presence, а не как browser-facing Control UI auth flow OpenClaw. В результате для hosted Traefik-backed UI был выбран `password` mode, хотя production-операторский сценарий и UI-first OAuth bootstrap требуют `token` mode.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется сменой gateway auth mode, secret contract и validation/test/doc chain |
| □ Systemic? | yes | Повторяемо для любого hosted OpenClaw UI на удаленном сервере |
| □ Preventable? | yes | Через явное правило: hosted Control UI uses token auth, not password auth |

## Принятые меры

1. **Немедленное исправление:** Clawdiy gateway переведен с `password` на `token` auth в tracked config и deploy/render pipeline.
2. **Совместимость:** До ротации поддержан legacy fallback `CLAWDIY_PASSWORD -> OPENCLAW_GATEWAY_TOKEN`, чтобы не блокировать rollout новым секретом немедленно.
3. **Предотвращение:** Создано правило `docs/rules/clawdiy-hosted-control-ui-token-auth.md`.
4. **Документация:** Обновлены `docs/SECRETS-MANAGEMENT.md`, `docs/deployment-strategy.md`, `docs/runbooks/clawdiy-repeat-auth.md`, `SESSION_SUMMARY.md`, а также fleet policy/registry refs.
5. **Проверки:** Обновлены `preflight`, `auth-check`, `auth smoke`, `security_api` tests и regression на legacy fallback.

## Связанные обновления

- [X] Новый файл правила создан (`docs/rules/clawdiy-hosted-control-ui-token-auth.md`)
- [X] Краткая ссылка добавлена в `MEMORY.md`
- [X] `SESSION_SUMMARY.md` обновлён
- [X] Индекс уроков пересобран (`./scripts/build-lessons-index.sh`)
- [X] Индексация проверена через `./scripts/query-lessons.sh`

## Уроки

1. **Hosted OpenClaw UI требует auth-модель браузера, а не только сервера** — наличие секрета в env не означает, что hosted Control UI сможет использовать его без operator bootstrap.
2. **Для hosted Control UI Clawdiy должен использовать token auth** — password auth допустим только как локальный/временный операторский путь, но не как основной режим для `https://clawdiy.ainetic.tech`.
3. **UI-first OAuth нужно валидировать на gateway auth boundary раньше provider auth** — пока hosted gateway auth неудобен, дальнейший OAuth/UAT не имеет смысла.

---

*Создано по протоколу rca-5-whys (RCA-011).*
