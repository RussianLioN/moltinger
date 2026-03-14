# Feature Specification: Factory Business Analyst Intake

**Feature Branch**: `022-telegram-ba-intake`  
**Created**: 2026-03-13  
**Status**: In Progress
**Upstream Factory Context**: [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md)  
**Operational Baseline**: [../../docs/runbooks/agent-factory-prototype.md](../../docs/runbooks/agent-factory-prototype.md)  
**Input**: User description: "В самом начале пользователь должен взаимодействовать с фабричным агентом, реализованным на Moltis, который в роли бизнес-аналитика собирает требования, пользовательскую историю, примеры входных и выходных данных, ограничения, метрики успеха и формирует подтвержденное техническое задание для будущего AI агента."

## Clarifications

### Session 2026-03-14

- Q: Является ли discovery-агент Telegram-ботом как отдельной сущностью? → A: Нет, discovery-агент является фабричным цифровым сотрудником на `Moltis`, а `Telegram`, `Moltinger UI`, `Moltis UI` и будущий UI выступают только интерфейсными адаптерами.
- `022-telegram-ba-intake` остается legacy feature id и именем ветки для continuity workflow.
- Фактический scope пакета: фабричный агент-бизнес-аналитик на `Moltis`.
- Текущая реализация и fixtures по-прежнему используют `telegram` как default/reference channel, но это не определяет сущность агента.

## Scope Boundary

### In Scope

- Discovery-first flow для нового проекта AI-агента через любой поддерживаемый интерфейс фабрики, с `Telegram` как текущим reference adapter.
- Multi-turn диалог с нетехническим бизнес-пользователем на русском языке по умолчанию.
- Фабричный агент, реализованный на `Moltis`, действует как цифровой сотрудник фабрики в роли бизнес-аналитика.
- Пошаговый сбор и уточнение:
  - бизнес-проблемы
  - целевых пользователей и ролей
  - текущего процесса
  - болевых точек и желаемого результата
  - пользовательской истории
  - примеров входных данных
  - ожидаемых выходных данных
  - бизнес-правил и исключений
  - ограничений
  - метрик успеха
- Выявление недостающей, противоречивой или слишком расплывчатой информации и запуск уточняющих вопросов.
- Подготовка business-readable requirements brief и краткого технического задания до генерации concept pack.
- Явное подтверждение brief пользователем перед handoff в существующий concept-pack pipeline фабрики.
- Версионирование confirmed brief и сохранение истории правок до и после подтверждения.
- Возможность прервать и затем продолжить discovery-диалог без потери подтвержденного контекста.
- Отделение core discovery-логики от конкретного UI/мессенджер-канала, чтобы позже подключать дополнительные интерфейсы без переписывания бизнес-аналитического поведения.

### Out of Scope

- Defense workflow, review loop, internal swarm, playground packaging и deployment. Эти этапы уже покрываются downstream factory flow.
- Написание прикладного кода будущего AI-агента в рамках этого feature package.
- Обработка production-данных компании как обязательной части intake flow; для прототипа допускаются только sanitized, synthetic или surrogate examples.
- Полноценный multimodal intake через голос, изображения или документы как обязательный сценарий MVP этого slice.
- Замена concept-pack generation; этот feature подготавливает и подтверждает вход для уже существующего downstream pipeline.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Guided Discovery Interview (Priority: P1)

Как бизнес-пользователь без технической экспертизы, я хочу рассказать фабричному агенту о своей идее автоматизации простыми словами через доступный интерфейс и получать наводящие вопросы, чтобы постепенно сформулировать полноценные требования без самостоятельного написания ТЗ.

**Why this priority**: Пока discovery-интервью не работает, фабрика по-прежнему зависит от заранее подготовленного брифа и не закрывает главный пользовательский сценарий входа в систему.

**Independent Test**: Новый пользователь начинает диалог с сырой идеей, отвечает на вопросы в свободной форме и получает структурированное черновое описание проблемы, процесса, ограничений и целей без использования технического шаблона.

**Acceptance Scenarios**:

1. **Given** пользователь начинает новый проект AI-агента через поддерживаемый интерфейс фабрики, **When** агент открывает discovery flow, **Then** он объясняет свою роль, ожидаемый результат диалога и начинает собирать бизнес-контекст пошагово.
2. **Given** пользователь дает неполный или расплывчатый ответ, **When** агент определяет, что критичной информации не хватает, **Then** он задает следующий уточняющий вопрос вместо преждевременного формирования brief.
3. **Given** пользователь отвечает в свободной бизнес-лексике, **When** агент нормализует информацию, **Then** он переводит ответ в структурированные требования без требования технических терминов от пользователя.

---

### User Story 2 - Confirmed Requirements Brief (Priority: P1)

Как бизнес-пользователь, я хочу получить понятный черновик требований и подтвердить или поправить его, чтобы фабрика не запускала следующие этапы по неверно понятой идее.

**Why this priority**: Для downstream concept-pack pipeline нужен не просто набор ответов, а подтвержденный, устойчивый brief, который можно считать каноническим входом в дальнейшие стадии фабрики.

**Independent Test**: После диалога пользователь получает summary требований, вносит одно или несколько исправлений, а затем явно подтверждает финальную версию brief без ручного редактирования отдельных файлов.

**Acceptance Scenarios**:

1. **Given** агент собрал достаточный контекст, **When** он формирует summary, **Then** пользователь получает структурированный brief с проблемой, целями, scope, user story, примерами входа и выхода, правилами, ограничениями и метриками успеха.
2. **Given** пользователь замечает ошибку или упущение в summary, **When** он просит внести изменение, **Then** агент обновляет соответствующие разделы и показывает актуализированную версию brief до подтверждения.
3. **Given** пользователь явно подтверждает brief, **When** агент фиксирует подтверждение, **Then** текущая версия brief переводится в confirmed state и становится единственным допустимым входом для handoff в concept-pack pipeline.

---

### User Story 3 - Example-Driven Requirement Clarification (Priority: P2)

Как бизнес-пользователь, я хочу показывать примеры входных данных, ожидаемых результатов, правил и исключений, чтобы будущий агент проектировался не по абстрактным словам, а по реальным кейсам процесса.

**Why this priority**: Без examples и exceptions фабрика получает слишком общий brief, а downstream agent spec и playground riskуют не соответствовать реальной логике бизнеса.

**Independent Test**: Пользователь приводит несколько кейсов, агент извлекает из них структуру inputs, outputs, rules и exceptions, а при противоречии запрашивает разрешение конфликта до confirmation.

**Acceptance Scenarios**:

1. **Given** пользователь присылает пример ситуации из бизнеса, **When** агент анализирует его, **Then** он относит информацию к входным данным, ожидаемому результату, правилу или исключению.
2. **Given** пользователь присылает примеры, которые противоречат уже собранным требованиям, **When** агент выявляет расхождение, **Then** он формулирует вопрос на согласование противоречия до подтверждения brief.
3. **Given** examples собраны и подтверждены, **When** brief замораживается, **Then** в нем сохраняются как минимум representative input/output pairs и связанные business rules.

---

### User Story 4 - Handoff Into Existing Factory Pipeline (Priority: P2)

Как координатор фабрики, я хочу принимать confirmed brief как канонический upstream input для существующего concept-pack pipeline, чтобы discovery-слой не жил отдельно от уже реализованных стадий фабрики.

**Why this priority**: Новый фабричный business-analyst слой должен усиливать текущую фабрику, а не создавать параллельный и несвязанный процесс описания требований.

**Independent Test**: Подтвержденный brief передается в существующий concept-pack pipeline без ручного копипаста, при этом сохраняется traceability между диалогом, confirmed brief и downstream concept artifacts.

**Acceptance Scenarios**:

1. **Given** brief подтвержден, **When** фабрика запускает handoff, **Then** существующий concept-pack pipeline получает один canonical brief record с version linkage и complete business context.
2. **Given** brief еще не подтвержден, **When** кто-то пытается инициировать downstream generation, **Then** фабрика блокирует handoff до явного confirmation.
3. **Given** downstream concept artifacts позже потребуют проверяемости происхождения, **When** оператор или пользователь смотрит на provenance, **Then** он может проследить связь между conversational discovery, confirmed brief и concept-pack output.

---

### User Story 5 - Interrupted Session Recovery (Priority: P3)

Как бизнес-пользователь, я хочу вернуться к незавершенному диалогу позже и продолжить с того места, где остановился, чтобы не проходить интервью заново после паузы.

**Why this priority**: Реальные discovery-сессии часто растягиваются по времени и требуют возврата к теме после обсуждений внутри бизнеса.

**Independent Test**: Пользователь прерывает discovery-сессию до подтверждения, возвращается позже и продолжает только по неуточненным или измененным темам.

**Acceptance Scenarios**:

1. **Given** discovery-сессия была прервана, **When** пользователь возвращается в тот же проект, **Then** агент кратко напоминает подтвержденный контекст и продолжает с незакрытых тем.
2. **Given** часть требований уже была подтверждена ранее, **When** пользователь продолжает диалог, **Then** агент не задает заново уже закрытые вопросы без явной причины.

## Edge Cases

- Пользователь отвечает одним длинным сообщением сразу на несколько тем, включая информацию не в том порядке, в котором агент задавал вопросы.
- Пользователь говорит "я не знаю" по одной из критичных тем, но хочет продолжить discovery и зафиксировать это как открытый риск.
- Пользователь дает примеры, которые конфликтуют с уже подтвержденной пользовательской историей, scope или success metrics.
- Пользователь хочет использовать реальные бизнес-примеры, содержащие чувствительные данные, и агент должен запросить безопасную замену или обезличивание.
- Пользователь уходит из диалога на несколько дней и возвращается, когда часть контекста уже подтверждена, а часть нет.
- Пользователь хочет внести правку в brief после confirmation, не теряя предыдущую подтвержденную версию.

## Requirements *(mandatory)*

### Functional Requirements

#### Discovery Dialogue

- **FR-001**: System MUST open a dedicated discovery session when a user starts a new AI-agent project through any supported factory interface.
- **FR-002**: System MUST explain that it acts as a factory business-analyst agent that helps the user transform a raw automation idea into a confirmed requirements brief.
- **FR-003**: System MUST conduct a multi-turn dialogue in Russian by default to collect the business problem, target users, current workflow, pain points, desired outcome, constraints, and success metrics.
- **FR-004**: System MUST identify which critical requirement topics are still missing before declaring the brief ready for confirmation.
- **FR-005**: System MUST ask follow-up questions based on unresolved or ambiguous topics instead of using a fixed one-pass questionnaire.
- **FR-006**: System MUST accept free-form business language and normalize it into structured requirement fields without requiring technical terminology from the user.
- **FR-007**: System MUST distinguish confirmed information, assumptions, and open questions during discovery.
- **FR-008**: System MUST support collection of user story statements, input examples, output expectations, business rules, and exception cases as first-class discovery artifacts.
- **FR-009**: System MUST detect contradictions or material ambiguities across answers and examples and request clarification before confirmation.
- **FR-010**: System MUST maintain topic-level progress that differentiates unanswered, partially answered, clarified, confirmed, and unresolved requirement areas.
- **FR-011**: System MUST support resuming an unfinished discovery session without losing previously confirmed context.
- **FR-011a**: System MUST preserve the same discovery semantics regardless of whether the current interaction surface is Telegram, Moltinger UI, Moltis UI, or a future factory UI adapter.

#### Requirements Brief And Confirmation

- **FR-012**: System MUST generate a business-readable requirements brief for each discovery session before any downstream artifact generation begins.
- **FR-013**: The requirements brief MUST include the problem statement, target users, current process, desired outcome, scope boundaries, user story, input examples, expected outputs, business rules, exceptions, constraints, success metrics, and open risks.
- **FR-014**: System MUST show a reviewable summary draft to the user before freezing any version of the brief.
- **FR-015**: Users MUST be able to request corrections or additions to any section of the draft brief in conversational form.
- **FR-016**: System MUST require explicit user confirmation before marking a brief version as confirmed and eligible for downstream handoff.
- **FR-017**: System MUST version confirmed brief snapshots and preserve the history of meaningful revisions.
- **FR-018**: System MUST expose a clear state for each brief such as discovery in progress, awaiting clarification, awaiting confirmation, confirmed, or reopened for revision.

#### Handoff Into The Existing Factory Flow

- **FR-019**: System MUST transform the confirmed brief into one canonical handoff record consumable by the existing concept-pack pipeline.
- **FR-020**: System MUST preserve traceability between discovery dialogue content, confirmed brief sections, and downstream concept-pack generation.
- **FR-021**: System MUST prevent concept-pack generation from starting until a brief has explicit confirmed status.
- **FR-022**: System MUST allow a previously confirmed brief to be reopened for revision by creating a new version instead of overwriting historical confirmed content.
- **FR-023**: System MUST provide the next recommended action after each major state transition, including continue discovery, resolve contradiction, confirm brief, or start concept-pack handoff.

#### Non-Technical Usability And Governance

- **FR-024**: The dialogue experience MUST remain usable for non-technical business users and MUST NOT require them to provide implementation details in order to complete discovery.
- **FR-025**: System MUST keep business-facing discovery dialogue separate from factory-internal production evidence, operator escalation data, and swarm runtime details.
- **FR-026**: System MUST warn the user when provided examples appear to contain sensitive or production business data and request sanitized substitutes for prototype use.
- **FR-027**: System MUST support Russian-language summaries and confirmations by default while keeping the meaning of confirmed requirements stable across future language expansions.
- **FR-028**: System MUST support one project having multiple discovery and confirmation iterations without requiring the user to restart from an empty session each time.

### Key Entities *(include if feature involves data)*

- **DiscoverySession**: One factory-owned conversational discovery context for a future AI-agent project, including current progress, unresolved topics, state, and the active interface channel.
- **RequirementTopic**: One required or optional subject area such as business problem, target users, input examples, exceptions, or success metrics.
- **RequirementBrief**: The structured, business-readable summary produced from the conversation before concept-pack generation.
- **BriefSection**: One named part of the requirement brief that can be reviewed, corrected, confirmed, or reopened independently.
- **ExampleCase**: A user-provided sample input, expected output, rule, or exception used to ground the future agent design.
- **ClarificationItem**: One unresolved ambiguity, contradiction, or missing topic that requires a follow-up answer before confirmation.
- **ConfirmationSnapshot**: One immutable confirmed version of the requirement brief linked to its discovery history.
- **FactoryHandoffRecord**: The canonical upstream record passed from confirmed discovery into the existing concept-pack pipeline.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A non-technical business user can go from a raw automation idea to a reviewable requirements brief within one guided factory discovery flow without using an external template.
- **SC-002**: At least 90% of pilot discovery sessions that start with a raw idea produce either a complete draft brief or an explicit list of unresolved questions, rather than failing silently.
- **SC-003**: 100% of confirmed briefs include at least one user story, one representative input/output example pair, one constraint, and one measurable success criterion.
- **SC-004**: 100% of downstream concept-pack handoffs are blocked until the current brief version is explicitly confirmed.
- **SC-005**: A user can correct the draft brief and receive an updated summary in the same conversation without manual file editing.
- **SC-006**: An interrupted discovery session can be resumed without re-asking already confirmed topics and without losing prior confirmed context.
- **SC-007**: Operators can trace any concept-pack generated from this flow back to the exact confirmed brief version and its discovery session.
- **SC-008**: In pilot usage, 0 users are required to supply implementation terms such as programming language, architecture, or deployment details in order to complete discovery.

## Assumptions

- `Telegram` remains the current default/reference interface for this slice, but the discovery agent itself belongs to the factory runtime on `Moltis`, not to one specific messenger.
- The existing `020-agent-factory-prototype` concept-pack pipeline remains the downstream consumer of confirmed discovery output.
- Russian is the default working language for both dialogue and generated brief content unless a future request explicitly changes it.
- Business users can provide sanitized or surrogate examples when real production examples contain sensitive data.

## Dependencies

- Existing factory scope and downstream lifecycle in [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md).
- Operational baseline in [../../docs/runbooks/agent-factory-prototype.md](../../docs/runbooks/agent-factory-prototype.md).
- Current Moltinger coordinator role in [../../config/moltis.toml](../../config/moltis.toml).
