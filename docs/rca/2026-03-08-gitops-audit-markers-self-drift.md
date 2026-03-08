---
title: "Self-inflicted GitOps drift from deployment audit markers"
date: 2026-03-08
severity: P1
category: cicd
tags: [gitops, deploy, drift-detection, github-actions, audit]
root_cause: "Deploy workflow conflated runtime deployment state with GitOps drift: it wrote audit markers into repo root and also treated intended repo-to-server deltas as hard drift"
---

# RCA: Self-inflicted GitOps drift from deployment audit markers

**Дата:** 2026-03-08
**Статус:** Resolved
**Влияние:** Высокое; deploy run из `main` блокировались, хотя часть drift создавалась самим workflow, а часть была обычным pending sync для deploy-managed файлов
**Контекст:** Разбор падений `Deploy Moltis` runs `22826884877` и `22827296133`

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-08T18:50:00Z |
| PWD | /Users/rl/.codex/worktrees/da4f/moltinger |
| Shell | /bin/zsh |
| Git Branch | codex/full-review |
| Git Commit | 0234a55 |
| Server Path | /opt/moltinger |
| Server HEAD | 01da067 |
| Error Type | cicd |

## Ошибка

`Deploy Moltis` из `main` падал на шаге `Block deployment on GitOps drift`:

- run `22826884877` от 2026-03-08T18:13:31Z
- run `22827296133` от 2026-03-08T18:37:18Z

На сервере `/opt/moltinger` при этом наблюдались untracked файлы:

- `.deployed-sha`
- `.deployment-info`

Именно они делали `git status --porcelain` непустым.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему deploy блокировался? | GitOps compliance gate видел drift и останавливал job до deploy | Runs `22826884877`, `22827296133`, `22827569709` падали на `Block deployment on GitOps drift` |
| 2 | Почему gate видел drift? | Он смешивал два разных случая: dirty worktree и обычную разницу между текущим repo и уже задеплоенным сервером | Логи показывали как `git status --porcelain`, так и `scripts/... DRIFT DETECTED (local != server)` |
| 3 | Почему dirty worktree вообще появлялся? | Сам workflow писал `.deployed-sha` и `.deployment-info` в repo root | [deploy.yml](/Users/rl/.codex/worktrees/da4f/moltinger/.github/workflows/deploy.yml):969-972 до фикса |
| 4 | Почему даже после переноса marker-файлов deploy всё ещё блокировался? | Workflow считал planned repo-to-server deltas в `scripts/` и `systemd/` hard drift, хотя это и есть содержимое предстоящего deploy | Лог run `22827569709`: `scripts/manifest.json`, `scripts/setup-telegram-web-user-monitor.sh`, `scripts/telegram-web-user-monitor.sh`, `systemd/moltis-telegram-web-user-monitor.service` reported as drift при clean server worktree |
| 5 | Почему проблема системная? | File-sync deploy не разделял declarative drift и pending sync, и не выравнивал server git checkout после успешного deploy | До фикса не было ни `pending_sync` семантики, ни post-deploy `git fetch/reset` |

## Корневая причина

Workflow смешивал три разных состояния в один `drift` сигнал:

1. runtime audit metadata в git-managed root;
2. реальный dirty server worktree;
3. обычный pending sync между текущим git и уже задеплоенным сервером.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется переносом marker-файлов в ignored state path |
| □ Systemic? | yes | Паттерн применим ко всем server-side audit artifacts |
| □ Preventable? | yes | Через правило: runtime markers не писать в git-managed root |

## Принятые меры

1. **Немедленное исправление:** post-deploy audit markers перенесены из repo root в `data/.deployed-sha` и `data/.deployment-info`.
2. **Немедленное исправление:** compliance gate теперь различает `server_dirty` и `pending_sync`; planned file deltas больше не блокируют deploy.
3. **Немедленное исправление:** после успешного deploy server git checkout выравнивается до текущего `${github.sha}`.
4. **Временная remediation:** существующие top-level marker-файлы на сервере вручную перенесены в `data/`, чтобы снять текущий dirty state.
5. **Предотвращение:** добавлены static tests, которые проверяют marker path, checkout alignment и distinction between dirty drift vs pending sync.

## Связанные обновления

- [X] RCA-отчёт создан в `docs/rca/`
- [X] Добавлен static guard в `tests/static/test_config_validation.sh`
- [X] Lessons пересобраны
- [ ] Новый policy rule не потребовался

## Уроки

1. **GitOps audit artifacts не должны жить в git-managed root** — иначе pipeline начинает детектить собственный мусор как drift.
2. **Drift gate должен различать dirty state и planned sync** — иначе любой config/script deploy будет сам себе блокером.
3. **File-sync deploy обязан выравнивать server git checkout** — иначе `git status` теряет смысл уже после первого успешного rollout.
4. **Для CI/CD self-state нужен regression guard** — дешёвый static test лучше повторяющихся blocked deploy runs.

---

*Создано по протоколу RCA (5 Why) для deploy runs `22826884877` и `22827296133`.*
