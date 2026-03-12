---
artifact_type: requirements_brief
source_format: markdown
download_formats:
  - md
  - pdf
project_key: "{{project_key}}"
brief_id: "{{brief_id}}"
brief_version: "{{brief_version}}"
brief_status: "{{brief_status}}"
language: "{{working_language}}"
owner: "{{owner}}"
---

# Требования к будущему AI-агенту: {{agent_name}}

## 1. Паспорт brief

- `Project Key`: `{{project_key}}`
- `Brief ID`: `{{brief_id}}`
- `Версия brief`: `{{brief_version}}`
- `Статус`: `{{brief_status}}`
- `Инициатор`: {{owner}}
- `Discovery session`: `{{discovery_session_id}}`

## 2. Бизнес-проблема

{{problem_statement}}

## 3. Для кого и в каком процессе

### Целевые пользователи

{{target_users}}

### Как процесс работает сейчас

{{current_process}}

### Какой результат нужен

{{desired_outcome}}

## 4. Scope и пользовательская история

### Scope boundaries

{{scope_boundaries}}

### User story

{{user_story}}

## 5. Примеры и ожидаемый результат

### Input examples

{{input_examples}}

### Expected outputs

{{expected_outputs}}

## 6. Бизнес-правила и исключения

### Business rules

{{business_rules}}

### Exception cases

{{exception_cases}}

## 7. Ограничения и метрики успеха

### Constraints

{{constraints}}

### Success metrics

{{success_metrics}}

## 8. Открытые риски и вопросы

### Open risks

{{open_risks}}

### Unresolved questions

{{unresolved_questions}}

## 9. Confirmation Gate

{{confirmation_guidance}}

## 10. Next Step

{{next_recommended_action}}

## 11. Sync Checklist

- [ ] Problem statement отражает реальную бизнес-боль
- [ ] User story сформулирована бизнес-языком
- [ ] Есть хотя бы один representative input/output example pair
- [ ] Ограничения и метрики успеха сформулированы явно
- [ ] Brief готов к confirmation перед downstream handoff
