---
name: telegram-learner
description: Мониторит Telegram каналы и извлекает знания для самообучения Moltis.
  Использовать для периодического обновления базы знаний из Telegram источников.
---

# Telegram Learner

## Активация

Используй этот skill когда:
- Пользователь просит "обнови знания из Telegram"
- Пользователь просит "извлеки знания из @tsingular"
- Нужно периодическое обучение (heartbeat trigger)
- Пользователь спрашивает о новых возможностях Moltis/OpenClaw

## Prerequisites

**Требуемые переменные окружения** (уже настроены):
- `TELEGRAM_BOT_TOKEN` - токен бота
- `TELEGRAM_ALLOWED_USERS` - разрешённые пользователи

**Каналы для мониторинга**:
- @tsingular - новости OpenClaw и работа с ним

## Workflow

### Phase 1: Подключение к источнику

```
1. Определи источник:
   - @tsingular → новости OpenClaw/Moltis
   - Другие каналы → по запросу пользователя

2. Проверь доступ:
   - Для публичных каналов: можно читать через bot API
   - Для приватных: bot должен быть admin

3. Получи последние сообщения:
   - По умолчанию: последние 10 сообщений
   - Можно указать: конкретный период или ID
```

### Phase 2: Фильтрация контента

```
Критерии релевантности для @tsingular:

✅ РЕЛЕВАНТНО:
- Новые функции Moltis/OpenClaw
- Туториалы и how-to
- Best practices
- Решения проблем (troubleshooting)
- Паттерны использования
- Примеры кода/конфигурации

❌ НЕ РЕЛЕВАНТНО:
- Реклама
- Общие новости AI (не связанные с OpenClaw)
- Флуд и оффтоп
- Уже известная информация
```

### Phase 3: Извлечение знаний

**Для каждого релевантного сообщения**:

```
1. Определи тип контента:
   - CONCEPT → новая концепция/функция
   - TUTORIAL → пошаговое руководство
   - REFERENCE → справочная информация
   - TROUBLESHOOTING → решение проблемы
   - PATTERN → паттерн использования

2. Извлеки ключевые элементы:
   - Главная тема (title)
   - Ключевые концепции
   - Практические советы
   - Примеры кода/конфигурации
   - Ссылки на источники

3. Оцени уверенность (confidence):
   - HIGH → официальная информация, проверенные факты
   - MEDIUM → мнение экспертов, community knowledge
   - LOW → неподтверждённая информация
```

### Phase 4: Создание knowledge файла

**Шаблон файла**:

```markdown
---
title: "[Topic from Message]"
category: "concept|tutorial|reference|troubleshooting|pattern"
tags: ["openclaw", "moltis", "skill", "memory"]
source: "@tsingular"
date: "[YYYY-MM-DD]"
confidence: "high|medium|low"
original_url: "https://t.me/tsingular/[msg_id]"
---

# [Topic Title]

## Summary
[2-3 предложения - что это и зачем важно]

## Key Concepts
- **[Concept 1]**: [Определение]
- **[Concept 2]**: [Определение]

## Details
[Подробное описание из сообщения]

## Code Examples
```[language]
[Код из сообщения или пример использования]
```

## Usage
[Как применить это знание]

## Related
- [[Related Topic 1]]
- [[Related Topic 2]]

## References
- [Original Post](https://t.me/tsingular/[msg_id])
```

### Phase 5: Сохранение и индексация

```
1. Определи путь сохранения:
   - CONCEPT → knowledge/concepts/
   - TUTORIAL → knowledge/tutorials/
   - REFERENCE → knowledge/references/
   - TROUBLESHOOTING → knowledge/troubleshooting/
   - PATTERN → knowledge/patterns/

2. Сгенерируй имя файла:
   - Используй kebab-case: docker-deployment.md
   - Из темы сообщения: "Auto-reload Skills" → auto-reload-skills.md

3. Сохрани файл:
   - Путь: /server/knowledge/[category]/[filename].md

4. Проверь связи:
   - Добавь wiki-links на связанные темы
   - Обнови связанные файлы если нужно
```

### Phase 6: Создание skills (опционально)

**Если обнаружен повторяющийся паттерн**:

```
1. Определи паттерн:
   - Повторяющаяся задача
   - Шаблонный workflow
   - Часто используемый процесс

2. Создай skill:
   mkdir -p skills/[skill-name]
   # Создать SKILL.md по шаблону в git-tracked repo source

3. Зарегистрируй skill:
   # Для production deploy skill должен быть затем синхронизирован в /home/moltis/.moltis/skills
```

## Output Format

После выполнения workflow:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   TELEGRAM LEARNING COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Source: @tsingular
Posts analyzed: [N]
Relevant posts: [M]
New knowledge files: [K]

[STATUS] Knowledge Files Created:
├── [OK] knowledge/tutorials/[topic-1].md
├── [OK] knowledge/concepts/[topic-2].md
└── [OK] knowledge/patterns/[topic-3].md

[STATUS] Skills Created:
├── [NEW] skills/[skill-name]/SKILL.md
└── None

[STATUS] Updated Files:
├── [UPD] knowledge/concepts/related-topic.md (added link)
└── None

Next recommended actions:
1. [Действие 1]
2. [Действие 2]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Examples

### Example 1: Извлечение tutorial из поста

**Input** (пост из @tsingular):
```
🚀 Новинка в Moltis: автоматическая перезагрузка skills!

Больше не нужно рестартить контейнер. Добавьте в moltis.toml:

[skills]
auto_reload = true
reload_interval = "30s"

И Moltis будет подхватывать новые skills автоматически!
```

**Output** (knowledge file):

```markdown
---
title: "Auto-reload Skills в Moltis"
category: "tutorial"
tags: ["moltis", "skills", "configuration", "hot-reload"]
source: "@tsingular"
date: "2026-02-18"
confidence: "high"
original_url: "https://t.me/tsingular/12345"
---

# Auto-reload Skills в Moltis

## Summary
Moltis поддерживает автоматическую перезагрузку skills без
рестарта контейнера. Новые skills подхватываются автоматически.

## Key Concepts
- **Auto-reload**: Автоматическое обнаружение новых skills
- **Hot-reload**: Обновление без перезапуска сервиса
- **Reload interval**: Интервал проверки (по умолчанию 30s)

## Configuration

```toml
[skills]
auto_reload = true
reload_interval = "30s"
```

## Usage
1. Добавь настройку в moltis.toml
2. Положи новый skill в директорию skills/
3. Подожди до 30 секунд
4. Skill автоматически загрузится

## Benefits
- ✅ Не нужен рестарт контейнера
- ✅ Быстрая итерация при разработке
- ✅ Минимальное прерывание сервиса

## Related
- [[Skills System]]
- [[Moltis Configuration]]

## References
- [Original post](https://t.me/tsingular/12345)
```

### Example 2: Обработка нерелевантного поста

**Input** (пост из @tsingular):
```
🔥 ChatGPT обновился до версии 5.0! Новые возможности...
```

**Output**:
```
[SKIP] Post #12346 - не релевантно
Reason: Общие новости AI, не связанные с OpenClaw/Moltis
```

### Example 3: Создание skill из паттерна

**Input** (серия постов о генерации спецификаций):
```
Пост 1: "Как создать спецификацию агента..."
Пост 2: "Шаблон spec.md для AI агентов..."
Пост 3: "Best practices по требованиям к агентам..."
```

**Output**:
```
[PATTERN DETECTED] Specification Generation

Multiple posts about agent specification generation.
Creating skill: agent-spec-generator

[CREATED] skills/agent-spec-generator/SKILL.md
```

## Error Handling

### Ошибка: Нет доступа к каналу

```
[ERR] Cannot access channel @tsingular
Reason: Bot is not admin of private channel

Solutions:
1. Contact channel owner to add bot as admin
2. Use userbot approach (Telethon)
3. Check if channel is public
```

### Ошибка: Дубликат знания

```
[WARN] Knowledge already exists: auto-reload-skills.md
Action: Check if update needed

If new information:
1. Merge with existing file
2. Update last_updated date
3. Add new sections

If duplicate:
1. Skip creation
2. Log for reference
```

## Best Practices

1. **Периодичность**: Запускай не чаще раза в день
2. **Дедупликация**: Проверяй существование знания перед созданием
3. **Валидация**: Всегда указывай confidence и источник
4. **Связи**: Добавляй wiki-links на связанные темы
5. **Структура**: Следуй шаблону knowledge файла

## Integration with Other Skills

- **self-learning-processor**: Может использовать этот skill для получения контента
- **agent-spec-generator**: Может использовать знания о спецификациях
- **content-validator**: Может валидировать извлечённые знания

---

*Skill Version: 1.0.0*
*Created: 2026-02-18*
*Author: Claude Code (based on MOLTIS-SELF-LEARNING-INSTRUCTION.md)*
