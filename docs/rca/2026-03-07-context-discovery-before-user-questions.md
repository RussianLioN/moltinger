---
title: "Повторный запрос уже документированных секретов"
date: 2026-03-07
severity: P2
category: process
tags: [process, context-discovery, secrets, telegram, instructions]
root_cause: "Отсутствовал жёсткий pre-check контекста перед вопросами пользователю о переменных"
---

# RCA: Повторный запрос уже документированных секретов

**Дата:** 2026-03-07
**Статус:** Resolved
**Влияние:** Среднее; потеря доверия к процессу и лишние вопросы вместо исполнения
**Контекст:** После блокировки E2E по Telegram WebHook ассистент запросил значения переменных, хотя источники были уже зафиксированы в проектной документации и CI/CD

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-07T03:xx:xx+03:00 |
| PWD | /Users/rl/.codex/worktrees/da4f/moltinger |
| Git Branch | codex/full-review |
| Error Type | process/communication |
| Trigger | Вопрос о `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, webhook URL при наличии documented source-of-truth |

## Error Classification (Chain-of-Thought)

| Field | Value |
|-------|-------|
| Error Type | process + communication |
| Confidence | high |
| Context Quality | sufficient |

### Hypotheses

| # | Hypothesis | Confidence |
|---|------------|------------|
| H1 | Не был выполнен обязательный lookup контекста перед вопросом пользователю | 85% |
| H2 | Правило о source-of-truth было неявным и не встроено в стартовый чеклист агента | 80% |
| H3 | Вопрос был задан для ускорения, но без проверки известных артефактов | 65% |

## Ошибка

Ассистент задал уточняющий вопрос о значениях переменных для Telegram, хотя в проекте уже зафиксированы:
- источник истины: GitHub Secrets;
- runtime-копия: `/opt/moltinger/.env`;
- автоматическая генерация `.env` в CI/CD workflow.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему был задан лишний вопрос пользователю? | Ассистент не использовал все доступные источники контекста перед вопросом | Факт диалога в текущей сессии |
| 2 | Почему lookup контекста не сработал как обязательный шаг? | Для запроса переменных не было жёсткого "pre-question" gate в стартовых инструкциях | До фикса `AGENTS.md` содержал только beads/push workflow без context-first секции |
| 3 | Почему это привело именно к запросу про секреты? | Информация о секретах была распределена по нескольким файлам и не была собрана в короткий обязательный протокол | `docs/SECRETS-MANAGEMENT.md:12`, `docs/SECRETS-MANAGEMENT.md:43-46`, `SESSION_SUMMARY.md:113-123`, `.github/workflows/deploy.yml:537-563` |
| 4 | Почему распределённые знания не были применены? | В инструкции отсутствовал явный порядок проверки источников перед вопросами пользователю | Отсутствовал formal lookup order в shared instructions до RCA-008 |
| 5 | Почему это повторяемый риск между сессиями? | Без единого правила и короткой ссылки в стартовых файлах новые сессии могут снова пропускать этот шаг | Не было централизованного правила в `docs/rules/` и ссылок из всех ключевых entrypoints |

## Корневая причина

Отсутствовал жёсткий, централизованный и повторяемый протокол "context discovery before questions" в стартовых инструкциях агента; знание о секретах было в проекте, но не было закреплено как обязательный pre-check перед вопросами пользователю.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Добавить обязательный lookup protocol в инструкции и правила |
| □ Systemic? | yes | Затрагивает все будущие сессии/агентов |
| □ Preventable? | yes | Через единый чеклист и ссылки в entrypoint-файлах |

## Принятые меры

1. **Немедленное исправление:** Добавлено правило `docs/rules/context-discovery-before-questions.md`.
2. **Предотвращение:** В `AGENTS.md` (через `.ai/instructions/shared-core.md`) добавлен обязательный `Context-First Rule (Mandatory)`.
3. **Документация:** Добавлены короткие ссылки/правила в `CLAUDE.md`, `MEMORY.md`, `SESSION_SUMMARY.md`, `docs/SECRETS-MANAGEMENT.md`.

## Связанные обновления

- [X] Новый файл правила создан (`docs/rules/context-discovery-before-questions.md`)
- [X] Краткая ссылка/чеклист добавлены в `CLAUDE.md`
- [X] `MEMORY.md` обновлён секцией source-of-truth
- [X] `SESSION_SUMMARY.md` обновлён секцией source-of-truth
- [X] `AGENTS.md` пересобран из `.ai/instructions/shared-core.md`
- [X] Индекс уроков пересобран (`./scripts/build-lessons-index.sh`)

## Уроки

1. **Сначала контекст, потом вопрос** — перед уточняющими вопросами нужно пройти фиксированный lookup order по ключевым артефактам.
2. **Source-of-truth должен быть в entrypoint-инструкциях** — знание в глубокой документации недостаточно без короткого обязательного правила на старте сессии.
3. **Вопрос пользователю — только после gap analysis** — сначала показать, что найдено, и спрашивать только недостающее.

---

*Создано по протоколу rca-5-whys (RCA-008).*
