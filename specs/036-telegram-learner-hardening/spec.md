# Feature Specification: Telegram Learner Hardening

**Feature Branch**: `[036-telegram-learner-hardening]`  
**Created**: 2026-04-02  
**Status**: Draft  
**Input**: User description: "Не останавливай работу и продолжай исправлять ошибки работы навыков в целом, разбирая корневую причину возникновения проблем и выдачи Activity Log. Для тестирования попробуй создай сам навык похожий на telegram-learner. Не забывай выполнять RCA при нахождении проблем. А также необходимо найти у нас сохраненный артефакт по созданию навыков и следовать этой инструкции. Если этого артефакта нет, создай его и в любом случае дополни рекомендациями сообществ по созданию навыков для Moltis/OpenClaw. Изучи этот навык и собери консилиум релевантных экспертов для улучшения этого навыка и получи от работы консилиума не менее 7-ми предложений по улучшению навыка. Далее используй Speckit воркфлоу для запуска планирования и внедрения этих 7-ми улучшений."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Clean Skill Detail In Telegram (Priority: P1)

Пользователь спрашивает про `telegram-learner` или опечатывается как `telegram-lerner`, а Telegram-safe runtime возвращает ровно один чистый и полезный ответ без `Activity log`, без operator markup и без рассказа о внутренних инструментах.

**Why this priority**: Это прямой пользовательский инцидент в проде. Пока skill-detail ответ загрязнён или дублируется, любой дальнейший skill-hardening не даёт ценности.

**Independent Test**: Можно полностью проверить отдельным component test и authoritative Telegram UAT на запрос `Расскажи мне про навык telegram-lerner`.

**Acceptance Scenarios**:

1. **Given** Telegram-safe user asks about `telegram-lerner`, **When** guard собирает deterministic skill-detail reply, **Then** пользователь получает один чистый ответ про `telegram-learner` без `Activity log`, `mcp__`, `SKILL.md`, host paths и tool errors.
2. **Given** runtime skill detail fallback срабатывает после raw tool/runtime failure, **When** MessageSending rewrite переписывает ответ, **Then** финальный reply остаётся value-first и не содержит внутренней authoring-разметки вроде `Workflow`, `Phase`, `Когда использовать`.

---

### User Story 2 - Thin Official-First Learner Skill Contract (Priority: P1)

Как maintainer, я хочу, чтобы `telegram-learner` был тонким Moltis skill-контрактом с явным `official-first` sourcing и canonical runtime boundary, а не giant prompt с operator handbook внутри.

**Why this priority**: Смешение DM-summary и operator workflow уже стало корневой причиной leakage/regression pressure. Это нужно исправить в самом authoring.

**Independent Test**: Можно проверить чтением `skills/telegram-learner/SKILL.md`, component skill-detail output и static review без live deploy.

**Acceptance Scenarios**:

1. **Given** maintainer открывает `skills/telegram-learner/SKILL.md`, **When** читает skill contract, **Then** видит короткий boundary-first workflow, official-first sourcing, degraded mode и отсутствие длинных operational templates.
2. **Given** deterministic builder строит skill-detail reply, **When** он читает thin contract, **Then** reply автоматически остаётся кратким, user-facing и не тянет internal workflow prose.

---

### User Story 3 - Similar Learner Skill And Guidance Artifacts (Priority: P2)

Как maintainer, я хочу иметь похожий тестовый learner-skill и исследовательский артефакт с официальными и community рекомендациями по skill authoring, чтобы новые learner skills не повторяли текущий дизайн-долг.

**Why this priority**: Это снижает риск повторного появления такого же класса багов при создании новых skills.

**Independent Test**: Можно проверить наличием нового skill, research artifact и component coverage на generic learner-skill detail output.

**Acceptance Scenarios**:

1. **Given** в репо создан похожий learner skill, **When** deterministic skill-detail logic читает его runtime `SKILL.md`, **Then** reply строится в том же clean Telegram-safe стиле.
2. **Given** maintainer ищет инструкцию по созданию learner skills, **When** открывает research/doc artifact, **Then** видит official-first guidance, relevant upstream issues и ranked next improvements.

---

### Edge Cases

- Что происходит, если skill runtime подтверждает имя навыка, но не может прочитать специальные summary sections?
- Как должен деградировать ответ, если official source для новости/инструкции не найден, а есть только community/Telegram сигнал?
- Что делать, если learner skill описывает long-running ingestion path, но Telegram-safe channel допускает только краткий синхронный ответ?
- Что происходит, если похожий learner skill добавлен в repo, но ещё не установлен в live runtime discovery path?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Система MUST возвращать deterministic skill-detail reply для `telegram-learner` и типовой опечатки `telegram-lerner` без `Activity log`, tool leakage и operator markup.
- **FR-002**: Система MUST строить skill-detail reply value-first, в 2-3 коротких предложениях, с каноническим именем навыка и без внутренних authoring-фраз вроде `Workflow`, `Phase`, `Когда использовать`, `SKILL.md`.
- **FR-003**: `skills/telegram-learner/SKILL.md` MUST быть переписан как thin contract с явным `official-first` sourcing order, canonical runtime boundary, degraded mode и без длинных filesystem/operator templates.
- **FR-004**: Система MUST иметь сохранённый артефакт по skill creation / learner authoring, который опирается на существующий проектный guide и дополняет его upstream/community рекомендациями.
- **FR-005**: Репозиторий MUST содержать похожий learner skill для regression/testing, чтобы generic skill-detail path проверялся не только на одном `telegram-learner`.
- **FR-006**: Component tests MUST проверять single clean reply, quiet typo resolution, отсутствие internal workflow markup и отсутствие tool leakage для learner-skill detail flows.
- **FR-007**: Изменения MUST быть зафиксированы через RCA/Speckit artifacts с минимум 7 конкретными улучшениями навыка и с выделением первых 5 приоритетных улучшений для немедленного внедрения.

### Key Entities *(include if feature involves data)*

- **Learner Skill Contract**: Тонкий `SKILL.md`, который задаёт trigger, boundary, sourcing order, degraded mode и краткий user-facing summary.
- **Skill Detail Reply**: Пользовательский deterministic ответ для Telegram-safe surface, генерируемый из runtime skill contract.
- **Guidance Artifact**: Документ с official/community best practices, ranked improvements и ссылками на канонические источники.
- **Test Learner Skill**: Похожий learner skill, используемый для regression coverage generic skill-detail behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Запрос `Расскажи мне про навык telegram-lerner` завершается одним clean Telegram reply без `Activity log`, tool-call traces и duplicate delivery.
- **SC-002**: `telegram-learner` skill-detail reply укладывается максимум в 3 предложения и не содержит внутренних authoring-маркеров.
- **SC-003**: В компонентных тестах есть coverage как минимум для двух learner skills, и все соответствующие проверки проходят.
- **SC-004**: В репо существует один явный документ с official/community guidance и ranked first-five improvements для learner-skill hardening.
