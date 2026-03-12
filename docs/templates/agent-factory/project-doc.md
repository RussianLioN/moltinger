---
artifact_type: project_doc
source_format: markdown
download_formats:
  - md
  - pdf
concept_id: "{{concept_id}}"
concept_version: "{{concept_version}}"
artifact_revision: "{{artifact_revision}}"
language: ru
owner: "{{owner}}"
---

# Проектный документ: {{agent_name}}

## 1. Паспорт концепции

- `Concept ID`: `{{concept_id}}`
- `Версия`: `{{concept_version}}`
- `Ревизия артефакта`: `{{artifact_revision}}`
- `Инициатор`: {{owner}}
- `Статус решения`: {{decision_state}}

## 2. Проблема и контекст

### Бизнес-проблема

{{problem_statement}}

### Для кого делаем

{{target_users}}

### Как процесс работает сейчас

{{current_process}}

## 3. Что делает будущий агент

### Целевой результат

{{desired_outcome}}

### Границы MVP0

- Telegram intake идеи
- Синхронный concept pack из трех артефактов
- Defense gate до запуска производства
- Playground package на синтетических или тестовых данных
- Без production deploy в рамках MVP0

### Что не входит в этот этап

{{non_goals}}

## 4. Метрики успеха

{{success_metrics}}

## 5. Ограничения и зависимости

### Ограничения

{{constraints}}

### Внешние зависимости

{{external_dependencies}}

## 6. Риски и допущения

### Допущения

{{assumptions}}

### Открытые риски

{{open_risks}}

## 7. Примененные фабричные паттерны

{{applied_factory_patterns}}

## 8. Артефакты concept pack

- `project_doc`: этот документ
- `agent_spec`: техническая спецификация будущего агента
- `presentation`: защита концепции для согласования

## 9. Запрос на решение

### Что нужно от защиты

{{requested_decision}}

### Следующий шаг после решения

{{next_step_summary}}

## 10. Sync Checklist

- [ ] Scope совпадает с `agent_spec`
- [ ] Метрики совпадают с `agent_spec`
- [ ] Риски и допущения отражены в презентации
- [ ] Решение на защите сформулировано явно

