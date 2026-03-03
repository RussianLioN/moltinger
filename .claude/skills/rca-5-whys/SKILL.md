---
name: rca-5-whys
description: Метод Root Cause Analysis "5 почему" для глубокого анализа любой допущенной ошибки. Срабатывает автоматически при ошибках. Задаёт 5 последовательных вопросов "почему" для нахождения корневой причины.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Task, AskUserQuestion
---

# Root Cause Analysis: Метод "5 Почему"

## Обзор

Метод "5 почему" — это техника RCA (Root Cause Analysis) для нахождения корневой причины проблемы через последовательные вопросы. Каждый ответ становится базой для следующего вопроса.

**Принцип:** Поверхностная ошибка → Глубокий анализ → Системное исправление

## Возможности (Enhanced)

| Возможность | Описание |
|-------------|----------|
| **Auto-Context** | Автоматический сбор контекста (git, docker, system) |
| **Domain Templates** | Специализированные шаблоны для Docker, CI/CD, Data Loss |
| **Chain-of-Thought** | Структурированные рассуждения с гипотезами |
| **RCA Index** | Реестр всех RCA с метриками и трендами |
| **Test Generation** | Автоматическое создание regression тестов |

## Когда применять

**ОБЯЗАТЕЛЬНО при любой ошибке:**
- Ошибка в коде (баг, исключение, crash)
- Ошибка в рассуждениях (неверный вывод)
- Ошибка в процессе (пропущен шаг, нарушен протокол)
- Ошибка в коммуникации (непонимание, конфликт)
- Любой незапланированный результат

## Процесс "5 Почему"

### Структура анализа

```
Ошибка (симптом)
    ↓
Вопрос 1: Почему это произошло?
    ↓
Ответ 1 → Причина уровня 1
    ↓
Вопрос 2: Почему [Ответ 1]?
    ↓
Ответ 2 → Причина уровня 2
    ↓
Вопрос 3: Почему [Ответ 2]?
    ↓
Ответ 3 → Причина уровня 3
    ↓
Вопрос 4: Почему [Ответ 3]?
    ↓
Ответ 4 → Причина уровня 4
    ↓
Вопрос 5: Почему [Ответ 4]?
    ↓
Ответ 5 → КОРНЕВАЯ ПРИЧИНА
```

### Правила формулирования вопросов

1. **Каждый вопрос опирается на предыдущий ответ**
   - ❌ "Почему проект упал?" → "Почему не было тестов?" (скачок)
   - ✅ "Почему проект упал?" → "Упал из-за бага в конфиге" → "Почему баг попал в конфиг?"

2. **Один вопрос — одно направление**
   - Не объединять несколько причин в один ответ

3. **Искать системные причины, а не виноватых**
   - ❌ "Потому что разработчик ошибся"
   - ✅ "Потому что нет автоматической валидации конфига"

4. **Дойти до изменяемого уровня**
   - Корневая причина должна быть той, на которую можно повлиять

## Диалоговый формат

При каждой ошибке проводится диалог:

```
🤖 RCA АНАЛИЗ НАЧАТ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ ОШИБКА: [описание ошибки]

📝 Вопрос 1: Почему [ошибка произошла]?
   → [ответ]

📝 Вопрос 2: Почему [ответ 1]?
   → [ответ]

📝 Вопрос 3: Почему [ответ 2]?
   → [ответ]

📝 Вопрос 4: Почему [ответ 3]?
   → [ответ]

📝 Вопрос 5: Почему [ответ 4]?
   → [ответ]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 КОРНЕВАЯ ПРИЧИНА: [итоговый вывод]

📋 ДЕЙСТВИЯ:
1. [немедленное исправление]
2. [предотвращение повторения]
3. [обновление инструкций/навыков]

📁 ФИКСАЦИЯ: docs/rca/YYYY-MM-DD-[topic].md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Пример RCA

### Ошибка: Контейнер Moltis недоступен через Traefik

```
❌ ОШИБКА: 404 при обращении к moltis.ainetic.tech

📝 Вопрос 1: Почему возвращается 404?
   → Traefik не может найти маршрут к контейнеру Moltis

📝 Вопрос 2: Почему Traefik не находит маршрут?
   → Контейнер Moltis находится в другой Docker сети (traefik_proxy)
   → а Traefik ожидает его в traefik-net

📝 Вопрос 3: Почему Moltis в неправильной сети?
   → В docker-compose.yml указана сеть traefik_proxy,
   → но на сервере используется traefik-net

📝 Вопрос 4: Почему конфигурация сети не совпадает с сервером?
   → Не было проверки соответствия конфигурации перед деплоем
   → Нет теста на доступность контейнеров через правильную сеть

📝 Вопрос 5: Почему нет валидации сетевой конфигурации?
   → Отсутствует preflight-check для Docker сетей
   → Нет документации о сетевой топологии сервера

🎯 КОРНЕВАЯ ПРИЧИНА:
   Отсутствие системной валидации сетевой конфигурации
   и документации сетевой топологии продакшена.

📋 ДЕЙСТВИЯ:
1. [ИСПРАВЛЕНО] Добавить traefik.docker.network=traefik-net label
2. [ПРОФИЛАКТИКА] Добавить проверку сетей в preflight-check.sh
3. [ДОКУМЕНТАЦИЯ] Зафиксировать сетевую топологию в MEMORY.md
```

## Фиксация результатов

### Создание RCA отчёта

```bash
# Путь: docs/rca/YYYY-MM-DD-[short-topic].md
```

### Шаблон отчёта

```markdown
# RCA: [Краткое описание проблемы]

**Дата:** YYYY-MM-DD
**Статус:** Resolved / In Progress
**Влияние:** [описание воздействия]

## Ошибка

[Описание симптома]

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---------|--------|-------|
| 1 | Почему [симптом]? | [ответ] |
| 2 | Почему [ответ1]? | [ответ] |
| 3 | Почему [ответ2]? | [ответ] |
| 4 | Почему [ответ3]? | [ответ] |
| 5 | Почему [ответ4]? | [ответ] |

## Корневая причина

[Итоговый вывод]

## Принятые меры

1. **Немедленное исправление:** [что сделано]
2. **Предотвращение:** [что изменено в процессе]
3. **Документация:** [что обновлено]

## Связанные обновления

- [ ] Инструкции CLAUDE.md обновлены
- [ ] MEMORY.md обновлён
- [ ] Новые навыки созданы
- [ ] Тесты добавлены

## Уроки

[Ключевые выводы для будущего]
```

## Обновление инструкций и навыков

После RCA ОБЯЗАТЕЛЬНО оценить:

### 1. Нужно ли обновить CLAUDE.md?
- Добавить новое правило/предостережение
- Обновить существующий раздел
- Добавить пример ошибки

### 2. Нужно ли обновить MEMORY.md?
- Зафиксировать конфигурацию
- Добавить в Common Pitfalls
- Обновить Debug Commands

### 3. Нужно ли создать новый навык?
- Если ошибка повторяющаяся
- Если нужен специальный процесс
- Если полезно для других ситуаций

### 4. Нужно ли обновить существующий навык?
- Добавить предупреждение
- Расширить чеклист
- Добавить пример

## Интеграция с рабочим процессом

### Автоматический триггер

При ЛЮБОЙ ошибке в процессе работы:

1. **СТОП** — не продолжать до RCA
2. Провести анализ "5 почему"
3. Зафиксировать в `docs/rca/`
4. Оценить необходимость обновления инструкций
5. Применить корректировки
6. Продолжить работу

### Примеры ошибок для RCA

| Тип ошибки | Пример |
|------------|--------|
| Код | TypeError, null reference, crash |
| Процесс | Пропущен шаг в workflow |
| Конфигурация | Неверные настройки, не тот env |
| Коммуникация | Неправильно понят запрос |
| Рассуждение | Логическая ошибка в выводе |
| Планирование | Нереалистичная оценка |

## Связанные навыки

- **systematic-debugging** — техническая отладка
- **rollback-changes** — откат изменений при ошибке
- **format-commit-message** — коммиты с контекстом

## Быстрая справка

```
Ошибка → СТОП → 5 Почему → Фиксация → Обновление → Продолжение
```

**Помни:** Каждая ошибка — это возможность улучшить систему, а не просто исправить симптом.

---

## 🔄 Auto-Context Collection

**При любой ошибке автоматически собирать контекст:**

### Запуск сбора контекста

```bash
# Вызвать скрипт сбора контекста
bash .claude/skills/rca-5-whys/lib/context-collector.sh <error_type>
```

### Типы ошибок для определения контекста

| Error Type | Дополнительный контекст |
|------------|------------------------|
| `docker` | docker version, containers, networks, volumes |
| `cicd` | workflow name, job, step, runner info |
| `shell` | shell version, environment variables |
| `data-loss` | backup status, disk space |
| `generic` | базовый контекст только |

### Формат контекста в RCA отчёте

```markdown
## Context

| Field | Value |
|-------|-------|
| Timestamp | [ISO datetime] |
| PWD | [working directory] |
| Git Branch | [branch or N/A] |
| Git Status | [short status] |
| Docker Version | [version or N/A] |
| Disk Usage | [percentage] |
| Memory | [used/total] |
| Error Type | [detected type] |
```

---

## 📋 Domain-Specific Templates

**Автоматический выбор шаблона по типу ошибки:**

### Template Selection Logic

```
Error contains "docker|container|image|volume|network" → docker.md
Error contains "workflow|pipeline|github actions|ci" → cicd.md
Error contains "data loss|deleted|corrupted|backup" → data-loss.md
Default → generic.md
```

### Templates Location

```
.claude/skills/rca-5-whys/templates/
├── docker.md      # Layer Analysis: Image → Container → Network → Volume → Runtime
├── cicd.md        # Pipeline Analysis: Workflow → Job → Step → Action
├── data-loss.md   # Critical Protocol: STOP → SNAPSHOT → ASSESS → RESTORE → ANALYZE
└── generic.md     # Standard 5-Why
```

### Использование шаблона

1. Определить тип ошибки (pattern matching)
2. Прочитать соответствующий шаблон из templates/
3. Применить структуру из шаблона к RCA анализу

---

## 📊 RCA Index

**Реестр всех RCA отчётов:**

### Location

`docs/rca/INDEX.md`

### Structure

```markdown
# RCA Index

## Statistics
- Total RCA: N
- By Category: docker (X), cicd (Y), ...
- Avg Resolution Time: Xm

## Registry
| ID | Date | Category | Severity | Status | Root Cause | Fix |
|----|------|----------|----------|--------|------------|-----|
| RCA-001 | 2026-03-03 | docker | P1 | ✅ | ... | abc123 |

## Patterns Detected
⚠️ 3+ RCA in "docker" - consider systemic fix
```

### Управление INDEX

```bash
# Обновить INDEX после создания RCA
bash .claude/skills/rca-5-whys/lib/rca-index.sh update

# Получить следующий ID
bash .claude/skills/rca-5-whys/lib/rca-index.sh next-id

# Валидировать INDEX
bash .claude/skills/rca-5-whys/lib/rca-index.sh validate
```

---

## 🧠 Chain-of-Thought Pattern

**Структурированные рассуждения для повышения точности RCA:**

### Step 1: Error Classification

```
Error Type: [infra | code | config | process | communication]
Confidence: [high | medium | low]
Context Quality: [sufficient | partial | insufficient]
```

### Step 2: Hypothesis Generation

```
H1: [наиболее вероятная причина] (confidence: X%)
H2: [вторая причина] (confidence: Y%)
H3: [третья причина] (confidence: Z%)
```

### Step 3: 5 Whys with Evidence

```
Q1: Почему [ошибка]? → A1 (evidence: [источник])
Q2: Почему [A1]? → A2 (evidence: [источник])
Q3: Почему [A2]? → A3 (evidence: [источник])
Q4: Почему [A3]? → A4 (evidence: [источник])
Q5: Почему [A4]? → A5 (evidence: [источник])
```

### Step 4: Root Cause Validation

```
□ Actionable? [yes/no] - Можно ли исправить?
□ Systemic? [yes/no] - Это системная проблема?
□ Preventable? [yes/no] - Можно ли предотвратить в будущем?
```

---

## 🧪 Test Generation

**Автоматическое создание regression тестов для code-ошибок:**

### Когда создавать тест

- Тип ошибки: `code`
- RCA завершён
- Корневая причина найдена

### Test Template (Vitest/TypeScript)

```typescript
describe('RCA-[ID]: [Short Description]', () => {
  it('should [expected behavior]', async () => {
    // Given: [setup from RCA context]
    // When: [action that caused error]
    // Then: [expected outcome, not error]
  });
});
```

### Test Location

```
tests/rca/RCA-NNN.test.ts
```

### Workflow

1. RCA завершён для code-ошибки
2. Предложить создать failing test
3. Если пользователь согласен — создать тест
4. Тест должен падать (failing test)
5. После fix — тест должен проходить

---

## 📁 File Structure

```
.claude/skills/rca-5-whys/
├── SKILL.md              # Этот файл
├── templates/
│   ├── docker.md         # Docker-specific RCA
│   ├── cicd.md           # CI/CD-specific RCA
│   ├── data-loss.md      # Critical data loss protocol
│   └── generic.md        # Generic 5-Why
└── lib/
    ├── context-collector.sh  # Auto-context collection
    └── rca-index.sh          # INDEX.md management

docs/rca/
├── INDEX.md              # RCA registry
├── TEMPLATE.md           # Report template
└── YYYY-MM-DD-*.md       # RCA reports

tests/rca/
└── RCA-NNN.test.ts       # Generated regression tests
```
