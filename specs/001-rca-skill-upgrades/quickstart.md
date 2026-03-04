# Quickstart: RCA Skill Enhancements

**Feature**: 001-rca-skill-upgrades
**Date**: 2026-03-03

## Обзор

Навык RCA (Root Cause Analysis) "5 Почему" с улучшениями:
- 🔄 **Auto-Context** — автоматический сбор контекста при ошибках
- 📋 **Domain Templates** — специализированные шаблоны для Docker, CI/CD, Data Loss
- 🧠 **Chain-of-Thought** — структурированные рассуждения с гипотезами
- 📊 **RCA Index** — реестр всех RCA с аналитикой
- 🧪 **Test Generation** — автоматическое создание regression тестов

---

## Быстрый старт

### 1. Базовое использование

При любой ошибке (exit code != 0), LLM автоматически запускает RCA:

```
❌ ОШИБКА: docker: Error response from daemon

🤖 RCA АНАЛИЗ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 AUTO-CONTEXT COLLECTION
Timestamp: 2026-03-03T12:34:56+03:00
PWD: /Users/user/project
Git Branch: feature-xyz
Docker Version: 24.0.5
...

📝 Вопрос 1: Почему контейнер не запустился?
   → Ошибка сети: контейнер не может подключиться к traefik-net
...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 2. Ручной запуск

```bash
/rca-5-whys
```

### 3. Просмотр RCA Index

```bash
cat docs/rca/INDEX.md
```

---

## Типы ошибок и шаблоны

### Docker Errors

**Триггеры**: `docker`, `container`, `image`, `volume`, `network`

**Шаблон**: Layer Analysis
```
Image → Container → Network → Volume → Runtime
```

**Пример**:
```
❌ docker: Error response from daemon: network traefik-net not found

🤖 DOCKER RCA TEMPLATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
| Layer    | Check                    | Status |
|----------|--------------------------|--------|
| Image    | Exists? Built?           | ✅     |
| Container| Running? Health check?   | ✅     |
| Network  | Connected? DNS resolves? | ❌     |
| Volume   | Mounted? Permissions?    | ❓     |
| Runtime  | OOM? CPU throttled?      | ❓     |

📝 5 Whys:
1. Почему сеть не найдена? → Сеть traefik-net не существует
2. Почему не существует? → Не была создана при деплое
3. Почему не создана? → docker-compose.yml не описывает сеть
...
```

### CI/CD Errors

**Триггеры**: `workflow`, `pipeline`, `github actions`, `ci`, `job failed`

**Шаблон**: Pipeline Analysis
```
Workflow → Job → Step → Action
```

### Data Loss Errors

**Триггеры**: `data loss`, `deleted`, `corrupted`, `backup failed`

**Шаблон**: Critical Protocol
```
🚨 CRITICAL: STOP → SNAPSHOT → ASSESS → RESTORE → ANALYZE
```

### Generic Errors

**Триггеры**: Все остальные ошибки

**Шаблон**: Standard 5-Why

---

## Chain-of-Thought процесс

### 1. Error Classification
```
Error Type: infra | code | config | process | communication
Confidence: high | medium | low
Context Quality: sufficient | partial | insufficient
```

### 2. Hypothesis Generation
```
H1: Network misconfiguration (confidence: 70%)
H2: Container resource limits (confidence: 20%)
H3: Image incompatibility (confidence: 10%)
```

### 3. 5 Whys with Evidence
```
Q1: Почему сеть недоступна?
A1: Traefik не может резолвить DNS (evidence: docker logs)
...
```

### 4. Root Cause Validation
```
Actionable: ✅ yes - can add network label
Systemic: ✅ yes - affects all containers
Preventable: ✅ yes - add preflight check
```

---

## Test Generation

Для code-ошибок автоматически предлагается создать тест:

```
🤖 Would you like to create a regression test?

File: tests/rca/RCA-001.test.ts

describe('RCA-001: Network configuration', () => {
  it('should connect container to correct network', async () => {
    // Given: Container with network config
    // When: Container starts
    // Then: Network connectivity verified
  });
});
```

---

## RCA Index

### Структура

```markdown
# RCA Registry

## Statistics
- Total RCA: 5
- By Category: docker (3), cicd (1), shell (1)
- Avg Resolution: 15 min

## Registry
| ID | Date | Category | Severity | Status | Root Cause | Fix |
|----|------|----------|----------|--------|------------|-----|
| RCA-001 | 2026-03-03 | docker | P1 | ✅ | Wrong network | abc123 |

## Patterns Detected
⚠️ 3+ RCA in "docker" - consider systemic fix
```

### Обновление

INDEX.md обновляется автоматически при создании нового RCA.

---

## Файловая структура

```
.claude/skills/rca-5-whys/
├── SKILL.md                 # Главный файл навыка
├── templates/
│   ├── docker.md            # Docker template
│   ├── cicd.md              # CI/CD template
│   ├── data-loss.md         # Critical protocol
│   └── generic.md           # Generic template
└── lib/
    ├── context-collector.sh # Сбор контекста
    └── rca-index.sh         # Управление INDEX

docs/rca/
├── INDEX.md                 # Реестр
├── TEMPLATE.md              # Шаблон отчёта
└── YYYY-MM-DD-*.md          # RCA отчёты

tests/rca/
└── RCA-NNN.test.ts          # Regression тесты
```

---

## Интеграция с systematic-debugging

RCA автоматически интегрируется с `systematic-debugging` skill:

```
Ошибка → systematic-debugging → RCA "5 Почему" → Фиксация → Продолжение
```

---

## Команды

| Команда | Описание |
|---------|----------|
| `/rca-5-whys` | Запустить RCA анализ |
| `cat docs/rca/INDEX.md` | Просмотр реестра |
| `cat docs/rca/YYYY-MM-DD-*.md` | Просмотр конкретного RCA |

---

## Troubleshooting

### Q: RCA не запускается автоматически
**A**: Проверьте, что в CLAUDE.md есть раздел `⛔ CRITICAL: RCA при ЛЮБОМ exit code != 0`

### Q: Контекст не собирается
**A**: Проверьте права доступа sandbox. Некоторые команды могут требовать `dangerouslyDisableSandbox`

### Q: INDEX.md не обновляется
**A**: Запустите `.claude/skills/rca-5-whys/lib/rca-index.sh update`
