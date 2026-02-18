# Agent Factory: Полный Lifecycle создания агента

**Date**: 2026-02-17
**Status**: Supporting Artifact
**Parent Plan**: [parallel-doodling-coral.md](./parallel-doodling-coral.md)

---

## Context

Это дополнение к основному плану трансформации Moltinger. Описывает **полный lifecycle создания AI агента** по методологии ASC, от спецификации до передачи в продакшен.

### Ключевые принципы ASC

1. **AGENT_DEVELOPMENT_PATTERN** - 5 фаз создания агента
2. **Независимая валидация** - отдельный агент проверяет spec vs code
3. **Рекурсивная самоприменимость** - фабрика использует свои же методы

---

## Полный Lifecycle агента

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    AGENT DEVELOPMENT LIFECYCLE                          │
│                    (AGENT_DEVELOPMENT_PATTERN)                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐             │
│  │   PHASE 1    │───►│   PHASE 2    │───►│   PHASE 3    │             │
│  │ Требования   │    │ Архитектура  │    │   Создание   │             │
│  │   (Spec)     │    │  (Design)    │    │   (Code)     │             │
│  └──────────────┘    └──────────────┘    └──────────────┘             │
│         │                   │                   │                      │
│         │                   │                   │                      │
│         ▼                   ▼                   ▼                      │
│  ┌──────────────────────────────────────────────────────────┐         │
│  │              НЕЗАВИСИМАЯ ВАЛИДАЦИЯ                         │         │
│  │              (Агент-валидатор)                             │         │
│  │   Проверка: Spec ↔ Architecture ↔ Code                     │         │
│  └──────────────────────────────────────────────────────────┘         │
│         │                                                              │
│         │ [FAIL] ────────────────────────────────────────┐            │
│         │                                                │            │
│         │ [PASS]                                         │            │
│         ▼                                                ▼            │
│  ┌──────────────┐                                ┌──────────────┐     │
│  │   PHASE 4    │                                │  ПЕРЕДЕЛКА   │     │
│  │  Тестирование│                                │  (Feedback   │     │
│  │  + UAT       │◄───────────────────────────────│   Loop)      │     │
│  └──────────────┘                                └──────────────┘     │
│         │                                                              │
│         │ [UAT FAIL] ──────────────────────────────────┐              │
│         │                                              │              │
│         │ [UAT PASS]                                   │              │
│         ▼                                              │              │
│  ┌──────────────┐                                      │              │
│  │   PHASE 5    │                                      │              │
│  │ Валидация +  │                                      │              │
│  │ Развертывание│                                      │              │
│  └──────────────┘                                      │              │
│         │                                              │              │
│         ▼                                              │              │
│  ┌──────────────────────────────────────────┐         │              │
│  │         DOCKER ПАКЕТИРОВАНИЕ              │         │              │
│  │         (Containerization)                │         │              │
│  └──────────────────────────────────────────┘         │              │
│         │                                              │              │
│         ▼                                              │              │
│  ┌──────────────────────────────────────────┐         │              │
│  │      ПЕРЕДАЧА КОМАНДЕ (Handover)          │◄────────┘              │
│  │      → Промышленный контур                │                        │
│  └──────────────────────────────────────────┘                        │
│                                                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Определение требований (Spec)

**Ответственный**: Moltinger (AI Agent Factory)

### Входные данные
- Описание бизнес-проблемы от пользователя
- Контекст бизнес-процесса
- Ограничения (время, ресурсы, compliance)

### Задачи
1. Анализ бизнес-процесса
2. Определение функций агента
3. Определение ограничений
4. Формирование метрик успеха

### Результаты
- `spec.md` - Спецификация агента
- `requirements.json` - Формализованные требования

### Шаблон spec.md

```markdown
# Agent Specification: [NAME]

## Overview
- **Name**: [название]
- **Version**: 0.1.0
- **Purpose**: [цель]
- **Owner**: Сергей
- **Created**: [дата]

## Business Context
- **Problem**: [описание проблемы]
- **Users**: [целевые пользователи]
- **Process**: [бизнес-процесс для оптимизации]

## Goals & Success Metrics
| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| [метрика 1] | [цель] | [как измерить] |
| [метрика 2] | [цель] | [как измерить] |

## Metablock Mapping
| Metablock | Usage | Priority |
|-----------|-------|----------|
| RESEARCH_FRAMEWORK | [как используется] | P1/P2/P3 |
| ARCHITECTURE | [как используется] | P1/P2/P3 |
| DEVELOPMENT | [как используется] | P1/P2/P3 |
| TESTING | [как используется] | P1/P2/P3 |

## Capabilities
- **Capability 1**: [описание]
- **Capability 2**: [описание]

## Inputs & Outputs
### Inputs
| Input | Type | Format | Source |
|-------|------|--------|--------|
| [вход 1] | [тип] | [формат] | [источник] |

### Outputs
| Output | Type | Format | Destination |
|--------|------|--------|-------------|
| [выход 1] | [тип] | [формат] | [назначение] |

## Constraints
- **Technical**: [ограничения]
- **Business**: [ограничения]
- **Compliance**: [требования соответствия]

## Implementation Phases
### Phase 1 (MVP0 - 4 недели)
- [ ] [задача 1]
- [ ] [задача 2]

### Phase 2 (Scaling - 3-6 месяцев)
- [ ] [задача]

### Phase 3 (Autonomous)
- [ ] [задача]
```

---

## Phase 2: Проектирование архитектуры

**Ответственный**: Moltinger (Agent Architect)

### Входные данные
- `spec.md` из Phase 1

### Задачи
1. Выбор архитектурных паттернов
2. Проектирование взаимодействия компонентов
3. Планирование безопасности
4. Документирование архитектуры

### Результаты
- `architecture.md` - Архитектура агента
- `security-plan.md` - План безопасности

### Шаблон architecture.md

```markdown
# Agent Architecture: [NAME]

## System Overview
[Диаграмма высокого уровня]

## Components
### Component 1: [название]
- **Purpose**: [назначение]
- **Technology**: [технология]
- **Interfaces**: [интерфейсы]

### Component 2: [название]
...

## Data Flow
[Диаграмма потоков данных]

## Security Architecture
- **Authentication**: [метод]
- **Authorization**: [метод]
- **Data Protection**: [метод]
- **Audit**: [метод]

## Integration Points
| System | Protocol | Data Format |
|--------|----------|-------------|
| [система 1] | [протокол] | [формат] |

## Technology Stack
- **Runtime**: [Node.js/Python/Go]
- **Framework**: [фреймворк]
- **LLM**: [модель]
- **Database**: [база данных]
```

---

## Phase 3: Создание агента (Code)

**Ответственный**: Moltinger (Agent Developer) + ИИ-инструменты

### Входные данные
- `spec.md` из Phase 1
- `architecture.md` из Phase 2

### Задачи
1. Генерация кода агента
2. Реализация функций
3. Интеграция с внешними системами
4. Создание конфигурации

### Результаты
- `/agents/[agent-name]/src/` - Исходный код
- `/agents/[agent-name]/config/` - Конфигурация
- `/agents/[agent-name]/tests/` - Тесты

---

## Phase 3.5: Независимая валидация ⚠️ КРИТИЧНО

**Ответственный**: **Агент-валидатор** (отдельный от разработчика)

### Принцип независимости
> Агент-валидатор НЕ участвовал в создании агента. Он проверяет соответствие **Spec ↔ Code**.

### Входные данные
- `spec.md` (требования)
- `architecture.md` (дизайн)
- Исходный код агента

### Задачи валидатора

```
1. Парсинг spec.md → извлечение требований
2. Анализ кода → извлечение реализованных функций
3. Сравнение Spec ↔ Code:
   - [ ] Все требования реализованы?
   - [ ] Нет лишнего функционала?
   - [ ] Архитектура соответствует дизайну?
4. Проверка качества:
   - [ ] Код стайл
   - [ ] Безопасность
   - [ ] Производительность
5. Генерация отчёта валидации
```

### Результаты
- `validation-report.md`

### Шаблон validation-report.md

```markdown
# Validation Report: [AGENT NAME]

**Validator**: Agent-Validator v1.0
**Date**: [дата]
**Status**: [PASS/FAIL]

## Summary
| Category | Status | Issues |
|----------|--------|--------|
| Requirements | ✅/❌ | [count] |
| Architecture | ✅/❌ | [count] |
| Code Quality | ✅/❌ | [count] |
| Security | ✅/❌ | [count] |

## Detailed Findings

### Requirements Coverage
| Requirement | Status | Notes |
|-------------|--------|-------|
| [req 1] | ✅ Implemented | |
| [req 2] | ❌ Missing | [описание проблемы] |
| [req 3] | ⚠️ Partial | [описание] |

### Issues Found
1. **[CRITICAL]** [описание]
2. **[HIGH]** [описание]
3. **[MEDIUM]** [описание]

### Recommendations
1. [рекомендация 1]
2. [рекомендация 2]

## Decision
- [ ] **PASS** - Продолжить к Phase 4
- [ ] **FAIL** - Вернуть на переделку (указать причины)
```

### Если FAIL → Feedback Loop

```
Validation FAIL
      │
      ▼
┌──────────────────┐
│  Создать tasks   │
│  для исправления │
└──────────────────┘
      │
      ▼
┌──────────────────┐
│  Вернуть в       │
│  Phase 3 (Code)  │
└──────────────────┘
      │
      ▼
Повторная валидация
```

---

## Phase 4: Тестирование + UAT

**Ответственный**: Moltinger (Agent Tester) + Бизнес-пользователи

### 4.1 Unit & Integration Tests

```bash
# Автоматические тесты
pytest /agents/[agent-name]/tests/
```

### 4.2 UAT (User Acceptance Testing)

**Участники**: Бизнес-пользователи (не разработчики)

**Сценарии UAT**:
1. Основной сценарий использования
2. Граничные случаи
3. Обработка ошибок
4. Производительность

### Шаблон UAT Report

```markdown
# UAT Report: [AGENT NAME]

**Testers**: [имена]
**Date**: [дата]
**Environment**: [среда]

## Test Scenarios

| # | Scenario | Expected | Actual | Status |
|---|----------|----------|--------|--------|
| 1 | [сценарий] | [ожидание] | [результат] | ✅/❌ |
| 2 | ... | ... | ... | ... |

## Issues Found
1. [описание проблемы]
2. [описание проблемы]

## User Feedback
> "Цитата от пользователя"

## Decision
- [ ] **PASS** - Продолжить к Phase 5
- [ ] **FAIL** - Вернуть на доработку
```

### Если UAT FAIL → Feedback Loop

```
UAT FAIL
    │
    ▼
Анализ проблем
    │
    ├──► Bug fixes → Phase 3.5 (Re-validation)
    │
    └──► Design changes → Phase 2 (Re-design)
```

---

## Phase 5: Валидация + Развертывание

**Ответственный**: Moltinger (Agent Deployer)

### 5.1 Финальная валидация

- [ ] Все тесты проходят
- [ ] UAT пройден
- [ ] Security review
- [ ] Performance baseline

### 5.2 Docker Пакетирование

```dockerfile
# Dockerfile для агента
FROM [base-image]

WORKDIR /app
COPY src/ ./src/
COPY config/ ./config/
COPY requirements.txt .

RUN pip install -r requirements.txt

EXPOSE [port]

CMD ["python", "src/main.py"]
```

### 5.3 Результаты

```
/agents/[agent-name]/
├── Dockerfile
├── docker-compose.yml
├── src/
├── config/
├── tests/
├── spec.md
├── architecture.md
├── validation-report.md
├── uat-report.md
└── README.md
```

---

## Phase 6: Передача (Handover)

**От**: Команда разработки (Moltinger)
**Кому**: Команда промышленного контура

### Artefacts для передачи

| Артефакт | Назначение |
|----------|------------|
| `spec.md` | Требования |
| `architecture.md` | Архитектура |
| `src/` | Исходный код |
| `Dockerfile` | Контейнеризация |
| `docker-compose.yml` | Оркестрация |
| `validation-report.md` | Результаты валидации |
| `uat-report.md` | Результаты UAT |
| `README.md` | Документация |
| `runbook.md` | Инструкции по эксплуатации |

### Checklist для передачи

```
[ ] Код валидирован (независимый валидатор)
[ ] UAT пройден
[ ] Docker образ собран
[ ] Документация полная
[ ] Мониторинг настроен
[ ] Runbook создан
[ ] Knowledge transfer проведён
```

---

## Roles & Responsibilities

| Роль | Когда активна | Ответственность |
|------|---------------|-----------------|
| **Moltinger (Spec Generator)** | Phase 1 | Создание спецификации |
| **Moltinger (Architect)** | Phase 2 | Проектирование архитектуры |
| **Moltinger (Developer)** | Phase 3 | Генерация кода |
| **Agent-Validator** | Phase 3.5 | Независимая валидация |
| **Moltinger (Tester)** | Phase 4 | Тестирование |
| **Business Users** | Phase 4 (UAT) | Приёмочное тестирование |
| **Moltinger (Deployer)** | Phase 5 | Пакетирование и деплой |
| **Production Team** | Phase 6 | Развертывание в прод |

---

## Feedback Loops

```
                    ┌─────────────────────────┐
                    │    FEEDBACK LOOPS       │
                    └─────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
   Validation Fail       UAT Fail            Production Issue
        │                     │                     │
        ▼                     ▼                     ▼
   Return to Phase 3    Return to Phase 3    Incident Response
   (Code Fix)          (Code/Design Fix)    (Hotfix Process)
```

---

## Summary

**Полный lifecycle создания агента**:

| Phase | Deliverable | Validator |
|-------|-------------|-----------|
| 1. Requirements | spec.md | Moltinger |
| 2. Architecture | architecture.md | Moltinger |
| 3. Creation | src/, config/ | — |
| 3.5. Validation | validation-report.md | **Agent-Validator** (независимый) |
| 4. Testing + UAT | uat-report.md | Business Users |
| 5. Deployment | Dockerfile, docker-compose.yml | Moltinger |
| 6. Handover | Full package | Production Team |

**Ключевые принципы**:
1. **Независимая валидация** - отдельный агент проверяет Spec ↔ Code
2. **UAT** - бизнес-пользователи принимают финальное решение
3. **Feedback loops** - возможность вернуться на любой этап
4. **Docker пакетирование** - стандартизированная доставка
5. **Передача** - формальный handover команде продакшена
