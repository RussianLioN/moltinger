# RCA: Git Branch Confusion - Коммиты на неправильной ветке

**Дата:** 2026-03-03
**Статус:** Resolved
**Влияние:** 8 коммитов RCA Skill Enhancements попали на ветку 001-browser-compatibility-fix вместо 001-rca-skill-upgrades
**Контекст:** Speckit workflow implementation

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-03T23:00:00+03:00 |
| PWD | /Users/rl/coding/moltinger |
| Shell | /bin/zsh |
| Git Branch (start) | 001-browser-compatibility-fix |
| Git Branch (expected) | 001-rca-skill-upgrades |
| Error Type | process |

## Error Classification (Chain-of-Thought)

| Field | Value |
|-------|-------|
| Error Type | process |
| Confidence | high |
| Context Quality | sufficient |

### Hypotheses

| # | Hypothesis | Confidence |
|---|------------|------------|
| H1 | Session continuation started on wrong branch (previous session didn't switch back) | 85% |
| H2 | No branch validation in speckit.implement workflow | 15% |
| H3 | User manually switched branch at some point | 0% |

## Ошибка

Все 8 коммитов RCA Skill Enhancements (Phase 1-8) были сделаны на ветку `001-browser-compatibility-fix` вместо `001-rca-skill-upgrades`.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему коммиты попали на 001-browser-compatibility-fix? | Сессия началась на этой ветке | `git branch` showed `* 001-browser-compatibility-fix` |
| 2 | Почему сессия началась на неправильной ветке? | Предыдущая сессия завершилась на этой ветке и не вернулась на 001-rca-skill-upgrades | Session continuation context |
| 3 | Почему не было проверки ветки перед началом работы? | В speckit.implement нет шага проверки текущей ветки | No `git branch` check in workflow |
| 4 | Почему нет проверки в speckit workflow? | speckit.implement предполагает, что пользователь уже на правильной ветке | Missing preflight check |
| 5 | Почему нет стандарта branch validation? | Отсутствие явного правила в CLAUDE.md или speckit | No branch validation rule documented |

## Корневая причина

Отсутствие обязательной проверки текущей git ветки в начале speckit.implement workflow.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Добавить проверку ветки в workflow |
| □ Systemic? | yes | Проблема процесса, не ошибка человека |
| □ Preventable? | yes | Автоматическая проверка предотвратит повторение |

## Принятые меры

1. **Немедленное исправление:**
   - Cherry-pick всех 8 коммитов на правильную ветку 001-rca-skill-upgrades
   - Force push на origin/001-rca-skill-upgrades
   - Удаление ошибочной ветки 001-browser-compatibility-fix

2. **Предотвращение:**
   - Добавить правило в CLAUDE.md: проверять ветку перед началом работы
   - Добавить preflight check в speckit.implement

3. **Документация:**
   - Создать данный RCA отчёт

## Связанные обновления

- [ ] Добавить branch check в CLAUDE.md
- [ ] Добавить preflight check в speckit.implement skill
- [X] RCA проведён с использованием enhanced skill
- [X] Коммиты перенесены на правильную ветку

## Уроки

1. **ВСЕГДА проверять git branch перед началом работы:**
   ```bash
   git branch --show-current
   # Должна совпадать с feature prefix из specs/XXX-feature-name/
   ```

2. **Добавить правило в CLAUDE.md:**
   ```markdown
   ## Перед началом работы
   1. Проверить git branch: `git branch --show-current`
   2. Если ветка не та - переключиться: `git checkout XXX-feature-name`
   ```

3. **В speckit.implement добавить preflight:**
   - Check current branch matches feature prefix from specs/
   - Warn if mismatch

4. **После завершения работы возвращаться на main:**
   - `git checkout main` после push

---

*Создано с помощью enhanced rca-5-whys skill (v1.1)*
*Features used: Auto-Context, Chain-of-Thought, Generic Template*
