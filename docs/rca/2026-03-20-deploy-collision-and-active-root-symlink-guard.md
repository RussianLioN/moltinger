---
title: "Deploy collision and active-root symlink guard"
date: 2026-03-20
severity: P1
category: cicd
tags: [deploy, github-actions, concurrency, symlink, gitops]
root_cause: "Branch-scoped deploy concurrency plus fragile ln -sfn symlink update logic without legacy directory migration."
---

# RCA: Deploy collision and active-root symlink guard

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** Production deploy мог падать на шаге `Update active deploy root symlink`, а параллельные deploy-пайплайны могли конфликтовать на одном сервере.

## Ошибка

Симптомы:

- `Deploy Moltis` run `23339680970` завершился `failure`.
- Падение на шаге `Update active deploy root symlink`.
- Пользователь зафиксировал системный риск столкновений при параллельных deploy в разных ветках.

Дополнительные факты:

- В `deploy.yml` использовался branch-scoped lock: `group: deploy-${{ github.ref }}`.
- В `uat-gate.yml` у production deploy-джобы не было общего lock с `deploy.yml`.
- Шаг symlink-обновления использовал `ln -sfn` + `test -L`, что ломается при legacy-состоянии, когда target path уже real directory.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему падал шаг обновления active-root? | Проверка `test -L /opt/moltinger-active` возвращала ошибку. | `deploy.yml` шаг `Update active deploy root symlink` |
| 2 | Почему `test -L` мог возвращать ошибку после `ln -sfn`? | `ln -sfn` не заменяет existing real directory; создаёт nested symlink внутри директории. | Локальная репродукция: `ln -sfn <target> <existing_dir>` + `[ -L <existing_dir> ] -> false` |
| 3 | Почему такой legacy-сценарий не был покрыт? | В workflow не было миграции non-symlink path в backup перед созданием symlink. | Отсутствие guard-блока `if [ -e ... ] && [ ! -L ... ]` |
| 4 | Почему конфликт проявлялся как системный риск, а не единичный сбой? | Параллельные production deploy могли менять одно и то же remote state без единого lock. | `deploy.yml` имел lock по branch (`deploy-${{ github.ref }}`), а `uat-gate.yml` не имел shared production lock |
| 5 | Почему это допустили в процессе? | Не была закреплена инварианта "single writer" для production target + не было unit-guard теста на workflow lock policy. | Отсутствовали тесты на shared lock group и на legacy symlink migration guard |

## Корневая причина

Система деплоя не обеспечивала инварианту "один writer на production target" и предполагала, что `/opt/moltinger-active` всегда уже symlink.  
Это комбинация двух причин:

1. Неправильная гранулярность concurrency (branch-scoped вместо target-scoped).
2. Хрупкая логика `ln -sfn` без миграции legacy directory-состояния.

## Принятые меры

1. **Немедленное исправление:**  
   В `deploy.yml` добавлен shared production lock:
   `group: prod-remote-ainetic-tech-opt-moltinger`.
2. **Предотвращение:**  
   В `uat-gate.yml` deploy-джобе добавлен тот же lock group, чтобы все mutating deploy paths serializовались.
3. **Hardening symlink шага:**  
   В `deploy.yml` и `uat-gate.yml` добавлена legacy migration логика: если active path существует и не symlink, он переносится в timestamp backup, затем создаётся корректный symlink.
4. **Regression guard:**  
   Добавлен unit test `tests/unit/test_deploy_workflow_guards.sh`, который проверяет:
   - shared production lock group в workflow,
   - отсутствие branch-scoped deploy group в `deploy.yml`,
   - наличие legacy migration guard для active-root symlink.

## Follow-up hardening (moltinger-4hqr, first slice)

После инцидентных фиксов обнаружилось, что корень проблемы глубже, чем отдельные YAML-баги:

- критичная active-root orchestration была продублирована в `.github/workflows/deploy.yml` и `.github/workflows/uat-gate.yml`;
- drift уже затронул не только тело SSH-блока, но и его входной контракт: в `uat-gate.yml` шаг ссылался на `DEPLOY_ACTIVE_PATH`, не объявляя его в workflow `env`;
- каждое новое исправление приходилось вносить в два workflow вручную, что создавало повторяемый риск расхождения.

Первый control-plane slice вынес active-root update и safety checks в единый versioned script entrypoint `scripts/update-active-deploy-root.sh`, а workflow оставил тонкими вызовами этого script. Это переводит источник истины из inline YAML в versioned shell contract и снижает вероятность повторного drift.

## Связанные обновления

- [x] Новый файл правила создан (`docs/rules/production-deploy-single-writer.md`)
- [ ] Краткая ссылка добавлена в CLAUDE.md
- [ ] Новые навыки созданы
- [x] Тесты добавлены

## Уроки

1. **Single writer для production обязателен** — concurrency group должен быть target-scoped (host/path), а не branch-scoped.
2. **`ln -sfn` не мигрирует real directory** — перед symlink update нужен explicit guard на legacy path type.
3. **Workflow policy должна быть тестируемой** — lock policy и migration guards нужно фиксировать unit-тестами, иначе регрессии возвращаются.
