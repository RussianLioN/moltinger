# Feature Specification: RCA Skill Enhancements

**Feature Branch**: `001-rca-skill-upgrades`
**Created**: 2026-03-03
**Status**: Draft
**Input**: User description: "RCA Skill Enhancements based on expert consilium recommendations: Hub Architecture, Auto-Context Collection, Domain-Specific Templates, Chain-of-Thought Pattern, Test Generation"

## Executive Summary

Улучшение навыка Root Cause Analysis (RCA) "5 Почему" на основе рекомендаций консилиума из 13 экспертов. Навык трансформируется из изолированного инструмента в **центральный узел системы анализа ошибок** с автоматическим сбором контекста, доменно-специфичными шаблонами, структурой рассуждений и генерацией тестов.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Автоматический анализ ошибки с контекстом (Priority: P1)

**Как** LLM-ассистент или разработчик
**Я хочу** чтобы при любой ошибке автоматически собирался контекст (git, docker, environment)
**Чтобы** сократить время диагностики и повысить качество RCA

**Why this priority**: Это ядро улучшения — без автоматического контекста RCA остаётся ручным процессом. P1 потому что влияет на 100% случаев использования.

**Independent Test**:
1. Спровоцировать ошибку (например, `cat /nonexistent`)
2. Проверить, что LLM автоматически собрал контекст (pwd, git branch, disk space, memory)
3. Проверить, что RCA отчёт содержит собранный контекст

**Acceptance Scenarios**:

1. **Given** любая команда с exit code != 0, **When** LLM начинает RCA, **Then** автоматически выполняется сбор контекста (timestamp, pwd, git status, docker info, disk, memory)
2. **Given** контекст собран, **When** формируется RCA отчёт, **Then** контекст включается в раздел "Environment Context"
3. **Given** Docker-ошибка, **When** собирается контекст, **Then** дополнительно проверяются: container status, network connectivity, volume mounts

---

### User Story 2 - Доменно-специфичные шаблоны RCA (Priority: P1)

**Как** DevOps-инженер или SRE
**Я хочу** чтобы RCA автоматически использовал подходящий шаблон в зависимости от типа ошибки
**Чтобы** анализ был глубже и учитывал специфику домена (Docker, CI/CD, Data Loss)

**Why this priority**: Разные типы ошибок требуют разных подходов. Docker-ошибки анализируются иначе чем shell-ошибки. P1 потому что критично для качества анализа.

**Independent Test**:
1. Спровоцировать Docker-ошибку (container not found)
2. Проверить, что использовался Docker-specific template с layer analysis
3. Спровоцировать CI/CD-ошибку
4. Проверить, что использовался CI/CD-specific template

**Acceptance Scenarios**:

1. **Given** ошибка связана с Docker (container, network, volume), **When** начинается RCA, **Then** используется Docker template с проверкой слоёв: Image → Container → Network → Volume → Runtime
2. **Given** ошибка связана с CI/CD (pipeline failure), **When** начинается RCA, **Then** используется CI/CD template с анализом: Workflow → Job → Step → Action
3. **Given** ошибка связана с data loss, **When** начинается RCA, **Then** используется Critical Protocol: STOP → SNAPSHOT → ASSESS → RESTORE → ANALYZE
4. **Given** тип ошибки не определён, **When** начинается RCA, **Then** используется generic template с 5 Why

---

### User Story 3 - RCA Hub Architecture с индексом (Priority: P2)

**Как** технический лид или SRE
**Я хочу** видеть индекс всех RCA с метриками и трендами
**Чтобы** выявлять системные паттерны и предотвращать повторяющиеся ошибки

**Why this priority**: Это стратегическое улучшение для долгосрочной аналитики. P2 потому что можно использовать навык без индекса, но индекс значительно повышает ценность.

**Independent Test**:
1. Создать несколько RCA отчётов
2. Открыть docs/rca/INDEX.md
3. Проверить, что все RCA отражены с метаданными
4. Проверить, что статистика корректна

**Acceptance Scenarios**:

1. **Given** создан RCA отчёт, **When** отчёт сохраняется, **Then** INDEX.md автоматически обновляется с новой записью
2. **Given** INDEX.md существует, **When** пользователь открывает его, **Then** видит таблицу: ID, Date, Category, Severity, Status, Root Cause, Fix
3. **Given** INDEX.md существует, **When** пользователь смотрит Statistics, **Then** видит: Total RCA, By Category, By Severity, Avg Resolution Time
4. **Given** более 3 RCA в одной категории, **When** формируется INDEX.md, **Then** показывается предупреждение о паттерне

---

### User Story 4 - Chain-of-Thought RCA с валидацией (Priority: P2)

**Как** LLM-ассистент
**Я хочу** структурированный процесс RCA с генерацией гипотез и валидацией
**Чтобы** повысить точность нахождения корневой причины

**Why this priority**: Улучшает качество рассуждений LLM. P2 потому что базовый "5 Why" работает, но CoT повышает точность.

**Independent Test**:
1. Спровоцировать нетривиальную ошибку
2. Проверить, что RCA включает: Error Classification → Hypothesis Generation → Evidence Gathering → 5 Whys with Evidence → Root Cause Validation
3. Проверить, что каждая гипотеза имеет confidence level

**Acceptance Scenarios**:

1. **Given** ошибка обнаружена, **When** начинается RCA, **Then** сначала определяется Error Type (infra | code | config | process | communication) и Confidence level
2. **Given** тип ошибки определён, **When** формируется анализ, **Then** генерируются 3 гипотезы с confidence levels
3. **Given** гипотезы сгенерированы, **When** проводится 5 Whys, **Then** каждый ответ включает evidence source
4. **Given** корневая причина найдена, **When** проводится валидация, **Then** проверяется: actionable? systemic? preventable?

---

### User Story 5 - Автоматическая генерация тестов из RCA (Priority: P3)

**Как** разработчик
**Я хочу** чтобы RCA автоматически создавал failing test для обнаруженной ошибки
**Чтобы** гарантировать что ошибка не повторится (regression test)

**Why this priority**: Это "quality gate" для предотвращения регрессий. P3 потому что требует интеграции с тестовой инфраструктурой.

**Independent Test**:
1. Провести RCA для бага в коде
2. Проверить, что создан тестовый файл tests/rca/RCA-001.test.ts
3. Запустить тест — он должен падать (failing test)
4. Исправить баг
5. Запустить тест — он должен проходить

**Acceptance Scenarios**:

1. **Given** RCA завершён для code-ошибки, **When** формируется отчёт, **Then** предлагается создать failing test
2. **Given** пользователь подтвердил создание теста, **When** тест создаётся, **Then** используется шаблон: Given/When/Then из RCA контекста
3. **Given** тест создан, **When** выполняется fix, **Then** тест должен переходить из failing → passing
4. **Given** тест проходит, **When** завершается сессия, **Then** тест добавляется в CI/CD pipeline

---

### Edge Cases

- **Что если ошибка в самом RCA процессе?** → Запускается meta-RCA для анализа ошибки анализа
- **Что если тип ошибки не удаётся классифицировать?** → Используется generic template с ручным выбором категории
- **Что если контекст не удаётся собрать (нет git, нет docker)?** → Пропустить недоступные проверки, отметить в отчёте
- **Что если RCA-INDEX.md конфликтует при merge?** → Автоматический merge с сохранением обеих записей
- **Что если гипотеза подтверждается на 100% до 5-го Why?** → Можно остановиться раньше, документировать причину ранней остановки

---

## Requirements *(mandatory)*

### Functional Requirements

#### Auto-Context Collection

- **FR-001**: Система ДОЛЖНА автоматически собирать контекст при любой ошибке (exit code != 0)
- **FR-002**: Контекст ДОЛЖЕН включать: timestamp, pwd, git branch, git status, disk usage, memory usage
- **FR-003**: Для Docker-ошибок контекст ДОЛЖЕН включать: docker version, container status, network info
- **FR-004**: Для CI/CD-ошибок контекст ДОЛЖЕН включать: workflow name, job name, step name
- **FR-005**: Собранный контекст ДОЛЖЕН быть включён в RCA отчёт

#### Domain-Specific Templates

- **FR-006**: Система ДОЛЖНА определять тип ошибки: docker, cicd, shell, data-loss, generic
- **FR-007**: Для Docker-ошибок ДОЛЖЕН использоваться Layer Analysis template (Image → Container → Network → Volume → Runtime)
- **FR-008**: Для Data Loss ошибок ДОЛЖЕН использоваться Critical Protocol (STOP → SNAPSHOT → ASSESS → RESTORE → ANALYZE)
- **FR-009**: Для CI/CD-ошибок ДОЛЖЕН использоваться Pipeline Analysis template
- **FR-010**: Для неопределённых ошибок ДОЛЖЕН использоваться Generic 5-Why template

#### RCA Hub Architecture

- **FR-011**: Система ДОЛЖНА поддерживать единый формат RCA (JSON schema + Markdown)
- **FR-012**: Каждый RCA отчёт ДОЛЖЕН иметь уникальный ID (RCA-NNN)
- **FR-013**: Система ДОЛЖНА поддерживать связи между RCA: related-to, caused-by, fixed-by
- **FR-014**: Система ДОЛЖНА поддерживать INDEX.md с реестром всех RCA
- **FR-015**: INDEX.md ДОЛЖЕН содержать статистику: Total, By Category, By Severity, Trends

#### Chain-of-Thought Pattern

- **FR-016**: RCA процесс ДОЛЖЕН начинаться с Error Classification (type, confidence, context quality)
- **FR-017**: Система ДОЛЖНА генерировать минимум 3 гипотезы с confidence levels
- **FR-018**: Каждый ответ в 5-Whys ДОЛЖЕН включать evidence source
- **FR-019**: После нахождения root cause ДОЛЖНА проводиться валидация (actionable, systemic, preventable)

#### Test Generation

- **FR-020**: Для code-ошибок система ДОЛЖНА предлагать создание failing test
- **FR-021**: Тест ДОЛЖЕН использовать Given/When/Then структуру из RCA контекста
- **FR-022**: Тест ДОЛЖЕН находиться в директории tests/rca/
- **FR-023**: Имя файла ДОЛЖНО соответствовать RCA ID (RCA-001.test.ts)

#### Integration

- **FR-024**: RCA навык ДОЛЖЕН интегрироваться с существующим systematic-debugging skill
- **FR-025**: RCA ДОЛЖЕН использовать Claude Code tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
- **FR-026**: RCA ДОЛЖЕН поддерживать MCP tools для расширенного анализа (supabase, context7)

### Key Entities

- **RCA Report**: Документ анализа ошибки, содержит Error, 5-Whys, Root Cause, Actions, Context
- **RCA Index**: Реестр всех RCA с метаданными и статистикой
- **RCA Template**: Доменно-специфичный шаблон для анализа (Docker, CI/CD, Data Loss, Generic)
- **RCA Context**: Собранные данные окружения (git, docker, system)
- **RCA Hypothesis**: Предположение о причине ошибки с confidence level и evidence
- **RCA Test**: Regression test созданный из RCA для предотвращения повторения

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Время от обнаружения ошибки до начала RCA сокращается до < 5 секунд (автоматический контекст)
- **SC-002**: 90% RCA отчётов содержат полный контекст окружения без ручного ввода
- **SC-003**: Качество RCA (измеряется по наличию systemic root cause) улучшается на 40% благодаря CoT pattern
- **SC-004**: 80% Docker-ошибок анализируются с использованием domain-specific template
- **SC-005**: RCA Index позволяет найти связанный RCA за < 10 секунд
- **SC-006**: 100% code-ошибок имеют предложение создать regression test
- **SC-007**: Повторяемость ошибок снижается на 50% благодаря тестам из RCA

### Quality Metrics

- **QM-001**: Все RCA отчёты следуют единому формату (JSON schema validation)
- **QM-002**: Каждый RCA имеет минимум 5 уровней "Почему" или обоснование ранней остановки
- **QM-003**: Корневая причина является systemic (не "разработчик ошибся")
- **QM-004**: Каждый RCA содержит конкретные действия (fix, prevent, document)

---

## Assumptions

- Проект использует git для версионирования
- LLM имеет доступ к Bash для сбора контекста
- Директория docs/rca/ существует или может быть создана
- Пользователь готов тратить время на качественный RCA (не skip)
- Тестовая инфраструктура поддерживает TypeScript/Vitest (для генерации тестов)

---

## Dependencies

- Существующий навык `rca-5-whys` (базовая версия)
- Навык `systematic-debugging` для интеграции
- Claude Code tools: Read, Write, Edit, Bash, Grep, Glob
- Директория docs/rca/ с шаблоном TEMPLATE.md
- Beads issue tracker (опционально, для auto-create issues)

---

## Out of Scope

- Автоматический rollback при критических ошибках (отдельная feature)
- Интеграция с external monitoring systems (Prometheus, Grafana)
- Email/Slack уведомления о RCA
- Machine learning для предсказания ошибок
- Web UI для просмотра RCA Index

---

## Risks

- **Risk-001**: LLM может игнорировать новые инструкции → Mitigation: CRITICAL маркеры, примеры в начале документа
- **Risk-002**: Слишком сложный процесс отпугнёт пользователей → Mitigation: Quick template для простых случаев
- **Risk-003**: INDEX.md конфликты при командной работе → Mitigation: Автоматический merge strategy
- **Risk-004**: Test generation требует адаптации под разные фреймворки → Mitigation: Начать с TypeScript/Vitest, расширить позже

---

## Future Considerations

- RCA Dashboard с визуализацией трендов
- Integration с PagerDuty/OpsGenie для incident management
- ML-based error pattern recognition
- Multi-language support для отчётов
