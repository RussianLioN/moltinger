# Moltinger → AI Agent Factory: План трансформации

**Date**: 2026-02-17
**Status**: Ready for Approval
**Priority**: P0 - Стратегический pivot проекта
**MVP Goal**: Moltinger знает концепцию ASC и помогает создавать документацию агентов

---

## Context

### Проблема
Moltinger сейчас — это DevOps-ассистент для Docker deployment. Но реальная задача — **фабрика по производству AI агентов** на основе концепции ASC AI Fabrique.

### Решение
Научить Moltinger (Moltis на сервере ainetic.tech) работать как AI Agent Factory:
1. Знать концепцию ASC (7 метаблоков, 3 фазы, 62 термина)
2. Формировать спецификации агентов
3. Генеририровать презентации по агентам
4. Валидировать архитектуру по ASC принципам

### ⚠️ Важно: Навыки добавляются в MOLTIS, не в Claude Code!

---

## Архитектура Moltis для обучения

### Механизмы добавления знаний в Moltinger:

| Механизм | Файл/Директория | Назначение |
|----------|-----------------|------------|
| **Soul Prompt** | `config/moltis.toml` → `[identity]` | Основное поведение и роль |
| **Skills** | `~/.config/moltis/skills/` или `./skills/` | Reusable prompt templates |
| **Memory (RAG)** | `~/.moltis/memory/` + watch_dirs | База знаний для поиска |
| **MCP Servers** | `config/moltis.toml` → `[mcp]` | Инструменты |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    MOLTIS SERVER                         │
│              (ainetic.tech:13131)                        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │           SOUL PROMPT (Agent Factory)           │    │
│  │  config/moltis.toml → [identity]                │    │
│  └─────────────────────────────────────────────────┘    │
│                          │                               │
│         ┌────────────────┼────────────────┐             │
│         ▼                ▼                ▼             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │    SKILLS   │  │   MEMORY    │  │ MCP TOOLS   │     │
│  │  ./skills/  │  │ ~/.moltis/  │  │ filesystem  │     │
│  │             │  │   memory/   │  │ github      │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
│                                                          │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│              ASC AI Fabrique Knowledge                   │
│  (Глоссарий 62 термина, 7 метаблоков, 3 фазы)           │
└─────────────────────────────────────────────────────────┘
```

---

## Phase 1: Soul Prompt (Agent Factory Identity)

**Цель**: Moltinger понимает свою роль как AI Agent Factory
**Время**: 30 минут

### Task 1.1: Обновить Soul Prompt в Moltis

**Файл на сервере**: `/opt/moltinger/config/moltis.toml`
**Секция**: `[identity]` (строки ~49-72)

**Заменить текущий soul prompt на**:

```toml
[identity]
name = "Молтингер"
emoji = "🤖"
vibe = "technical"
soul = """
Ты - Молтингер, AI Agent Factory - фабрика по производству AI агентов.

## Контекст
- Пользователь: Сергей (timezone Europe/Moscow)
- Миссия: Создание AI агентов по методологии ASC AI Fabrique

## Экспертиза ASC
Ты знаешь концепцию ASC (Agentric Swarm Coding):
- 7 семенных метаблоков для разработки агентов
- 3 фазы развития: MVP0 → Масштабирование → Автономная работа
- Рекурсивная самоприменимость системы

## Роль
- Архитектор AI агентов
- Генератор спецификаций агентов
- Создатель презентаций по агентам
- Валидатор архитектуры по ASC принципам

## Workflow создания агента
1. Собрать требования (цель, метрики успеха, ограничения)
2. Сформировать спецификацию (spec.md)
3. Спроектировать архитектуру (architecture.md)
4. Сгенерировать презентацию (presentation.md)
5. Валидировать по чеклисту ASC

## Поведение
- Язык: русский
- Стиль: технически точно, структурировано
- Формат: [OK]/[WARN]/[ERR] для статусов
- При запросе создания агента: Всегда начинай с понимания требований
"""
```

### Task 1.2: Deploy на сервер

```bash
# Локально: обновить config/moltis.toml
git add config/moltis.toml
git commit -m "feat(moltis): transform to AI Agent Factory (soul prompt)"
git push origin main

# Автоматический deploy через GitHub Actions
# Или вручную:
ssh root@ainetic.tech "cd /opt/moltinger && docker compose restart moltis"
```

---

## Phase 2: Knowledge Base (Memory/RAG)

**Цель**: Moltinger имеет доступ к знаниям ASC
**Время**: 1-2 часа

### Task 2.1: Создать базу знаний ASC на сервере

**Директория на сервере**: `/opt/moltinger/knowledge/asc/`

```
/opt/moltinger/knowledge/asc/
├── GLOSSARY.md           # 62 термина ASC
├── METABLOCKS.md         # 7 семенных метаблоков (полное описание)
├── PHASES.md             # 3 фазы развития
├── AGENT_TEMPLATE.md     # Шаблон спецификации агента
└── PRESENTATION_TEMPLATE.md  # Шаблон презентации
```

**Источник для копирования**:
- `docs/asc-roadmap/GLOSSARY.md`
- `docs/asc-roadmap/meta_block_registry.md`
- `docs/asc-roadmap/strategic_roadmap.md`

**Примечание**: Локальное зеркало ASC-документации в этом репозитории теперь ведется через `docs/ASC-AI-FABRIQUE-MIRROR.md`, чтобы planning и runtime-артефакты не зависели от внешнего абсолютного пути на рабочей станции.

### Task 2.2: Настроить Memory watch_dirs

**Файл**: `config/moltis.toml`

```toml
[memory]
llm_reranking = false
session_export = false
provider = "ollama"
model = "nomic-embed-text"
base_url = "http://localhost:11434/v1"

# Добавить директорию с знаниями ASC для RAG
watch_dirs = [
  "~/.moltis/memory",
  "/opt/moltinger/knowledge/asc",    # ← Добавить
]
```

### Task 2.3: Альтернатива - Filesystem MCP

Если Memory/RAG сложно настроить, использовать MCP filesystem:

```toml
[mcp.servers.asc-knowledge]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/opt/moltinger/knowledge/asc"]
enabled = true
```

---

## Phase 3: Skills для Moltis

**Цель**: Moltinger имеет специализированные skills для работы с агентами
**Время**: 2-3 часа

### Task 3.1: Создать skill "agent-spec-generator"

**Директория на сервере**: `/opt/moltinger/skills/agent-spec-generator/SKILL.md`

```markdown
---
name: agent-spec-generator
description: Генерирует спецификацию AI агента по методологии ASC
---

# Agent Spec Generator

## Активация
Используй этот skill когда пользователь просит создать нового агента.

## Workflow

1. **Сбор требований**
   Спроси пользователя:
   - Какую задачу будет решать агент?
   - Кто пользователи агента?
   - Как измерить успех?

2. **Маппинг на метаблоки**
   Определи какие из 7 метаблоков ASC применимы:
   - RESEARCH_FRAMEWORK_PATTERN
   - ARCHITECTURE_PATTERN
   - DEVELOPMENT_PATTERN
   - TESTING_PATTERN
   - ENVIRONMENT_SETUP_PATTERN
   - POC_DEFENSE_PATTERN
   - AGENT_DEVELOPMENT_PATTERN

3. **Генерация спецификации**
   Создай документ по шаблону:

## Шаблон спецификации

```markdown
# Agent Specification: [NAME]

## Overview
- **Name**: [название]
- **Version**: 0.1.0
- **Purpose**: [цель]
- **Owner**: Сергей

## Goals & Success Metrics
| Metric | Target | Measurement |
|--------|--------|-------------|
| [метрика] | [цель] | [как измерить] |

## Metablock Mapping
| Metablock | Usage | Priority |
|-----------|-------|----------|
| [блок] | [как используется] | P1/P2/P3 |

## Capabilities
- [возможность 1]
- [возможность 2]

## Inputs & Outputs
### Inputs
- [входные данные]

### Outputs
- [выходные данные]

## Implementation Phases
### Phase 1 (MVP0 - 4 недели)
- [ ] [задача]

### Phase 2 (Scaling - 3-6 месяцев)
- [ ] [задача]

### Phase 3 (Autonomous)
- [ ] [задача]
```
```

### Task 3.2: Создать skill "agent-presentation-generator"

**Директория на сервере**: `/opt/moltinger/skills/agent-presentation-generator/SKILL.md`

```markdown
---
name: agent-presentation-generator
description: Генерирует презентацию по агенту в формате Marp/Markdown
---

# Agent Presentation Generator

## Активация
Используй этот skill когда пользователь просит создать презентацию по агенту.

## Workflow

1. Прочитай спецификацию агента
2. Извлеки ключевую информацию
3. Сгенерируй slides в формате Marp

## Шаблон презентации (Marp)

```markdown
---
marp: true
theme: default
paginate: true
---

# [Agent Name]
## AI Agent for [Purpose]

**Moltinger AI Agent Factory**

---

## Problem Statement

- Проблема 1
- Проблема 2
- Текущие ограничения

---

## Solution

**[Agent Name]** - [one-line description]

Ключевые возможности:
- Возможность 1
- Возможность 2
- Возможность 3

---

## Architecture Overview

```
[Диаграмма архитектуры]
```

---

## Metablocks Used

| Block | Purpose |
|-------|---------|
| RESEARCH_FRAMEWORK | Исследование |
| ARCHITECTURE | Проектирование |
| DEVELOPMENT | Реализация |

---

## Success Metrics

| Metric | Target | Status |
|--------|--------|--------|
| [метрика] | [цель] | 🔄 |

---

## Roadmap

- **Week 1-4**: MVP0
- **Month 2-6**: Scaling
- **Month 7+**: Autonomous

---

## Investment Required

- **Timeline**: X недель
- **Resources**: [команда]
- **Dependencies**: [зависимости]

---

## Next Steps

1. [Действие 1]
2. [Действие 2]
3. [Действие 3]

---

# Questions?

**Contact**: Сергей
**Project**: ASC AI Fabrique
```
```

### Task 3.3: Настроить search_paths для skills

**Файл**: `config/moltis.toml`

```toml
[skills]
enabled = true
search_paths = ["/opt/moltinger/skills"]    # ← Добавить
auto_load = ["agent-spec-generator", "agent-presentation-generator"]
```

---

## Phase 4: Verification

**Цель**: Убедиться что Moltinger работает как Agent Factory
**Время**: 30 минут

### Test Scenarios

| # | Запрос к Moltinger | Ожидаемый результат |
|---|-------------------|---------------------|
| 1 | "Привет, представься" | "Я - Молтингер, AI Agent Factory..." |
| 2 | "Что такое метаблок?" | Объяснение концепции из знаний ASC |
| 3 | "Создай агента для X" | Спецификация по шаблону ASC |
| 4 | "Сгенерируй презентацию для агента Y" | Marp slides |

### Verification Checklist

```
[ ] Soul prompt обновлён (Agent Factory identity)
[ ] Knowledge base создана (/opt/moltinger/knowledge/asc/)
[ ] Memory watch_dirs настроен ИЛИ filesystem MCP
[ ] Skills созданы (/opt/moltinger/skills/)
[ ] search_paths в moltis.toml указывает на skills
[ ] Moltis перезапущен (docker compose restart)
[ ] Тест 1: "Представься" → Agent Factory identity
[ ] Тест 2: "Что такое ASC?" → знает концепцию
[ ] Тест 3: "Создай агента" → генерирует spec
```

---

## Files to Create/Modify

### На сервере (ainetic.tech)

| Файл | Действие | Приоритет |
|------|----------|-----------|
| `/opt/moltinger/config/moltis.toml` | Обновить soul prompt | P0 |
| `/opt/moltinger/config/moltis.toml` | Добавить skills.search_paths | P0 |
| `/opt/moltinger/config/moltis.toml` | Добавить memory.watch_dirs | P1 |
| `/opt/moltinger/knowledge/asc/GLOSSARY.md` | Создать (из ASC проекта) | P0 |
| `/opt/moltinger/knowledge/asc/METABLOCKS.md` | Создать | P0 |
| `/opt/moltinger/skills/agent-spec-generator/SKILL.md` | Создать | P1 |
| `/opt/moltinger/skills/agent-presentation-generator/SKILL.md` | Создать | P1 |

### В репозитории (для GitOps deploy)

| Файл | Действие |
|------|----------|
| `config/moltis.toml` | Обновить soul + skills config |
| `knowledge/asc/GLOSSARY.md` | Создать |
| `knowledge/asc/METABLOCKS.md` | Создать |
| `skills/agent-spec-generator/SKILL.md` | Создать |
| `skills/agent-presentation-generator/SKILL.md` | Создать |

---

## Execution Order

```
Phase 1 (30 мин)
├── 1.1 Обновить soul prompt в config/moltis.toml
├── 1.2 Git commit + push (триггер deploy)
└── 1.3 Verify: https://moltis.ainetic.tech "Представься"
        │
        ▼
Phase 2 (1-2 часа)
├── 2.1 Создать knowledge/asc/ директорию
├── 2.2 Скопировать GLOSSARY.md из ASC проекта
├── 2.3 Скопировать METABLOCKS.md из ASC проекта
├── 2.4 Настроить memory.watch_dirs ИЛИ filesystem MCP
└── 2.5 Deploy + Verify: "Что такое метаблок?"
        │
        ▼
Phase 3 (2-3 часа)
├── 3.1 Создать skills/agent-spec-generator/
├── 3.2 Создать skills/agent-presentation-generator/
├── 3.3 Настроить skills.search_paths
└── 3.4 Deploy + Verify: "Создай агента для X"
        │
        ▼
Phase 4 (30 мин)
└── Full verification + документация
```

---

## MVP Prioritization

### Must Have (Phase 1-2)
- [x] Soul prompt → Agent Factory identity
- [ ] Knowledge base: GLOSSARY + METABLOCKS
- [ ] Memory или filesystem доступ к знаниям

### Should Have (Phase 3)
- [ ] agent-spec-generator skill
- [ ] agent-presentation-generator skill

### Nice to Have (Future)
- MCP GitHub для работы с репозиториями
- Automation slash commands
- Memory entities для ASC

---

## Risks & Mitigation

| Риск | Митигация |
|------|-----------|
| Memory/RAG требует Ollama | Использовать filesystem MCP как fallback |
| GLM-5 не справится с генерацией | Использовать более мощную модель для критичных задач |
| Skills не загружаются | Проверить search_paths и права доступа |
| Знания устаревают | Хранить в Git, обновлять через CI/CD |

---

## Success Criteria

| Критерий | Как проверить |
|----------|---------------|
| Moltinger знает ASC | Запрос: "Что такое метаблок?" → корректный ответ |
| Генерирует спецификации | Запрос: "Создай агента для X" → spec.md |
| Генерирует презентации | Запрос: "Презентация для агента Y" → Marp slides |
| Понимает свою роль | Запрос: "Представься" → "AI Agent Factory" |

---

## Связанные артефакты

| Артефакт | Назначение |
|----------|------------|
| [agent-factory-lifecycle.md](./agent-factory-lifecycle.md) | **Полный lifecycle создания агента** - от спецификации до передачи в продакшен, включая независимую валидацию, UAT, Docker пакетирование |

---

## Summary

**Что делаем**: Учит Moltinger (Moltis) работать как AI Agent Factory

**Как (механизмы Moltis)**:
1. **Soul Prompt** → определяет роль и поведение
2. **Knowledge Base** →Memory/watch_dirs или filesystem MCP
3. **Skills** → reusable templates для spec и presentation
4. **Deploy** → через GitOps (push → GitHub Actions → server)

**MVP (Phase 1-2, ~2 часа)**:
- Soul prompt обновлён
- Knowledge base (GLOSSARY + METABLOCKS) доступна
- Moltinger отвечает на вопросы по ASC

**Результат**: Moltinger — AI Agent Factory, готовый помогать в создании агентов

---

## Полный Lifecycle создания агента

```
Phase 1: Требования (Spec)        → spec.md
    ↓
Phase 2: Архитектура (Design)     → architecture.md
    ↓
Phase 3: Создание (Code)          → src/, config/
    ↓
Phase 3.5: НЕЗАВИСИМАЯ ВАЛИДАЦИЯ  → validation-report.md (Agent-Validator)
    ↓ [PASS]
Phase 4: Тестирование + UAT       → uat-report.md (Business Users)
    ↓ [UAT PASS]
Phase 5: Docker Пакетирование      → Dockerfile, docker-compose.yml
    ↓
Phase 6: Передача команде          → Full package
```

**Детали в**: [agent-factory-lifecycle.md](./agent-factory-lifecycle.md)
