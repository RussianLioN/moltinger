---
artifact_type: agent_spec
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

# Спецификация агента: {{agent_name}}

## 1. Идентичность

- `Concept ID`: `{{concept_id}}`
- `Версия концепции`: `{{concept_version}}`
- `Ревизия спецификации`: `{{artifact_revision}}`
- `Целевой runtime`: {{target_runtime}}
- `Целевой канал`: Telegram / playground / internal swarm

## 2. Назначение

{{problem_statement}}

## 3. Пользователи и сценарий

### Основные пользователи

{{target_users}}

### Основной сценарий

{{primary_scenario}}

## 4. Capabilities

{{capabilities}}

## 5. Inputs / Outputs

### Inputs

{{inputs}}

### Outputs

{{outputs}}

## 6. Интеграции и зависимости

{{integrations}}

## 7. Ограничения

### Функциональные границы

{{functional_boundaries}}

### Нефункциональные требования

{{non_functional_requirements}}

### Исключения

{{exclusions}}

## 8. Acceptance Criteria

{{acceptance_criteria}}

## 9. Проверки качества

### Test expectations

{{test_expectations}}

### Validation expectations

{{validation_expectations}}

### Audit expectations

{{audit_expectations}}

## 10. Playground Scope

### Что должно демонстрироваться

{{playground_scope}}

### Какие данные разрешены

{{allowed_data_profile}}

## 11. Traceability

- Этот документ обязан совпадать по scope, metrics и constraints с `project_doc`
- Presentation обязана отражать только утверждения из этой версии spec
- Production swarm запускается только после `approved` для этой же версии

