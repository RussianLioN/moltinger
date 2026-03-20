---
title: "SSH heredoc runner-side expansion in deploy workflow"
date: 2026-03-20
severity: P1
category: cicd
tags: [deploy, github-actions, ssh, heredoc, rca]
root_cause: "Unquoted heredoc in remote ssh step allowed runner-side shell expansion of remote variables and command substitutions."
---

# RCA: SSH heredoc runner-side expansion in deploy workflow

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** Production deploy падал на шаге `Update active deploy root symlink` при корректном состоянии сервера.

## Ошибка

Симптомы:

- `Deploy Moltis` run `23341975775` завершился `failure`.
- Падение на шаге `Update active deploy root symlink`.
- На сервере при этом ` /opt/moltinger-active -> /opt/moltinger` уже был корректным symlink, то есть состояние target было валидным, но job все равно завершался с exit code `1`.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему шаг `Update active deploy root symlink` падал? | Команда завершалась `exit code 1` без диагностического сообщения из remote-скрипта. | GitHub Actions log run `23341975775`, job `67897873911` |
| 2 | Почему не было remote-диагностики при падении? | Ошибка происходила на runner во время подготовки heredoc, до полного корректного исполнения remote-блока. | Репродукция локально: `bash -euxo pipefail` + `ssh << EOF` |
| 3 | Почему runner исполнял часть remote-скрипта локально? | Использовался неэкранированный heredoc `<< EOF`; локальный shell разворачивал `$LEGACY_BACKUP` и `$(...)`. | Фрагмент workflow шага symlink update |
| 4 | Почему это приводило к `exit 1`? | При `set -u` локальная подстановка `$LEGACY_BACKUP` вызывала `unbound variable`, прерывая шаг. | Репродукция: `bash: line 1: LEGACY_BACKUP: unbound variable` |
| 5 | Почему это попало в production pipeline? | Не было policy и unit-guard теста на quoted heredoc именно для remote symlink-шагов. | Отсутствие проверки `<< 'EOF'` в `tests/unit/test_deploy_workflow_guards.sh` |

## Корневая причина

В production deploy-пайплайне remote ssh-блок был оформлен неэкранированным heredoc (`<< EOF`), из-за чего shell runner-а локально разворачивал remote-переменные и command substitution.  
Это процессная ошибка в шаблоне workflow, а не проблема серверного состояния.

## Принятые меры

1. **Немедленное исправление:**  
   Переведены symlink-шаги в `deploy.yml` и `uat-gate.yml` на quoted heredoc: `<< 'EOF'`.
2. **Hardening:**  
   Добавлены явные проверки с диагностикой:
   - active path после обновления обязан быть symlink;
   - target symlink обязан совпадать с `${{ env.DEPLOY_PATH }}`.
3. **Предотвращение:**  
   Добавлен regression test в `tests/unit/test_deploy_workflow_guards.sh`, который валидирует quoted heredoc в symlink-шагах обоих workflow.
4. **Документация:**  
   Добавлено правило в `docs/rules/github-actions-remote-ssh-heredoc-quoting.md`.

## Связанные обновления

- [x] Новый файл правила создан (`docs/rules/github-actions-remote-ssh-heredoc-quoting.md`)
- [ ] Краткая ссылка добавлена в CLAUDE.md
- [ ] Новые навыки созданы
- [x] Тесты добавлены

## Уроки

1. **Remote ssh steps в GitHub Actions должны использовать quoted heredoc** — для удаленного скрипта применять `<< 'EOF'`, иначе shell runner-а может выполнить подстановки локально.
2. **Нельзя полагаться на “тихие” `test` без контекста** — при проверках symlink добавлять явные сообщения об ошибке и текущем состоянии пути.
3. **Workflow-политики должны быть тестируемыми** — heredoc quoting и критичные deploy-инварианты обязаны иметь unit-guard.
