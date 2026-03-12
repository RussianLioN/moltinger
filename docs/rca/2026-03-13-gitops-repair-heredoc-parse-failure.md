---
title: "GitOps repair workflow failed before execution because inline heredoc was not parse-safe in GitHub Actions"
date: 2026-03-13
severity: P1
category: shell
tags: [gitops, github-actions, bash, heredoc, moltis]
root_cause: "A complex remote-repair block was embedded as an inline SSH heredoc inside deploy.yml, and its closing delimiter was indented by the YAML run block, so bash failed during parsing before branch conditions were evaluated"
---

# RCA: GitOps repair workflow failed before execution because inline heredoc was not parse-safe in GitHub Actions

**Дата:** 2026-03-13
**Статус:** Resolved
**Влияние:** Высокое; production run `23029168487` и follow-up run `23029278583` не дошли до backup/deploy, потому что `GitOps Compliance Check` падал на bash parse error в `Check GitOps compliance`
**Контекст:** Разбор GitHub Actions logs для runs `23029168487` и `23029278583`

## Ошибка

Production workflow `Deploy Moltis` падал на шаге `Check GitOps compliance` с ошибками:

- `warning: here-document at line 140 delimited by end-of-file (wanted \`EOF')`
- `unexpected EOF while looking for matching ')'`

При этом run `23029278583` шёл без `repair_server_checkout=true`, но всё равно падал на парсинге того же shell-блока.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему production deploy не дошёл до backup/deploy steps? | Потому что `GitOps Compliance Check` завершался bash syntax error ещё до исполнения repair-ветки | GitHub log run `23029278583`, job `66884023026` |
| 2 | Почему shell падал на синтаксисе, хотя `repair_server_checkout=false`? | Потому что bash сначала парсит весь `run:` block целиком, а уже потом исполняет ветки условий | Ошибка возникала на том же шаге до любого runtime-вывода из repair path |
| 3 | Почему bash не смог распарсить repair-блок? | Потому что inline heredoc `<<'EOF'` был закрыт строкой `EOF` с отступом внутри YAML block scalar | Локальный `deploy.yml` и log: shell ждал `EOF` до конца файла |
| 4 | Почему repair-логика оказалась в таком хрупком виде? | Потому что сложный remote reconcile был встроен прямо в workflow вместо отдельного script entrypoint | `deploy.yml` содержал длинный `ssh ... <<'EOF'` внутри command substitution |
| 5 | Почему этот дефект не поймали до production rerun? | Потому что статические проверки валидировали YAML и бизнес-guard, но не охраняли parse-safe contract для inline heredoc в deploy workflow | `tests/static/test_config_validation.sh` не проверял отсутствие этого паттерна |

## Корневая причина

Сложная GitOps repair-логика была размещена в inline shell inside workflow, а не в отдельном скрипте. Из-за этого YAML-отступы сломали heredoc delimiter, и bash не мог распарсить workflow step даже когда repair path не должен был исполняться.

## Принятые меры

1. **Немедленное исправление:** remote repair вынесен в `scripts/gitops-repair-managed-checkout.sh`.
2. **Немедленное исправление:** `deploy.yml` теперь вызывает этот script entrypoint вместо inline SSH heredoc.
3. **Предотвращение:** добавлен static guard, который запрещает возвращать такой inline heredoc-pattern в deploy workflow.
4. **Документация:** инцидент зафиксирован отдельным RCA для lessons index.

## Связанные обновления

- [X] RCA-отчёт создан в `docs/rca/`
- [X] Static guard добавлен в `tests/static/test_config_validation.sh`
- [ ] Отдельный policy file не потребовался

## Уроки

1. **GitHub Actions `run:` block нужно считать shell source code, а не просто многострочным текстом**: parser hazards ломают даже неисполняемые ветки.
2. **Сложную deploy/reconcile shell-логику нельзя держать inline в workflow**, если она требует heredoc или многоступенчатого quoting.
3. **Static CI guard должен ловить parser-sensitive shell patterns**, а не только YAML syntax и высокоуровневые GitOps assertions.

---

*Создано по протоколу RCA (5 Why) для failed runs `23029168487` и `23029278583`.*
