# RCA: [Краткое описание проблемы]

**Дата:** YYYY-MM-DD
**Статус:** Resolved / In Progress
**Влияние:** [описание воздействия на пользователей/систему]
**Контекст:** [сессия/задача/компонент]

## Context

*Автоматически собирается через `bash .claude/skills/rca-5-whys/lib/context-collector.sh <error_type>`*

| Field | Value |
|-------|-------|
| Timestamp | [ISO datetime] |
| PWD | [working directory] |
| Shell | [shell type] |
| Git Branch | [branch or N/A] |
| Git Status | [short status] |
| Docker Version | [version or N/A] |
| Disk Usage | [percentage] |
| Memory | [used/total] |
| Error Type | [docker/cicd/shell/data-loss/generic] |

## Error Classification (Chain-of-Thought)

| Field | Value |
|-------|-------|
| Error Type | [infra/code/config/process/communication] |
| Confidence | [high/medium/low] |
| Context Quality | [sufficient/partial/insufficient] |

### Hypotheses

| # | Hypothesis | Confidence |
|---|------------|------------|
| H1 | [наиболее вероятная причина] | X% |
| H2 | [вторая причина] | Y% |
| H3 | [третья причина] | Z% |

## Ошибка

[Описание симптома - что произошло, как проявилось]

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему [симптом]? | [ответ] | [источник: logs/command/output] |
| 2 | Почему [ответ1]? | [ответ] | [источник] |
| 3 | Почему [ответ2]? | [ответ] | [источник] |
| 4 | Почему [ответ3]? | [ответ] | [источник] |
| 5 | Почему [ответ4]? | [ответ] | [источник] |

## Корневая причина

[Итоговый вывод - системная причина, на которую можно повлиять]

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | [yes/no] | Можно ли исправить? |
| □ Systemic? | [yes/no] | Это системная проблема? |
| □ Preventable? | [yes/no] | Можно ли предотвратить в будущем? |

[Итоговый вывод - системная причина, на которую можно повлиять]

## Принятые меры

1. **Немедленное исправление:** [что сделано для устранения симптома]
2. **Предотвращение:** [что изменено в процессе/системе]
3. **Документация:** [какие документы обновлены]

## Связанные обновления

- [ ] Инструкции CLAUDE.md обновлены
- [ ] MEMORY.md обновлён
- [ ] Новые навыки созданы
- [ ] Тесты добавлены
- [ ] Чеклисты обновлены

## Уроки

[Ключевые выводы для предотвращения подобных ошибок в будущем]

---

*Создано с помощью навыка rca-5-whys*
