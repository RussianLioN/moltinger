---
marp: true
paginate: true
size: 16:9
title: "Защита концепции: {{agent_name}}"
description: "Defense presentation for concept {{concept_id}} version {{concept_version}}"
---

<!--
Source-first presentation template for Marp export.
Expected export targets: HTML, PDF, PPTX.
-->

# {{agent_name}}

## Защита концепции AI-агента

- `Concept ID`: `{{concept_id}}`
- `Версия`: `{{concept_version}}`
- `Инициатор`: {{owner}}
- `Запрос решения`: {{requested_decision}}

---

# Проблема

{{problem_statement}}

### Почему это важно сейчас

{{why_now}}

---

# Текущий процесс

{{current_process}}

### Потери текущего подхода

{{current_pain_points}}

---

# Предлагаемый агент

{{agent_summary}}

### Что автоматизируем

{{automation_scope}}

---

# Ценность и метрики

{{success_metrics}}

### Что считаем успехом MVP0

- concept pack согласован
- защита прошла или вернула структурированную доработку
- после approval фабрика способна дойти до playground package

---

# Контур фабрики

1. Telegram intake
2. Project doc + spec + presentation
3. Defense gate
4. Swarm: coder -> tester -> validator -> auditor -> assembler
5. Playground package

---

# Ограничения и риски

{{constraints}}

### Основные риски

{{open_risks}}

---

# Что не делаем в MVP0

- production deploy
- live business data в playground
- неограниченную автономию без approval gate

---

# Решение, которое нужно сейчас

{{requested_decision}}

### Следующий шаг

{{next_step_summary}}

