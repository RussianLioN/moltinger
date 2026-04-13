---
title: "Deploy host automation missing cron package bootstrap"
date: 2026-04-14
severity: P1
category: cicd
tags: [deploy, cron, scheduler, host-automation, apt]
root_cause: "Tracked host automation assumed an existing cron/crond systemd unit and had no package-bootstrap path for fresh Debian/Ubuntu hosts."
---

# RCA: Deploy host automation missing cron package bootstrap

**Дата:** 2026-04-14  
**Статус:** Resolved  
**Влияние:** Production deploy после merge `#173` не смог завершить host automation, поэтому live Moltis не получил исправление Telegram-safe guard и scheduler path остался без прод-роллаута.  
**Контекст:** beads `moltinger-1inj`, deploy run `24366831337`, шаг `Apply Moltis host automation from active deploy root`.

## Ошибка

Симптомы:

- `Deploy Moltis` run `24366831337` завершился `failure`.
- Падение произошло на шаге `Apply Moltis host automation from active deploy root`.
- Лог завершался строкой: `apply-moltis-host-automation.sh: unable to resolve a cron service unit (expected cron or crond)`.

Дополнительные факты:

- На хосте `root@ainetic.tech` присутствовал cron file `/etc/cron.d/moltis-codex-upstream-watcher`, но `systemctl list-unit-files` не показывал ни `cron.service`, ни `crond.service`.
- На том же хосте был доступен `apt-get`, а `/etc/os-release` подтверждал `Ubuntu 22.04.5 LTS`.
- Значит, проблема была не в "inactive service", а в полном отсутствии установленного scheduler package.

## Проверка прошлых уроков

**Проверенные источники:**

- `docs/LESSONS-LEARNED.md`
- `./scripts/query-lessons.sh --tag deploy`
- `./scripts/query-lessons.sh --tag cron`

**Релевантные прошлые RCA/уроки:**

1. `docs/rca/2026-03-28-moltis-repo-skill-sync-trap-broke-deploy-verification.md` — deploy helper scripts должны иметь blocking regression coverage на failure-path.
2. `docs/rca/2026-03-20-deploy-collision-and-active-root-symlink-guard.md` — deploy control plane нужно вытаскивать в versioned script entrypoints, а не держать implicit behavior в workflow.

**Что могло быть упущено без этой сверки:**

- можно было снова ограничиться server-only workaround (`systemctl start cron`) вместо source fix в owning helper;
- можно было закрыть incident без unit coverage на package-bootstrap path.

**Что в текущем инциденте действительно новое:**

- helper уже управлял cron/systemd convergence, но не умел materialize сам dependency package на чистом Debian/Ubuntu host.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему production deploy упал на host automation? | Скрипт не смог разрешить `cron`/`crond` unit и завершился ошибкой. | `gh run view 24366831337 --log-failed` |
| 2 | Почему `cron`/`crond` unit не разрешился? | На сервере не было установленного пакета cron, поэтому `systemctl` не видел соответствующий unit. | `systemctl list-unit-files`, `command -v cron`, `command -v crond` на `root@ainetic.tech` |
| 3 | Почему отсутствие пакета не было обработано автоматически? | `scripts/apply-moltis-host-automation.sh` умел только reload/restart/enable existing service, но не имел bootstrap path для missing package. | Исходный код helper до фикса |
| 4 | Почему такой сценарий прошёл в `main` без guard? | Unit tests покрывали только "service exists but inactive" и "service remains inactive", но не "service missing because package absent". | `tests/unit/test_deploy_workflow_guards.sh` до фикса |
| 5 | Почему coverage не поймала реальный production prerequisite? | Мы зафиксировали operational contract на уровне systemd activation, но не сформулировали более базовую инварианту: helper обязан либо materialize scheduler dependency, либо fail с явной diagnostic причиной. | Разрыв между live host facts и проверяемым тестовым контрактом |

## Корневая причина

Tracked deploy helper предполагал, что на целевом Debian/Ubuntu host уже существует systemd unit `cron`/`crond`.  
Это было неверное инфраструктурное предположение: при свежем или неполном хосте helper не materialize-ил обязательный scheduler dependency package и не имел regression test на этот prerequisite.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| Actionable? | yes | Исправляется в owning helper script и test contract |
| Systemic? | yes | Ошибка в versioned deploy control-plane, а не в единичном ручном действии |
| Preventable? | yes | Покрывается package-bootstrap path + unit regressions |

## Принятые меры

1. **Немедленное исправление:**  
   `scripts/apply-moltis-host-automation.sh` теперь при отсутствии `cron`/`crond` unit пытается официально bootstrap-нуть пакет `cron` через `apt-get update -yqq && apt-get install -y -qq cron`, затем повторно разрешает service и продолжает activation contract.
2. **Предотвращение:**  
   В `tests/unit/test_deploy_workflow_guards.sh` добавлены блокирующие regression tests на:
   - успешный package bootstrap при отсутствии cron unit;
   - явный fail-fast, если `apt-get install cron` не удаётся.
3. **Документация:**  
   Создан этот RCA; lessons flow обновлён через пересборку индекса уроков.

## Связанные обновления

- [ ] Новый файл правила создан
- [ ] Краткая ссылка добавлена в CLAUDE.md
- [ ] Новые навыки созданы
- [x] Тесты добавлены
- [x] Новый RCA создан

## Уроки

1. Для deploy helper-а "service activation" недостаточно, если runtime dependency может отсутствовать на хосте целиком.
2. Host automation должна либо materialize обязательную системную зависимость официальным путём, либо падать с explicit diagnostic message вместо общего `unable to resolve`.
3. Production prerequisites нужно закреплять unit-тестами не только на happy path existing-service, но и на fresh-host package-missing path.
