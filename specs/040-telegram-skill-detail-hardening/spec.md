# Feature Specification: Telegram Skill Detail Hardening

**Feature Branch**: `[040-telegram-skill-detail-hardening]`  
**Created**: 2026-04-05  
**Status**: Draft  
**Input**: User description: "Продолжай исправлять ошибки работы навыков в целом, разбирая корневую причину возникновения проблем и выдачи Activity Log. Используй Speckit workflow, RCA, official instructions и community evidence. Не останавливайся, пока skill-detail path в Telegram не станет чистым и устойчивым."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Clean Skill Detail For Any Repo Skill In Telegram (Priority: P1)

Пользователь спрашивает про любой repo-managed навык (`telegram-learner`, `codex-update`, `post-close-task-classifier` и т.п.), а Telegram-safe runtime возвращает ровно один чистый краткий ответ без `Activity log`, tool traces, operator markup и host paths.

**Why this priority**: Это прямой пользовательский surface. Пока skill-detail reply может деградировать в Activity log или operator-heavy prose, у нас нет надёжного user-facing contract.

**Independent Test**: Можно проверить component tests и authoritative Telegram UAT на skill-detail prompts.

**Acceptance Scenarios**:

1. **Given** пользователь спрашивает про существующий repo-managed skill, **When** runtime/hook path попадает в `skill_detail`, **Then** итоговый ответ остаётся deterministic, value-first и не содержит `Activity log`, `mcp__`, `SKILL.md`, `/server`, `/home/moltis` или operator templates.
2. **Given** raw runtime fallback пытается уйти в tool path или в filesystem probing, **When** Telegram-safe guard переписывает delivery, **Then** пользователь получает только clean skill-detail summary.

---

### User Story 2 - Terminal No-Tool Skill Detail Mode (Priority: P1)

Как maintainer, я хочу, чтобы `skill_detail` в Telegram-safe lane был терминальным text-only режимом и не допускал даже allowlisted tools вроде Tavily после классификации skill-detail turn.

**Why this priority**: Поздние tool dispatch и mixed-mode behavior остаются главным архитектурным риском повторного `Activity log` leakage.

**Independent Test**: Можно проверить dedicated BeforeToolCall/AfterLLMCall component coverage без live deploy.

**Acceptance Scenarios**:

1. **Given** turn уже классифицирован как `skill_detail`, **When** runtime пытается вызвать allowlisted Tavily tool, **Then** BeforeToolCall suppresses the tool and оставляет deterministic skill-detail path terminal.
2. **Given** direct fastpath не сработал и turn идёт in-band, **When** provider всё равно порождает tool calls, **Then** пользовательский итог остаётся text-only и не показывает внутренние progress/tool traces.

---

### User Story 3 - Shared Authoring Contract For Repo Skills (Priority: P2)

Как maintainer, я хочу, чтобы все repo-managed user-facing skills имели единый Telegram-safe skill-detail contract в frontmatter, а не зависели от случайного пересказа operator-heavy body.

**Why this priority**: Даже при хорошем runtime hook качество ответа остаётся нестабильным, если сами `SKILL.md` оформлены по-разному.

**Independent Test**: Можно проверить static contract tests и component skill-detail rewrites для нескольких разных skills.

**Acceptance Scenarios**:

1. **Given** maintainer открывает repo-managed `SKILL.md`, **When** skill может быть спрошен в Telegram/DM, **Then** frontmatter содержит отдельный user-facing summary contract.
2. **Given** runtime summary builder читает разные repo-managed skills, **When** они имеют единый frontmatter contract, **Then** итоговые ответы остаются краткими, user-facing и не тянут operator prose из тела файла.

---

### Edge Cases

- Что делать, если skill найден по typo/alias, но user-facing reply не должен повторять опечатку?
- Что делать, если tool path уже начался, но turn всё ещё должен завершиться deterministic skill-detail answer?
- Как должен деградировать ответ, если repo-managed skill существует, но специальных summary fields у него ещё нет?
- Что делать, если raw reply уже не содержит `Activity log`, но всё равно выглядит как operator/meta prose?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Система MUST возвращать deterministic clean skill-detail reply для всех текущих repo-managed user-facing skills без internal telemetry и operator markup.
- **FR-002**: `skill_detail` в Telegram-safe lane MUST быть terminal text-only mode и MUST suppress tool execution даже для allowlisted Tavily tools.
- **FR-003**: Repo-managed user-facing skills MUST иметь frontmatter contract как минимум с `description`, `telegram_summary`, `value_statement`, `telegram_safe_note`.
- **FR-004**: Learner/research/advisory-style skills MUST дополнительно иметь `source_priority` с explicit official-first order.
- **FR-005**: Component tests MUST покрывать skill-detail rewrite не только для `telegram-learner`, но и как минимум для ещё двух разных repo-managed skills.
- **FR-006**: Static validation MUST фиксировать отсутствие Telegram-safe skill-detail contract у repo-managed skills до live/UAT stage.
- **FR-007**: Изменения MUST быть зафиксированы через новый Speckit package и новый RCA с отличием от предыдущего learner-only incident.
- **FR-008**: Авторitative Telegram UAT MUST быть выполнен для skill-detail prompt после hardening.

### Key Entities

- **Skill Detail Turn**: Telegram-safe запрос, где пользователь спрашивает, что делает конкретный навык.
- **Terminal Skill Detail Mode**: Режим hook/runtime, в котором после классификации `skill_detail` дальнейшие tool calls запрещены, а ответ должен оставаться text-only.
- **Repo Skill Detail Contract**: Набор frontmatter полей, определяющий user-facing summary отдельно от operator-heavy body.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Для `telegram-learner`, `codex-update` и `post-close-task-classifier` component tests подтверждают clean skill-detail rewrites без internal telemetry/operator markup.
- **SC-002**: При persisted `skill_detail` intent allowlisted Tavily tools больше не проходят через BeforeToolCall.
- **SC-003**: Все repo-managed user-facing skills в `skills/` проходят static Telegram-safe detail contract check.
- **SC-004**: Authoritative Telegram UAT на skill-detail prompt проходит без `Activity log`, tool traces и duplicate tail delivery.
