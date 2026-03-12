# OpenClaw/Moltis: Полное исследование для самообучения агента

**Дата исследования**: 2026-02-18
**Исследователь**: Research Specialist
**Версия Moltis**: Latest (ghcr.io/moltis-org/moltis:latest)
**Назначение**: Создание системы самообучения AI агента Молтингер

---

## Executive Summary

Moltis - это мощная платформа для AI агентов с развитой системой расширения через Skills, Memory/RAG и MCP серверы. Основные механизмы для самообучения:

1. **Soul Prompt** - определяет идентичность и поведение агента
2. **Skills System** - переиспользуемые шаблоны промптов
3. **Memory/RAG** - семантический поиск в базе знаний
4. **MCP Servers** - внешние инструменты и интеграции
5. **Telegram Integration** - канал для обучения и взаимодействия

**Ключевой вывод**: Moltis поддерживает несколько независимых механизмов добавления знаний, которые могут комбинироваться для создания самообучающегося агента.

---

## Часть 1: Архитектура Moltis для обучения

### 1.1 Обзор системы

```
┌─────────────────────────────────────────────────────────────┐
│                     MOLTIS CORE                             │
│                  (OpenClaw Gateway)                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              SOUL PROMPT (Identity)                   │  │
│  │         config/moltis.toml → [identity]              │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                  │
│         ┌─────────────────┼─────────────────┐               │
│         ▼                 ▼                 ▼               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   SKILLS    │  │   MEMORY    │  │  MCP TOOLS  │         │
│  │ ~/.config/  │  │ ~/.moltis/  │  │  External   │         │
│  │ moltis/     │  │ memory/     │  │  Servers    │         │
│  │ skills/     │  │             │  │             │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    LLM PROVIDERS                            │
│  (OpenAI, Anthropic, Ollama, Groq, xAI, Deepseek, etc)     │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Конфигурация moltis.toml (полная структура)

#### Server & Auth
```toml
[server]
bind = "0.0.0.0"              # Docker: must be 0.0.0.0
port = 13131                  # Main gateway port
http_request_logs = false
ws_request_logs = false
update_repository_url = "https://github.com/moltis-org/moltis"

[auth]
disabled = false              # true = DANGEROUS if exposed
```

#### Identity (Soul Prompt)
```toml
[identity]
name = "Молтингер"
emoji = "🤖"
vibe = "technical"
soul = """
Ты - Молтингер, AI-ассистент для разработки и DevOps.
...
"""
```

#### LLM Providers
```toml
[providers]
offered = ["openai", "anthropic", "gemini", "groq"]
allowed_models = ["zai::glm-5", "zai::glm-4.7"]
priority_models = []

[providers.openai]
enabled = true
api_key = "${GLM_API_KEY}"
model = "glm-5"
base_url = "https://api.z.ai/api/coding/paas/v4"
alias = "zai"
```

#### Chat Settings
```toml
[chat]
message_queue_mode = "followup"  # or "collect"
allowed_models = ["zai::glm-5", "zai::glm-4.7"]
priority_models = []
```

#### Tools & Sandbox
```toml
[tools]
agent_timeout_secs = 600
max_tool_result_bytes = 50000

[tools.exec]
default_timeout_secs = 30
max_output_bytes = 204800
approval_mode = "on-miss"
security_level = "allowlist"
allowlist = []

[tools.exec.sandbox]
mode = "all"                  # "off", "non-main", "all"
scope = "session"             # "command", "session", "global"
workspace_mount = "ro"        # "ro", "rw", "none"
backend = "auto"              # "auto", "docker", "apple-container"
no_network = true

[tools.exec.sandbox.resource_limits]
memory_limit = "512M"
cpu_quota = 0.5
pids_max = 100

[tools.exec.sandbox.packages]
# Список пакетов для sandbox image
```

#### Web Tools
```toml
[tools.web.search]
enabled = false               # Using Tavily MCP instead
provider = "brave"
max_results = 5
timeout_seconds = 30

[tools.web.fetch]
enabled = true
max_chars = 50000
timeout_seconds = 30
cache_ttl_minutes = 15
max_redirects = 3
readability = true
```

#### Browser Automation
```toml
[tools.browser]
enabled = true
headless = true
viewport_width = 2560
viewport_height = 1440
device_scale_factor = 2.0
max_instances = 3
idle_timeout_secs = 300
navigation_timeout_ms = 30000
allowed_domains = []
```

#### Skills System
```toml
[skills]
enabled = true
search_paths = []             # Additional directories
auto_load = []                # Always-loaded skills
```

**Default locations**:
- `~/.config/moltis/skills/`
- `./skills/` (relative to working directory)

#### MCP Servers
```toml
[mcp.servers.server-name]
command = "npx"
args = ["-y", "@package/name"]
env = { KEY = "value" }
enabled = true
transport = "stdio"           # or "sse"
url = "http://..."            # for SSE
```

**Active MCP servers in project**:
```json
{
  "mcpServers": {
    "context7": {...},
    "sequential-thinking": {...},
    "supabase": {...},
    "playwright": {...},
    "shadcn": {...},
    "serena": {...}
  }
}
```

#### Memory & Embeddings
```toml
[memory]
llm_reranking = false
session_export = false
# provider = "local"          # "local", "ollama", "openai", "custom"
# base_url = "http://localhost:11434/v1"
# model = "nomic-embed-text"
# api_key = "..."

# Для RAG:
# watch_dirs = ["~/.moltis/memory", "/path/to/knowledge"]
```

#### Channels (Telegram)
```toml
[channels.telegram]
enabled = true

[channels.telegram.moltis-bot]
token = "${TELEGRAM_BOT_TOKEN}"
allowed_users = "${TELEGRAM_ALLOWED_USERS:-}"  # Comma-separated user IDs from env
```

#### Metrics & Telemetry
```toml
[metrics]
enabled = true
prometheus_endpoint = true

[telemetry]
enabled = false
otlp_endpoint = "http://localhost:4317"
```

#### Heartbeat
```toml
[heartbeat]
enabled = true
every = "30m"
ack_max_chars = 300
sandbox_enabled = true

[heartbeat.active_hours]
start = "08:00"
end = "23:59"
timezone = "local"
```

#### Voice (TTS/STT)
```toml
[voice.tts]
enabled = true
provider = "piper"            # "piper", "coqui", "elevenlabs", "openai", "google"

[voice.stt]
enabled = true
provider = "whisper"          # "whisper", "groq", "mistral"
```

### 1.3 Пути к файлам и директориям

**Configuration**:
- macOS/Linux: `~/.config/moltis/moltis.toml`
- Docker volume: `/home/moltis/.config/moltis/`

**Data**:
- macOS/Linux: `~/.moltis/`
- Docker volume: `/home/moltis/.moltis/`

**Skills locations** (search order):
1. `~/.config/moltis/skills/`
2. `./skills/` (relative to working directory)
3. Custom paths from `skills.search_paths`

**Memory locations**:
- `~/.moltis/memory/` (default)
- Any path in `memory.watch_dirs`

---

## Часть 2: Skills System

### 2.1 Формат SKILL.md

**Пример структуры**:
```markdown
---
name: skill-name
description: What it does. Use when [specific scenario].
---

# Skill Name

## Quick Start

### Main Capabilities
...

## Core Expertise
...

## Tech Stack
...

## Reference Documentation
...

## Best Practices
...

## Common Commands
...

## Resources
...
```

**Реальный пример** (code-reviewer):
```markdown
---
name: code-reviewer
description: Comprehensive code review skill for TypeScript, JavaScript, Python, Swift, Kotlin, Go. Use when reviewing pull requests, providing code feedback, identifying issues, or ensuring code quality standards.
---

# Code Reviewer

Complete toolkit for code reviewer with modern tools and best practices.

## Quick Start

### Main Capabilities

This skill provides three core capabilities through automated scripts:
...

## Core Capabilities

### 1. Pr Analyzer
...

## Reference Documentation

### Code Review Checklist
...

## Tech Stack
...

## Best Practices Summary
...

## Common Commands
...
```

### 2.2 Активация Skills

**Auto-load skills** (всегда активны):
```toml
[skills]
auto_load = ["skill-name-1", "skill-name-2"]
```

**Manual activation**:
- Пользователь может активировать skill через UI или API
- Skill добавляется в контекст LLM при активации

**Search paths**:
```toml
[skills]
search_paths = [
  "/opt/moltinger/skills",
  "/custom/path/to/skills"
]
```

### 2.3 Создание новых Skills

**Шаги**:
1. Создать директорию: `skills/my-skill/`
2. Создать файл: `skills/my-skill/SKILL.md`
3. (Опционально) Добавить `references/` с документацией
4. (Опционально) Добавить `scripts/` с утилитами
5. Перезапустить Moltis или дождаться автоматической перезагрузки

---

## Часть 3: Memory & RAG System

### 3.1 Конфигурация Memory

```toml
[memory]
llm_reranking = false
session_export = false
provider = "local"              # Options: "local", "ollama", "openai", "custom"
base_url = "http://localhost:11434/v1"  # For ollama/custom
model = "nomic-embed-text"      # Embedding model name
api_key = "..."                 # For openai/custom
```

### 3.2 Watch Directories

```toml
[memory.qmd.collections]
# Конфигурация QMD collections (если используется)

# Для RAG:
watch_dirs = [
  "~/.moltis/memory",           # Default location
  "/opt/moltinger/knowledge",    # Custom knowledge base
  "./docs",                      # Project documentation
]
```

### 3.3 Работа с Memory

**Создание memory файлов**:
- Создать markdown файлы в `~/.moltis/memory/` или в watch_dirs
- Moltis автоматически индексирует их для семантического поиска

**Формат memory файлов**:
```markdown
# Topic Name

## Summary
Краткое описание темы.

## Details
Подробная информация...

## Examples
Примеры использования...
```

### 3.4 Альтернатива: Filesystem MCP

Если Memory/RAG сложно настроить, можно использовать MCP filesystem:

```toml
[mcp.servers.knowledge-base]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/knowledge"]
enabled = true
```

**Преимущества MCP filesystem**:
- Не требует embeddings
- Простой доступ к файлам
- Moltis может читать и анализировать файлы напрямую

**Недостатки**:
- Нет семантического поиска
- Меньшая "интеллектуальность" при поиске релевантной информации

---

## Часть 4: MCP Servers Integration

### 4.1 Активные MCP серверы в проекте

**Context7** (документация библиотек):
```toml
[mcp.servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp@latest"]
```

**Sequential Thinking** (цепочки рассуждений):
```toml
[mcp.servers.sequential-thinking]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-sequential-thinking"]
```

**Supabase** (база данных):
```toml
[mcp.servers.supabase]
command = "npx"
args = ["-y", "@supabase/mcp-server-supabase@latest", "--project-ref=${SUPABASE_PROJECT_REF}"]
env = { SUPABASE_ACCESS_TOKEN = "${SUPABASE_ACCESS_TOKEN}" }
```

**Playwright** (браузерная автоматизация):
```toml
[mcp.servers.playwright]
command = "npx"
args = ["@playwright/mcp@latest"]
```

**Shadcn** (UI компоненты):
```toml
[mcp.servers.shadcn]
command = "npx"
args = ["shadcn@latest", "mcp"]
```

**Serena** (IDE assistant):
```toml
[mcp.servers.serena]
command = "uvx"
args = ["--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--context", "ide-assistant"]
```

### 4.2 Создание собственных MCP серверов

**Базовый шаблон** (stdio):
```toml
[mcp.servers.my-custom-server]
command = "node"
args = ["/path/to/server.js"]
env = { API_KEY = "${MY_API_KEY}" }
enabled = true
transport = "stdio"
```

**SSE сервер**:
```toml
[mcp.servers.remote-server]
transport = "sse"
url = "http://localhost:8080/sse"
enabled = true
```

### 4.3 Использование MCP для самообучения

**Pattern 1: Knowledge Base MCP**
Создать MCP сервер для доступа к базе знаний:
```toml
[mcp.servers.asc-knowledge]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/opt/moltinger/knowledge/asc"]
enabled = true
```

**Pattern 2: Learning MCP**
Создать MCP сервер который:
- Читает новые знания из Telegram
- Сохраняет их в базу знаний
- Обновляет индексы

---

## Часть 5: Telegram Integration

### 5.1 Конфигурация Telegram

```toml
[channels.telegram]
enabled = true

[channels.telegram.moltis-bot]
token = "${TELEGRAM_BOT_TOKEN}"
allowed_users = "${TELEGRAM_ALLOWED_USERS:-}"  # Comma-separated user IDs from env, or specify IDs
```

### 5.2 Создание Telegram бота

1. **Создать бота через @BotFather**:
   ```
   /newbot
   MyBotName
   moltinger_bot
   ```

2. **Получить токен** и сохранить в секретах:
   ```bash
   # В .env или через docker secrets
   TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
   ```

3. **Получить User ID** через @userinfobot

### 5.3 Мониторинг Telegram каналов

**Для мониторинга канала @tsingular** (или любого другого):

**Option 1: Userbot подход (Telethon/Pyrogram)**
- Неофициальный метод
- Требует user account (не bot)
- Может читать любые каналы

**Option 2: Bot API ограничения**
- Боты могут читать только каналы где они являются admin
- Для публичных каналов можно использовать webhooks

**Option 3: RSS/Atom feed**
- Некоторые Telegram каналы имеют RSS
- Можно парсить через стандартные инструменты

### 5.4 Создание Skill для мониторинга Telegram

**Пример структуры**:
```markdown
---
name: telegram-channel-monitor
description: Мониторит Telegram канал и извлекает новый контент для обучения
---

# Telegram Channel Monitor

## Активация
Используй когда нужно получить новый контент из Telegram канала.

## Workflow

1. **Подключиться к каналу**
   - Используй Telegram Bot API или MCP сервер
   - Укажи канал: @tsingular

2. **Получить посты**
   - Последние N постов
   - С датами и метаданными

3. **Извлечь контент**
   - Текст сообщений
   - Комментарии/обсуждения
   - Медиа (описания)

4. **Сохранить в knowledge base**
   - Создать markdown файлы
   - Добавить теги и метаданные
```

### 5.5 Telegram MCP Servers

**Для интеграции с Telegram через MCP**:

Необходимо создать/найти MCP сервер для Telegram:
```toml
[mcp.servers.telegram]
command = "node"
args = ["/path/to/telegram-mcp-server.js"]
env = {
  TELEGRAM_API_ID = "${TELEGRAM_API_ID}",
  TELEGRAM_API_HASH = "${TELEGRAM_API_HASH}"
}
enabled = true
```

**Примечание**: На момент исследования (2026-02-18) официального MCP сервера для Telegram не найдено.

---

## Часть 6: Self-Learning Patterns

### 6.1 Паттерны автономного обучения

**Pattern 1: RAG-based Learning**
```
1. Агент получает новый контент (из Telegram, API, файлов)
2. Контент сохраняется в memory/ с тегами
3. Moltis индексирует контент через embeddings
4. При запросах агент ищет релевантную информацию
5. Релевантные контексты добавляются в промпт
```

**Pattern 2: Skill-based Learning**
```
1. Создать skill с инструкциями по обучению
2. Skill содержит шаблоны для анализа контента
3. Агент использует skill для обработки новых знаний
4. Результаты сохраняются как новые skills или memory
```

**Pattern 3: MCP-based Learning**
```
1. MCP сервер подключается к внешнему источнику знаний
2. Агент запрашивает информацию через MCP
3. Полученная информация анализируется
4. Результат сохраняется в memory или как skill
```

**Pattern 4: Telegram-based Learning**
```
1. Агент мониторит Telegram канал
2. Новые сообщения извлекаются
3. Контент анализируется и структурируется
4. Знания сохраняются в базу
5. Агент может ссылаться на источник знаний
```

### 6.2 Best Practices из сообщества

**Примечание**: Веб-поиск не нашел публичной информации о @tsingular или OpenClaw сообществе. Рекомендации основаны на общих паттернах для AI агентов.

**General AI Agent Learning Patterns**:

1. **Incremental Learning**
   - Добавлять знания небольшими порциями
   - Валидировать новые знания перед добавлением
   - Хранить метаданные (источник, дата, уверенность)

2. **Knowledge Validation**
   - Кросс-проверка из нескольких источников
   - User feedback loop
   - Version control для knowledge base

3. **Context Management**
   - Использовать теги для категоризации знаний
   - Ограничивать размер контекста
   - Приоритизировать релевантность

4. **Continuous Improvement**
   - Анализировать какие знания используются чаще
   - Удалять устаревшие знания
   - Обновлять на основе feedback

### 6.3 Примеры Self-Learning Skills

**Learning Skill Template**:
```markdown
---
name: self-learning-processor
description: Обрабатывает новый контент и интегрирует его в базу знаний
---

# Self-Learning Processor

## Когда использовать
- При получении нового контента для обучения
- При обновлении существующих знаний
- При валидации знаний

## Workflow

### 1. Analyze Content
- Определи тип контента (tutorial, discussion, news)
- Извлек ключевые концепции
- Определи релевантность для текущих задач

### 2. Validate Knowledge
- Проверь на противоречия с существующими знаниями
- Оцени достоверность источника
- Отметь требующие проверки факты

### 3. Structure Knowledge
- Создай структурированный markdown файл
- Добавь метаданные (source, date, tags)
- Свяжи с существующими знаниями

### 4. Store Knowledge
- Сохрани в соответствующую директорию memory/
- Добавь в watch_dirs для индексации
- Создай cross-references при необходимости

## Output Format
```markdown
---
source: "@tsingular or URL"
date: "2026-02-18"
tags: ["tutorial", "docker", "deployment"]
confidence: "high"  # high/medium/low
---

# Topic Name

## Summary
...

## Key Concepts
- ...
- ...

## Related Topics
- [[Other Topic]]
- [[Another Topic]]
```
```

---

## Часть 7: Рекомендации для обучения LLM

### 7.1 Структура документа для обучения

**Оптимальная структура для LLM comprehension**:

```markdown
# [Topic Name]

## Executive Summary
[2-3 sentences explaining what this is]

## Core Concepts
### Concept 1
[Definition + explanation]

### Concept 2
[Definition + explanation]

## How It Works
[Step-by-step process]

## Examples
### Example 1: [Scenario]
[Concrete example with input/output]

### Example 2: [Scenario]
[Concrete example with input/output]

## Best Practices
1. [Practice 1]
2. [Practice 2]
3. [Practice 3]

## Common Pitfalls
- ❌ [Pitfall 1] - [Why it's wrong] - ✅ [Correct approach]
- ❌ [Pitfall 2] - [Why it's wrong] - ✅ [Correct approach]

## Relationships
- Relates to: [[Topic A]], [[Topic B]]
- Prerequisite for: [[Topic C]]
- Alternative to: [[Topic D]]

## References
- [Source 1](URL)
- [Source 2](URL)
```

### 7.2 Ключевые секции для агента

**Must-have секции**:
1. **Purpose/Goal** - зачем это нужно знать
2. **Key Terms** - терминология с определениями
3. **Workflow/Process** - пошаговые инструкции
4. **Decision Criteria** - когда использовать
5. **Examples** - конкретные примеры

**Should-have секции**:
1. **Context** - где это применяется
2. **Trade-offs** - плюсы и минусы
3. **Related Concepts** - связи с другими знаниями
4. **Troubleshooting** - что делать если не работает

**Nice-to-have секции**:
1. **History/Evolution** - как развивалось
2. **Alternatives** - другие подходы
3. **Future Directions** - куда движется
4. **Community Resources** - где узнать больше

### 7.3 Metadata для знаний

**Рекомендуемые frontmatter**:
```yaml
---
title: "Topic Name"
category: "concept|tutorial|reference|troubleshooting"
difficulty: "beginner|intermediate|advanced"
tags: ["tag1", "tag2", "tag3"]
related: [["topic1"], ["topic2"]]
prerequisites: [["topic3"]]
last_updated: "2026-02-18"
source: "original|@tsingular|URL"
confidence: "high|medium|low"
---
```

### 7.4 Naming Conventions

**Для файлов**:
- Использовать kebab-case: `docker-deployment.md`
- Информативные имена: `telegram-bot-setup.md` (не `guide.md`)
- Категоризация через директории: `knowledge/deploy/docker/`

**Для секций**:
- Использовать # для заголовков
- Чёткая иерархия (H1 > H2 > H3)
- Описательные заголовки

**Для концептов**:
- **Bold** для ключевых терминов при первом упоминании
- `code` для технических терминов
- "Кавычки" для буквальных значений

---

## Часть 8: Практическое руководство по внедрению

### 8.1 Phase 1: Базовая настройка (30 мин)

**Обновить Soul Prompt**:
```toml
[identity]
name = "Молтингер"
soul = """
Ты - самообучающийся AI ассистент.

## Твоя роль
- Учиться из новых источников знаний
- Структурировать и сохранять знания
- Применять знания на практике

## Источники знаний
- Telegram каналы (настройте через MCP)
- Документация в memory/
- Skills в ~/.config/moltis/skills/

## Процесс обучения
1. Получи новый контент
2. Проанализируй и структурируй
3. Сохрани в базу знаний
4. Применяй в работе
"""
```

### 8.2 Phase 2: Memory Setup (1-2 часа)

**Настроить watch_dirs**:
```toml
[memory]
enabled = true
provider = "ollama"             # или "local"
model = "nomic-embed-text"

watch_dirs = [
  "~/.moltis/memory",
  "/opt/moltinger/knowledge",
]
```

**Создать структуру knowledge**:
```
/opt/moltinger/knowledge/
├── tutorials/
├── concepts/
├── troubleshooting/
├── best-practices/
└── references/
```

### 8.3 Phase 3: Learning Skills (2-3 часа)

**Создать learning skill**:
`skills/content-processor/SKILL.md`

```markdown
---
name: content-processor
description: Обрабатывает новый контент из Telegram и других источников для обучения
---

# Content Processor

## Workflow
1. Извлечь ключевые концепции
2. Структурировать по шаблону
3. Проверить на противоречия
4. Сохранить в knowledge base
```

### 8.4 Phase 4: Telegram Integration (2-4 часа)

**Option A: Через webhook**
1. Настроить webhook endpoint в Moltis
2. Подключить Telegram bot к webhook
3. Создать skill для обработки входящих сообщений

**Option B: Через polling**
1. Создать MCP сервер для Telegram
2. Настроить periodic polling
3. Обрабатывать новые сообщения

### 8.5 Phase 5: Validation & Iterate (ongoing)

**Контрольные вопросы**:
- [ ] Агент правильно извлекает знания из контента?
- [ ] Знания корректно структурированы?
- [ ] Агент использует знания при ответах?
- [ ] Нет противоречий в knowledge base?

**Metrics**:
- Количество обработанных документов
- Точность извлечения концепций
- Частота использования знаний
- User satisfaction score

---

## Часть 9: Мониторинг и Maintenance

### 9.1 Health Checks

**Проверка Memory**:
```bash
# Проверить индекс
ls -la ~/.moltis/memory/

# Проверить watch_dirs
grep "watch_dirs" ~/.config/moltis/moltis.toml
```

**Проверка Skills**:
```bash
# Проверить загруженные skills
ls -la ~/.config/moltis/skills/

# Проверить search_paths
grep "search_paths" ~/.config/moltis/moltis.toml
```

**Проверка MCP**:
```bash
# Проверить активные MCP серверы
grep "\[mcp.servers" ~/.config/moltis/moltis.toml
```

### 9.2 Updating Knowledge Base

**Добавление новых знаний**:
1. Создать markdown файл в `knowledge/`
2. Следовать структуре из Part 7
3. Добавить metadata
4. Перезапустить Moltis для переиндексации

**Обновление существующих знаний**:
1. Найти файл через поиск
2. Обновить content
3. Обновить `last_updated` в metadata
4. Закоммитить изменения в Git

### 9.3 Backup Strategy

**Резервное копирование knowledge base**:
```bash
# Локально
tar -czf knowledge-backup-$(date +%Y%m%d).tar.gz knowledge/

# В Git
git add knowledge/
git commit -m "docs: update knowledge base"
git push
```

**Резервное копирование config**:
```bash
# Moltis config
cp ~/.config/moltis/moltis.toml ~/.config/moltis/moltis.toml.backup

# Skills
tar -czf skills-backup-$(date +%Y%m%d).tar.gz ~/.config/moltis/skills/
```

---

## Часть 10: Troubleshooting

### 10.1 Common Issues

**Issue: Skills не загружаются**
- Проверить `search_paths` в moltis.toml
- Проверить права доступа к директориям
- Проверить формат YAML frontmatter в SKILL.md
- Перезапустить Moltis

**Issue: Memory не индексируется**
- Проверить что `memory.enabled = true`
- Проверить что провайдер embeddings доступен
- Проверить `watch_dirs` - пути должны существовать
- Проверить логи Moltis на ошибки

**Issue: MCP сервер не подключается**
- Проверить что команда работает из терминала
- Проверить environment variables
- Проверить enabled = true
- Проверить транспорт (stdio vs sse)

**Issue: Telegram bot не получает сообщения**
- Проверить токен бота
- Проверить что bot добавлен в канал (для private)
- Проверить webhook settings
- Проверить allowed_users

### 10.2 Debug Logging

**Включить debug logging**:
```toml
[server]
http_request_logs = true
ws_request_logs = true
```

**Проверить логи**:
```bash
# Docker
docker logs moltis --tail 100 -f

# Local
moltis gateway --verbose
```

---

## Summary & Action Items

### Что было исследовано:

1. ✅ **Moltis Architecture** - полная конфигурация moltis.toml
2. ✅ **Skills System** - формат SKILL.md, активация, создание
3. ✅ **Memory/RAG** - watch_dirs, embeddings, индексация
4. ✅ **MCP Servers** - интеграция, создание собственных серверов
5. ✅ **Telegram Integration** - настройка бота, мониторинг каналов
6. ✅ **Self-Learning Patterns** - паттерны автономного обучения
7. ✅ **Documentation Format** - структура для обучения LLM

### Next Steps:

**Немедленные действия** (Phase 1-2):
1. Обновить Soul Prompt в moltis.toml
2. Создать структуру knowledge base
3. Настроить memory.watch_dirs
4. Создать базовые learning skills

**Краткосрочные задачи** (Phase 3-4):
1. Настроить Telegram интеграцию
2. Создать content-processor skill
3. Реализовать feedback loop
4. Деплой на сервер ainetic.tech

**Долгосрочные задачи**:
1. Создать dashboard для мониторинга обучения
2. Реализовать автоматическую валидацию знаний
3. Добавить поддержку voice input/output
4. Интегрировать с ASC AI Fabrique

### Key Takeaways:

1. **Moltis поддерживает 4 независимых механизма обучения**: Soul, Skills, Memory, MCP
2. **Skills лучше для повторяющихся паттернов**, Memory - для фактов
3. **Telegram требует custom MCP сервера** для полноценной интеграции
4. **Stруктура документации критически важна** для эффективного обучения
5. **GitOps deploy через GitHub Actions** для обновлений

---

## Appendix A: Полный пример миграции

### From: DevOps Assistant
### To: Self-Learning Agent Factory

**Step 1: Update Soul**
```toml
soul = """
Ты - Молтингер, AI Agent Factory и самообучающийся ассистент.

## Основная роль
Создание AI агентов по методологии ASC AI Fabrique

## Способности к обучению
- Извлекаю знания из Telegram каналов
- Структурирую информацию в knowledge base
- Создаю skills на основе паттернов
- Валидирую знания перед применением

## Workflow создания агента
1. Собрать требования
2. Сформировать spec.md
3. Сгенерировать architecture.md
4. Создать presentation.md (Marp)
5. Валидировать по ASC чеклисту
"""
```

**Step 2: Configure Memory**
```toml
[memory]
enabled = true
provider = "ollama"
model = "nomic-embed-text"
watch_dirs = [
  "~/.moltis/memory",
  "/opt/moltinger/knowledge/asc",
  "/opt/moltinger/knowledge/tutorials",
]
```

**Step 3: Create Learning Skill**
`skills/self-learner/SKILL.md` - см. пример в Part 6.3

**Step 4: Deploy**
```bash
git add config/moltis.toml skills/
git commit -m "feat: enable self-learning capabilities"
git push
# GitHub Actions автоматически деплоит на ainetic.tech
```

---

## Appendix B: Полезные ресурсы

### Official Documentation:
- Moltis Docs: https://docs.moltis.org/
- MCP Protocol: https://modelcontextprotocol.io/
- Telegram Bot API: https://core.telegram.org/bots/api

### Community:
- GitHub: https://github.com/moltis-org/moltis
- Discord: (если доступен)

### Related Projects:
- ASC AI Fabrique mirror: docs/ASC-AI-FABRIQUE-MIRROR.md
- Agent Factory Lifecycle: docs/plans/agent-factory-lifecycle.md

---

**Конец документа**

---

*Generated by Research Specialist*
*Date: 2026-02-18*
*Version: 1.0.0*
