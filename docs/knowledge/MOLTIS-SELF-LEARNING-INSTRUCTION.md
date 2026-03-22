# ИНСТРУКЦИЯ ДЛЯ LLM: Самообучение OpenClaw/Moltis

**Версия**: 1.0.0
**Дата**: 2026-02-18
**Назначение**: Исчерпывающее руководство для обучения LLM-агента работе с Moltis и его самообучению

> Для проектного skill/agent authoring и миграции capability из Claude Code, Codex или OpenCode сначала смотри канонический гайд:
> [docs/moltis-skill-agent-authoring.md](/Users/rl/coding/moltinger-molt-2-codex-update-monitor-new/docs/moltis-skill-agent-authoring.md)

---

## META: Как читать этот документ

```
┌─────────────────────────────────────────────────────────────┐
│  СТРУКТУРА ДОКУМЕНТА ДЛЯ LLM                                │
├─────────────────────────────────────────────────────────────┤
│  1. Executive Summary → Быстрое понимание (1 мин)           │
│  2. Core Concepts → Фундаментальные знания (5 мин)          │
│  3. Workflows → Пошаговые инструкции (10 мин)               │
│  4. Examples → Конкретные примеры (5 мин)                   │
│  5. Templates → Готовые шаблоны для копирования             │
│  6. Troubleshooting → Решение проблем                       │
│  7. Quick Reference → Шпаргалка                             │
└─────────────────────────────────────────────────────────────┘
```

**ВАЖНО**: Этот документ содержит ВСЁ необходимое для автономной работы. Читай его полностью перед началом.

---

## 1. Executive Summary

### 1.1 Что такое Moltis

**Moltis** (OpenClaw Gateway) — платформа для AI-агентов с 4 механизмами расширения:

| Механизм | Файл | Назначение | Когда использовать |
|----------|------|------------|-------------------|
| **Soul Prompt** | `moltis.toml → [identity]` | Идентичность, поведение, роль | Изменение личности агента |
| **Skills** | `~/.config/moltis/skills/*/SKILL.md` | Переиспользуемые шаблоны промптов | Новые возможности, паттерны |
| **Memory/RAG** | `~/.moltis/memory/` + watch_dirs | База знаний с семантическим поиском | Факты, документация, ссылки |
| **MCP Servers** | `moltis.toml → [mcp.servers]` | Внешние инструменты и интеграции | API, базы данных, Telegram |

### 1.2 Цель самообучения

```
СОСТОЯНИЕ СЕЙЧАС          →        ЦЕЛЕВОЕ СОСТОЯНИЕ
┌──────────────────┐              ┌──────────────────────────┐
│ Moltis работает  │              │ Moltis САМ:              │
│ как настроенный  │     →        │ • Извлекает знания       │
│ ассистент        │              │ • Создаёт skills         │
│                  │              │ • Обновляет memory       │
│                  │              │ • Мониторит Telegram     │
└──────────────────┘              └──────────────────────────┘
```

### 1.3 Первая задача: Telegram мониторинг

**Канал**: @tsingular — новости OpenClaw и работа с ним
**Цель**: Автоматически извлекать полезную информацию и создавать навыки

---

## 2. Core Concepts

### 2.1 Архитектура Moltis

```
┌─────────────────────────────────────────────────────────────┐
│                     MOLTIS CORE                             │
│                  (OpenClaw Gateway)                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              SOUL PROMPT (Identity)                   │  │
│  │         config/moltis.toml → [identity]              │  │
│  │                                                       │  │
│  │  Определяет:                                          │  │
│  │  • Имя и роль агента                                  │  │
│  │  • Основное поведение                                 │  │
│  │  • Приоритеты и ценности                              │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                  │
│         ┌─────────────────┼─────────────────┐               │
│         ▼                 ▼                 ▼               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   SKILLS    │  │   MEMORY    │  │  MCP TOOLS  │         │
│  │             │  │             │  │             │         │
│  │ Шаблоны     │  │ База знаний │  │ Инструменты │         │
│  │ промптов    │  │ с RAG       │  │ извне       │         │
│  │             │  │             │  │             │         │
│  │ ~/.config/  │  │ ~/.moltis/  │  │ External    │         │
│  │ moltis/     │  │ memory/     │  │ Servers     │         │
│  │ skills/     │  │             │  │             │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    LLM PROVIDERS                            │
│  (OpenAI, Anthropic, Ollama, Groq, xAI, Deepseek, GLM)     │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Paths & Locations

**Важные пути (Docker deployment)**:

```
/server                    # Рабочая директория контейнера
├── config/
│   └── moltis.toml        # ГЛАВНЫЙ конфиг
├── skills/                # Skills (если используется локальный путь)
└── knowledge/             # База знаний (кастомная)

/home/moltis/
├── .config/moltis/
│   ├── moltis.toml        # Конфиг по умолчанию
│   └── skills/            # Skills по умолчанию
└── .moltis/
    └── memory/            # Memory по умолчанию
```

**Для GitOps деплоя** (репозиторий moltinger):
```
/Users/rl/coding/moltinger/
├── config/
│   └── moltis.toml        # Конфиг для деплоя
├── skills/                # Skills для деплоя
└── knowledge/             # Knowledge base для деплоя
```

### 2.3 Конфигурация moltis.toml

#### Server Settings
```toml
[server]
bind = "0.0.0.0"              # Docker: ОБЯЗАТЕЛЬНО 0.0.0.0
port = 13131                  # Порт gateway
http_request_logs = false
ws_request_logs = false
```

#### Identity (Soul Prompt)
```toml
[identity]
name = "Молтингер"
emoji = "🤖"
vibe = "technical"
soul = """
Ты - Молтингер, [РОЛЬ И ПОВЕДЕНИЕ]

## Твой контекст
[ИНФОРМАЦИЯ О СРЕДЕ И ПОЛЬЗОВАТЕЛЕ]

## Твои способности
[СПИСОК ВОЗМОЖНОСТЕЙ]

## Твоё поведение
[ПРАВИЛА ВЗАИМОДЕЙСТВИЯ]
"""
```

#### Skills Configuration
```toml
[skills]
enabled = true
search_paths = [
  "/server/skills",           # Кастомный путь
  "~/.config/moltis/skills"   # По умолчанию
]
auto_load = ["skill-name-1", "skill-name-2"]  # Всегда активные skills
```

#### Memory Configuration
```toml
[memory]
llm_reranking = false
session_export = false
provider = "ollama"           # "local", "ollama", "openai", "custom"
model = "nomic-embed-text"    # Модель для embeddings
base_url = "http://localhost:11434/v1"

# Watch directories для RAG
watch_dirs = [
  "~/.moltis/memory",
  "/server/knowledge",
]
```

#### MCP Servers
```toml
[mcp.servers.server-name]
command = "npx"
args = ["-y", "@package/name"]
env = { API_KEY = "${ENV_VAR}" }
enabled = true
transport = "stdio"           # или "sse"
```

#### Telegram Integration
```toml
[channels.telegram]
enabled = true

[channels.telegram.moltis-bot]
token = "${TELEGRAM_BOT_TOKEN}"
dm_policy = "allowlist"
allowlist = ["262872984"]  # Tracked runtime source of truth; .env mirror is for auxiliary scripts only
```

### 2.4 Формат SKILL.md

**Обязательная структура**:

```markdown
---
name: skill-name
description: Что делает skill. Использовать когда [конкретный сценарий].
---

# Skill Name

## Активация
Когда пользователь просит [сценарий], используй этот skill.

## Workflow

1. **Шаг 1**
   - Действие
   - Критерии

2. **Шаг 2**
   - Действие

## Templates

### Template 1: [Название]
```markdown
[Шаблон документа]
```

## Examples

### Example 1: [Сценарий]
Input: ...
Output: ...

## Best Practices
- Правило 1
- Правило 2

## Common Pitfalls
- ❌ Ошибка → ✅ Правильный подход
```

**Ключевые правила**:
1. `name` в frontmatter = название директории skill
2. `description` используется для автоматической активации
3. Skill добавляется в контекст LLM при активации
4. Используй конкретные примеры (few-shot learning)

### 2.5 Memory Files Format

**Структура memory файла**:

```markdown
---
title: "Topic Name"
category: "concept|tutorial|reference|troubleshooting"
tags: ["tag1", "tag2", "tag3"]
source: "@tsingular|URL|original"
date: "2026-02-18"
confidence: "high|medium|low"
---

# Topic Name

## Summary
[2-3 предложения - что это и зачем нужно]

## Key Concepts
- **Concept 1**: Определение
- **Concept 2**: Определение

## Details
[Подробное описание]

## Examples
[Конкретные примеры]

## Related
- [[Related Topic 1]]
- [[Related Topic 2]]

## References
- [Source](URL)
```

**Ключевые правила**:
1. Frontmatter с метаданными обязателен
2. Summary = первые 2-3 предложения для быстрого поиска
3. Используй wiki-links `[[Topic]]` для связей
4. Confidence показывает надёжность информации

---

## 3. Workflows

### 3.1 Workflow: Создание нового Skill

**Триггер**: Появилась повторяющаяся задача или паттерн работы

```
STEP 1: Определить потребность
        │
        ▼
STEP 2: Создать директорию skills/skill-name/
        │
        ▼
STEP 3: Написать SKILL.md по шаблону
        │
        ▼
STEP 4: Добавить в search_paths или auto_load
        │
        ▼
STEP 5: Перезапустить Moltis (или ждать auto-reload)
        │
        ▼
STEP 6: Протестировать активацию
```

**Детальные шаги**:

#### Step 1: Определить потребность
```
Вопросы для анализа:
1. Это повторяющаяся задача? → Да → Skill candidate
2. Нужен шаблон документа? → Да → Skill candidate
3. Это сложный multi-step процесс? → Да → Skill candidate
4. Это просто факт/информация? → Да → Memory candidate
```

#### Step 2: Создать директорию
```bash
mkdir -p /server/skills/my-skill/
# или
mkdir -p ~/.config/moltis/skills/my-skill/
```

#### Step 3: Написать SKILL.md
```bash
cat > /server/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: [Описание]. Использовать когда [сценарий].
---

# My Skill

## Активация
[Когда активировать]

## Workflow
[Пошаговый процесс]

## Templates
[Шаблоны]
EOF
```

#### Step 4: Настроить конфигурацию
```toml
[skills]
search_paths = ["/server/skills"]

# Для always-on skills:
auto_load = ["my-skill"]
```

#### Step 5: Перезапуск
```bash
# Docker
docker compose restart moltis

# Или проверить auto-reload (если включён)
```

#### Step 6: Тестирование
```
Запрос к Moltis: "Используй skill my-skill для [задача]"
Ожидаемый результат: Skill активирован, workflow выполнен
```

### 3.2 Workflow: Добавление знаний в Memory

**Триггер**: Получена новая информация для сохранения

```
STEP 1: Определить тип информации
        │
        ├── Concept/Fact → knowledge/concepts/
        ├── Tutorial → knowledge/tutorials/
        ├── Reference → knowledge/references/
        └── Troubleshooting → knowledge/troubleshooting/
        │
        ▼
STEP 2: Создать markdown файл с frontmatter
        │
        ▼
STEP 3: Заполнить по шаблону
        │
        ▼
STEP 4: Добавить связи с существующими знаниями
        │
        ▼
STEP 5: (Опционально) Триггерить переиндексацию
```

**Пример создания knowledge файла**:

```bash
cat > /server/knowledge/concepts/mcp-servers.md << 'EOF'
---
title: "MCP Servers"
category: "concept"
tags: ["mcp", "integration", "tools"]
source: "original"
date: "2026-02-18"
confidence: "high"
---

# MCP Servers

## Summary
MCP (Model Context Protocol) Servers — внешние инструменты,
подключаемые к Moltis для расширения возможностей агента.

## Key Concepts
- **MCP Protocol**: Стандарт для подключения инструментов к LLM
- **Transport**: stdio или SSE для коммуникации
- **Tools**: Функции, вызываемые агентом

## Configuration
```toml
[mcp.servers.example]
command = "npx"
args = ["-y", "@package/name"]
enabled = true
```

## Related
- [[Moltis Architecture]]
- [[Skills System]]
EOF
```

### 3.3 Workflow: Мониторинг Telegram канала @tsingular

**Триггер**: Периодическая задача или входящее сообщение

```
STEP 1: Подключиться к Telegram
        │
        ├── Option A: Bot API (если bot admin канала)
        ├── Option B: Userbot (Telethon/Pyrogram)
        └── Option C: Web scraping (если публичный)
        │
        ▼
STEP 2: Получить новые сообщения
        │
        ▼
STEP 3: Отфильтровать релевантные
        │
        ▼
STEP 4: Извлечь ключевые концепции
        │
        ▼
STEP 5: Создать knowledge файл или skill
        │
        ▼
STEP 6: Сохранить в knowledge base
```

**ВАЖНО: Ограничения Telegram Bot API**:
- Bot может читать только каналы где он является administrator
- Для публичных каналов нужен userbot или другие методы

**Решение для @tsingular**:

#### Option A: Стать admin канала (рекомендуется)
1. Связаться с владельцем @tsingular
2. Добавить bot как admin
3. Использовать Bot API

#### Option B: Userbot (Telethon)
```python
# Отдельный скрипт, не MCP
from telethon import TelegramClient

api_id = os.getenv('TELEGRAM_API_ID')
api_hash = os.getenv('TELEGRAM_API_HASH')

client = TelegramClient('session', api_id, api_hash)

async def get_channel_posts(channel_name, limit=10):
    async for message in client.iter_messages(channel_name, limit=limit):
        # Обработать сообщение
        yield message.text
```

#### Option C: Web interface (если доступен)
Некоторые каналы имеют web версию: https://t.me/s/tsingular

### 3.4 Workflow: Self-Learning Cycle

**Полный цикл самообучения**:

```
┌─────────────────────────────────────────────────────────────┐
│                  SELF-LEARNING CYCLE                        │
└─────────────────────────────────────────────────────────────┘
                          │
         ┌────────────────┼────────────────┐
         ▼                ▼                ▼
   ┌───────────┐   ┌───────────┐   ┌───────────┐
   │  INPUT    │   │ PROCESS   │   │  OUTPUT   │
   │           │   │           │   │           │
   │ Telegram  │   │ Analyse   │   │ New Skill │
   │ Docs      │──►│ Extract   │──►│ Memory    │
   │ User FB   │   │ Validate  │   │ Config    │
   │ Forums    │   │ Structure │   │ Update    │
   └───────────┘   └───────────┘   └───────────┘
         │                               │
         └───────────────────────────────┘
                    (Feedback Loop)
```

**Ежедневный цикл**:
1. Проверить новые сообщения в @tsingular
2. Извлечь релевантные концепции
3. Создать/обновить knowledge файлы
4. При обнаружении паттерна → создать skill
5. Валидировать через тестовые запросы

---

## 4. Examples

### 4.1 Example: Skill для генерации спецификаций агентов

**Файл**: `skills/agent-spec-generator/SKILL.md`

```markdown
---
name: agent-spec-generator
description: Генерирует спецификацию AI агента по методологии ASC.
  Использовать когда пользователь просит создать нового агента.
---

# Agent Spec Generator

## Активация
Когда пользователь говорит:
- "Создай агента для [задача]"
- "Мне нужен агент который [функция]"
- "Спроектируй AI агента для [домен]"

## Workflow

### Phase 1: Сбор требований

Задай пользователю вопросы:
1. **Цель агента**: Какую задачу будет решать?
2. **Пользователи**: Кто будет использовать агента?
3. **Метрики успеха**: Как измерить эффективность?
4. **Ограничения**: Время, ресурсы, compliance?

### Phase 2: Маппинг на метаблоки ASC

Определи какие из 7 метаблоков применимы:

| Metablock | Когда использовать |
|-----------|-------------------|
| RESEARCH_FRAMEWORK_PATTERN | Нужно исследование |
| ARCHITECTURE_PATTERN | Нужна архитектура |
| DEVELOPMENT_PATTERN | Нужна разработка |
| TESTING_PATTERN | Нужно тестирование |
| ENVIRONMENT_SETUP_PATTERN | Нужна настройка среды |
| POC_DEFENSE_PATTERN | Нужна защита/презентация |
| AGENT_DEVELOPMENT_PATTERN | Полный цикл разработки |

### Phase 3: Генерация спецификации

Создай документ по шаблону:

## Template: Agent Specification

```markdown
# Agent Specification: [NAME]

## Overview
- **Name**: [название]
- **Version**: 0.1.0
- **Purpose**: [цель в одном предложении]
- **Owner**: [владелец]
- **Created**: [дата]

## Business Context
- **Problem**: [описание проблемы]
- **Users**: [целевые пользователи]
- **Process**: [бизнес-процесс]

## Goals & Success Metrics
| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| [метрика 1] | [цель] | [как измерить] |
| [метрика 2] | [цель] | [как измерить] |

## Metablock Mapping
| Metablock | Usage | Priority |
|-----------|-------|----------|
| [блок] | [как используется] | P1/P2/P3 |

## Capabilities
- **Capability 1**: [описание]
- **Capability 2**: [описание]

## Inputs & Outputs

### Inputs
| Input | Type | Format | Source |
|-------|------|--------|--------|
| [вход] | [тип] | [формат] | [источник] |

### Outputs
| Output | Type | Format | Destination |
|--------|------|--------|-------------|
| [выход] | [тип] | [формат] | [назначение] |

## Constraints
- **Technical**: [ограничения]
- **Business**: [ограничения]
- **Compliance**: [требования]

## Implementation Phases

### Phase 1 (MVP0 - 4 недели)
- [ ] [задача 1]
- [ ] [задача 2]

### Phase 2 (Scaling - 3-6 месяцев)
- [ ] [задача]

### Phase 3 (Autonomous)
- [ ] [задача]
```

## Example Output

**Input**: "Создай агента для автоматизации отчётов по продажам"

**Output**:
```markdown
# Agent Specification: Sales Report Automator

## Overview
- **Name**: Sales Report Automator
- **Version**: 0.1.0
- **Purpose**: Автоматизация сбора и генерации отчётов по продажам
- **Owner**: Сергей
- **Created**: 2026-02-18

## Business Context
- **Problem**: Ручной сбор данных из CRM, Excel, Telegram занимает 4+ часа в неделю
- **Users**: Менеджеры по продажам, руководители
- **Process**: Еженедельная отчётность по продажам

## Goals & Success Metrics
| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Time saved | 4 hrs/week | Time tracking |
| Report accuracy | 99% | Error count |

## Metablock Mapping
| Metablock | Usage | Priority |
|-----------|-------|----------|
| RESEARCH_FRAMEWORK | Анализ источников данных | P1 |
| DEVELOPMENT | Реализация парсеров | P1 |
| TESTING | Валидация данных | P2 |

## Capabilities
- **Data Collection**: Сбор данных из CRM, Excel, Telegram
- **Report Generation**: Создание отчётов в заданном формате
- **Distribution**: Отправка отчётов по расписанию
```
```

### 4.2 Example: Skill для мониторинга Telegram

**Файл**: `skills/telegram-learner/SKILL.md`

```markdown
---
name: telegram-learner
description: Мониторит Telegram канал @tsingular и извлекает знания для обучения.
  Использовать для периодического обновления базы знаний.
---

# Telegram Learner

## Активация
- По расписанию (heartbeat)
- По команде "обнови знания из Telegram"
- При появлении нового важного контента

## Prerequisites
- TELEGRAM_API_ID и TELEGRAM_API_HASH в env
- Или bot token с admin правами на канале

## Workflow

### Step 1: Получить новые сообщения

Если используется userbot (Telethon):
```python
from telethon import TelegramClient

async def fetch_new_posts(channel, last_id, limit=50):
    async for msg in client.iter_messages(
        channel,
        min_id=last_id,
        limit=limit
    ):
        yield msg
```

### Step 2: Отфильтровать релевантные

Критерии релевантности:
- Содержит техническую информацию
- Описывает новую функцию или паттерн
- Объясняет решение проблемы
- Содержит tutorial или how-to

### Step 3: Извлечь концепции

Для каждого релевантного сообщения:
1. Определить главную тему
2. Извлечь ключевые термины
3. Найти практические советы
4. Зафиксировать примеры кода

### Step 4: Создать knowledge файл

```markdown
---
title: "[Topic from Message]"
category: "tutorial|concept|reference"
tags: ["openclaw", "moltis", ...]
source: "@tsingular"
date: "[message date]"
confidence: "high"
original_url: "https://t.me/tsingular/[msg_id]"
---

# [Topic]

## Summary
[2-3 sentences from message]

## Key Points
- [Point 1]
- [Point 2]

## Code Examples
```[language]
[code from message]
```

## Discussion Summary
[Key points from comments if available]
```

### Step 5: Сохранить и проиндексировать

```bash
# Сохранить файл
filename="knowledge/tutorials/$(echo $topic | tr ' ' '-' | tr '[:upper:]' '[:lower:]').md"
echo "$content" > "$filename"

# Если watch_dirs настроен, индексация автоматическая
# Иначе триггернуть вручную
```

## Output Format

После выполнения:
```
Telegram Learning Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━
Posts analyzed: [N]
Relevant found: [M]
New knowledge files: [K]
Skills created: [S]

Files created:
- knowledge/tutorials/topic-1.md
- knowledge/concepts/topic-2.md
```
```

### 4.3 Example: Knowledge File из Telegram поста

**Исходный пост** (гипотетический из @tsingular):
```
🚀 Новая фича в Moltis: автоматическая перезагрузка skills!

Теперь не нужно рестартить контейнер при добавлении нового skill.
Просто добавьте файл в директорию skills/ и Moltis подхватит его
автоматически в течение 30 секунд.

Как включить:
[skills]
auto_reload = true
reload_interval = "30s"

#openclaw #moltis #skills
```

**Результат** (knowledge file):

```markdown
---
title: "Auto-reload Skills в Moltis"
category: "tutorial"
tags: ["moltis", "skills", "configuration", "feature"]
source: "@tsingular"
date: "2026-02-18"
confidence: "high"
original_url: "https://t.me/tsingular/12345"
---

# Auto-reload Skills в Moltis

## Summary
Moltis поддерживает автоматическую перезагрузку skills без
рестарта контейнера. Новые skills подхватываются в течение 30 секунд.

## Key Concepts
- **Auto-reload**: Автоматическое обнаружение новых skills
- **Hot-reload**: Обновление без перезапуска сервиса
- **Reload interval**: Интервал проверки (по умолчанию 30s)

## Configuration

Включить auto-reload в moltis.toml:

```toml
[skills]
auto_reload = true
reload_interval = "30s"
```

## Benefits
- ✅ Не нужен рестарт контейнера
- ✅ Быстрая итерация при разработке skills
- ✅ Минимальное прерывание сервиса

## Related
- [[Skills System]]
- [[Moltis Configuration]]

## References
- [Original post](https://t.me/tsingular/12345)
```

---

## 5. Templates

### 5.1 Template: Базовый Skill

```markdown
---
name: [skill-name]
description: [Что делает. Использовать когда X.]
---

# [Skill Name]

## Активация
[Триггеры для активации skill]

## Workflow

1. **[Step 1 Name]**
   - [Action]
   - [Criteria]

2. **[Step 2 Name]**
   - [Action]

## Templates

### [Template Name]
```[language]
[Template content]
```

## Examples

### Example: [Scenario]
Input: [Input example]
Output: [Output example]

## Best Practices
- [Practice 1]
- [Practice 2]

## Common Pitfalls
- ❌ [Mistake] → ✅ [Solution]
```

### 5.2 Template: Knowledge File

```markdown
---
title: "[Topic Title]"
category: "concept|tutorial|reference|troubleshooting"
tags: ["tag1", "tag2", "tag3"]
source: "@tsingular|URL|original"
date: "YYYY-MM-DD"
confidence: "high|medium|low"
original_url: "[if applicable]"
---

# [Topic Title]

## Summary
[2-3 sentences explaining what this is and why it matters]

## Key Concepts
- **[Concept 1]**: [Definition]
- **[Concept 2]**: [Definition]

## Details
[In-depth explanation]

## Code Examples
```[language]
[code example]
```

## Best Practices
- [Practice 1]
- [Practice 2]

## Common Issues
- ❌ [Issue] → ✅ [Solution]

## Related
- [[Related Topic 1]]
- [[Related Topic 2]]

## References
- [Source 1](URL)
```

### 5.3 Template: Soul Prompt для самообучения

```toml
[identity]
name = "Молтингер"
emoji = "🤖"
vibe = "technical"
soul = """
Ты - Молтингер, самообучающийся AI Agent Factory.

## Твоя миссия
Создавать AI агентов по методологии ASC AI Fabrique и постоянно
совершенствовать свои способности через самообучение.

## Твои способности

### Создание агентов
- Проектировать спецификации агентов
- Генерировать архитектуры
- Создавать презентации (Marp)
- Валидировать по ASC чеклисту

### Самообучение
- Извлекать знания из Telegram (@tsingular)
- Структурировать информацию в knowledge base
- Создавать skills на основе паттернов
- Валидировать новые знания

## Твои источники знаний
- Knowledge base: /server/knowledge/
- Skills: /server/skills/
- Telegram: @tsingular (OpenClaw новости)

## Твоё поведение

### При создании агента
1. Всегда начинай с понимания требований
2. Задавай уточняющие вопросы
3. Следуй ASC методологии
4. Генерируй структурированный вывод

### При самообучении
1. Анализируй новый контент критически
2. Валидируй информацию перед сохранением
3. Создавай связи с существующими знаниями
4. Фиксируй источник и confidence

## Форматирование
- Используй [OK]/[WARN]/[ERR] для статусов
- Структурируй вывод с помощью markdown
- Добавляй примеры для иллюстрации

## Язык
Отвечай на русском языке.
"""
```

### 5.4 Template: Telegram MCP Server Config

```toml
# Для интеграции Telegram через MCP
# Примечание: Требуется создание собственного MCP сервера

[mcp.servers.telegram]
command = "node"
args = ["/server/mcp/telegram-server/index.js"]
env = {
  TELEGRAM_API_ID = "${TELEGRAM_API_ID}",
  TELEGRAM_API_HASH = "${TELEGRAM_API_HASH}",
  TELEGRAM_PHONE = "${TELEGRAM_PHONE}"
}
enabled = true
transport = "stdio"
```

---

## 6. Troubleshooting

### 6.1 Skills не загружаются

**Симптомы**:
- Skill не активируется по команде
- Ошибки в логах при загрузке

**Диагностика**:
```bash
# Проверить пути
grep "search_paths" ~/.config/moltis/moltis.toml

# Проверить существование директории
ls -la /server/skills/

# Проверить формат SKILL.md
head -20 /server/skills/my-skill/SKILL.md
```

**Решения**:
1. Проверь что путь в `search_paths` существует
2. Проверь frontmatter в SKILL.md (должен быть валидный YAML)
3. Проверь права доступа к файлам
4. Перезапусти Moltis

### 6.2 Memory не индексируется

**Симптомы**:
- Knowledge не находится при запросах
- RAG не работает

**Диагностика**:
```bash
# Проверить конфигурацию
grep -A10 "\[memory\]" ~/.config/moltis/moltis.toml

# Проверить watch_dirs
grep "watch_dirs" ~/.config/moltis/moltis.toml

# Проверить что Ollama запущен (если provider = "ollama")
curl http://localhost:11434/api/tags
```

**Решения**:
1. Убедись что `provider` правильный
2. Убедись что Ollama запущен и имеет модель embeddings
3. Проверь что пути в `watch_dirs` существуют
4. Проверь логи Moltis на ошибки

### 6.3 Telegram интеграция не работает

**Симптомы**:
- Bot не отвечает
- Не получает сообщения из канала

**Диагностика**:
```bash
# Проверить конфигурацию
grep -A5 "\[channels.telegram\]" ~/.config/moltis/moltis.toml

# Проверить токен
echo $TELEGRAM_BOT_TOKEN

# Проверить webhook (если используется)
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
```

**Решения**:
1. Проверь что токен валидный (не истёк)
2. Для каналов: bot должен быть admin
3. Проверь `allowed_users` если ограничен доступ
4. Для monitoring: нужен userbot или admin права

### 6.4 MCP Server не подключается

**Симптомы**:
- Ошибки при запуске Moltis
- MCP tools недоступны

**Диагностика**:
```bash
# Проверить конфигурацию
grep -A10 "\[mcp.servers" ~/.config/moltis/moltis.toml

# Проверить команду вручную
npx -y @package/name

# Проверить env variables
env | grep API_KEY
```

**Решения**:
1. Проверь что команда работает из терминала
2. Проверь environment variables
3. Проверь `enabled = true`
4. Проверь транспорт (stdio vs sse)

---

## 7. Quick Reference

### 7.1 Частые команды

```bash
# Перезапуск Moltis (Docker)
docker compose restart moltis

# Просмотр логов
docker logs moltis --tail 100 -f

# Проверка статуса
curl http://localhost:13131/health

# Создать новый skill
mkdir -p /server/skills/my-skill
cat > /server/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: Description here
---
# My Skill
Content here
EOF

# Добавить knowledge файл
cat > /server/knowledge/concepts/topic.md << 'EOF'
---
title: "Topic"
category: "concept"
tags: ["tag"]
---
# Topic
Content here
EOF
```

### 7.2 Структура директорий

```
/server/
├── config/
│   └── moltis.toml          # Главный конфиг
├── skills/
│   ├── agent-spec-generator/
│   │   └── SKILL.md
│   ├── telegram-learner/
│   │   └── SKILL.md
│   └── ...
├── knowledge/
│   ├── concepts/
│   ├── tutorials/
│   ├── references/
│   └── troubleshooting/
└── mcp/
    └── telegram-server/      # Кастомный MCP
```

### 7.3 Конфигурация чеклист

**Для Skills**:
- [ ] `skills.enabled = true`
- [ ] `skills.search_paths` содержит нужный путь
- [ ] Директория skills существует
- [ ] SKILL.md имеет валидный frontmatter

**Для Memory**:
- [ ] `memory.provider` настроен
- [ ] `memory.watch_dirs` содержит пути к knowledge
- [ ] Ollama запущен (если provider = "ollama")
- [ ] Модель embeddings доступна

**Для Telegram**:
- [ ] `channels.telegram.enabled = true`
- [ ] `TELEGRAM_BOT_TOKEN` в env
- [ ] Bot добавлен в канал (для мониторинга)

---

## 8. Deployment

### 8.1 GitOps Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                    GitOps DEPLOY                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Изменить файлы локально                                 │
│     ├─ config/moltis.toml                                   │
│     ├─ skills/*/SKILL.md                                    │
│     └─ knowledge/**/*.md                                    │
│                                                             │
│  2. Commit & Push                                           │
│     $ git add .                                             │
│     $ git commit -m "feat: add new skill X"                 │
│     $ git push origin main                                  │
│                                                             │
│  3. GitHub Actions (автоматически)                          │
│     ├─ Build & Test                                         │
│     ├─ Deploy to server                                     │
│     └─ Restart Moltis                                       │
│                                                             │
│  4. Verify                                                  │
│     $ curl https://moltis.ainetic.tech/health               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 8.2 Manual Deploy

```bash
# На сервере ainetic.tech
ssh root@ainetic.tech

# Перейти в директорию проекта
cd /opt/moltinger

# Обновить из git
git pull origin main

# Перезапустить Moltis
docker compose restart moltis

# Проверить логи
docker logs moltis --tail 50
```

---

## 9. Первая задача: Telegram Monitor Setup

### 9.1 План реализации

```
TASK: Telegram Monitor для @tsingular
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Phase 1: Setup (1 час)
├── Получить API credentials
│   ├── Telegram API ID: https://my.telegram.org/apps
│   └── Telegram API Hash
├── Создать .env с credentials
└── Протестировать подключение

Phase 2: Skill Creation (2 часа)
├── Создать skills/telegram-learner/SKILL.md
├── Добавить workflow для извлечения знаний
└── Протестировать на реальных постах

Phase 3: Knowledge Base (1 час)
├── Создать структуру knowledge/
├── Добавить первые knowledge файлы
└── Настроить watch_dirs

Phase 4: Automation (2 часа)
├── Настроить heartbeat для периодического запуска
├── Добавить в auto_load
└── Monitor и iterate
```

### 9.2 Первые шаги

```bash
# 1. Создать директории
mkdir -p /server/{skills/telegram-learner,knowledge/{concepts,tutorials}}

# 2. Получить Telegram API credentials
# Идти на https://my.telegram.org/apps
# Создать app, получить api_id и api_hash

# 3. Добавить в .env
echo "TELEGRAM_API_ID=your_id" >> .env
echo "TELEGRAM_API_HASH=your_hash" >> .env

# 4. Создать skill
# См. пример в секции 4.2

# 5. Обновить конфигурацию
# Добавить watch_dirs в moltis.toml

# 6. Deploy
git add . && git commit -m "feat: add telegram-learner skill"
git push
```

---

## 10. Заключение

### 10.1 Key Takeaways

1. **4 механизма расширения**: Soul, Skills, Memory, MCP — используй их вместе
2. **Skills для паттернов**: Повторяющиеся задачи → skills
3. **Memory для фактов**: Информация, документация → memory
4. **Telegram требует подготовки**: Userbot или admin права на канале
5. **GitOps для деплоя**: Push → GitHub Actions → Server

### 10.2 Следующие шаги

1. ✅ Прочитать этот документ полностью
2. ⬜ Создать первый skill (telegram-learner)
3. ⬜ Настроить Telegram API credentials
4. ⬜ Протестировать извлечение знаний из @tsingular
5. ⬜ Создать базу knowledge файлов
6. ⬜ Настроить автоматический запуск

---

**Конец документа**

---

*Generated for Moltis Self-Learning*
*Version: 1.0.0*
*Date: 2026-02-18*
