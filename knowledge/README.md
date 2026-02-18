# Knowledge Base

Структурированная база знаний для самообучения Moltinger.

## Структура

```
knowledge/
├── concepts/        # Концепции и определения
├── tutorials/       # Пошаговые руководства
├── references/      # Справочная информация
├── troubleshooting/ # Решения проблем
└── patterns/        # Паттерны использования
```

## Формат файлов

Каждый файл должен иметь frontmatter:

```yaml
---
title: "Topic Title"
category: "concept|tutorial|reference|troubleshooting|pattern"
tags: ["tag1", "tag2"]
source: "@tsingular|URL|original"
date: "YYYY-MM-DD"
confidence: "high|medium|low"
---

# Topic Title

## Summary
[2-3 sentences]

## Key Concepts
- **Concept**: Definition

## Details
[Content]
```

## Источники

- **@tsingular** - Telegram канал с новостями OpenClaw
- **Документация** - Официальная документация Moltis
- **Community** - Best practices из сообщества

## Связанные файлы

- `docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md` - Инструкция для самообучения
- `skills/telegram-learner/SKILL.md` - Skill для мониторинга Telegram

---

*Created: 2026-02-18*
