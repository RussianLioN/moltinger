# Feature Specification: Agent Factory Prototype

**Feature Branch**: `020-agent-factory-prototype`  
**Created**: 2026-03-12  
**Status**: Ready for Planning  
**Context Mirror**: [../../docs/ASC-AI-FABRIQUE-MIRROR.md](../../docs/ASC-AI-FABRIQUE-MIRROR.md)  
**Supporting Local Plans**: [../../docs/plans/parallel-doodling-coral.md](../../docs/plans/parallel-doodling-coral.md), [../../docs/plans/agent-factory-lifecycle.md](../../docs/plans/agent-factory-lifecycle.md)  
**Input**: User description: "Начать разработку прототипа фабрики AI-агентов внутри Moltis: через Telegram-бот вести диалог по идее автоматизации, параллельно выпускать проектную документацию, спецификацию и презентацию, проводить защиту концепции, затем запускать служебный рой для автономного производства контейнеризированного агента с playground и циклом обратной связи до решения о production."

## Scope Boundary

### In Scope

- Прототип фабрики AI-агентов внутри текущего контура Moltinger/Moltis.
- Telegram-диалог с пользователем по идее автоматизации и сбору недостающего контекста.
- Параллельное формирование трех артефактов по концепции:
  - проектная документация
  - спецификация будущего агента
  - презентация для защиты концепции
- Фиксация результата защиты концепции и работа с обратной связью.
- Запуск внутреннего служебного роя после явного одобрения концепции.
- Сборка контейнеризированного playground на тестовых или синтетических данных для демонстрации будущего агента.
- Административная эскалация только на блокирующих или integrity-ошибках.
- Локальное зеркало ASC AI Fabrique документации в текущем репозитории и навигация по ней.

### Out of Scope

- Production deployment сгенерированного прикладного агента в рабочий контур организации. Это относится к MVP1.
- Полностью автономное согласование без внешнего человеческого решения после защиты концепции.
- Полноценный многонодовый production swarm с произвольным числом runtime-агентов.
- Реальные бизнесовые данные в playground; для прототипа допустимы только тестовые и синтетические данные.
- Полная замена текущей роли Moltinger как DevOps-платформы в рамках этого feature package.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Idea Intake To Concept Pack (Priority: P1)

Как инициатор автоматизации, я хочу через Telegram обсудить идею будущего агента и получить готовый набор артефактов по концепции, чтобы вынести идею на защиту без ручной сборки документов.

**Why this priority**: Пока фабрика не умеет превращать сырой замысел в согласованный концепт-пакет, все последующие этапы производства агента лишены устойчивого входа и единого источника правды.

**Independent Test**: Пользователь проходит один Telegram-диалог по новой идее и получает три согласованных артефакта, каждый из которых доступен как рабочий исходник и как скачиваемый файл.

**Acceptance Scenarios**:

1. **Given** у пользователя есть сырая идея автоматизации, **When** фабрика проводит intake-диалог, **Then** она собирает проблему, целевых пользователей, текущий процесс, ограничения, метрики успеха и допущения.
2. **Given** intake-диалог завершён, **When** фабрика выпускает концепт-пакет, **Then** проектная документация, спецификация и презентация согласованы по целям, границам, рискам и ожидаемому эффекту.
3. **Given** концепт-пакет готов, **When** пользователь запрашивает результаты, **Then** каждый артефакт можно скачать и использовать без ручного поиска файлов в серверном контуре.

---

### User Story 2 - Defense Outcome And Rework Loop (Priority: P1)

Как владелец идеи, я хочу зафиксировать результат защиты и полученную обратную связь, чтобы фабрика либо обновила концепт-пакет, либо перевела его в состояние готовности к производству агента.

**Why this priority**: Защита концепции является обязательным управляющим шлюзом между этапом идеи и этапом автономного производства. Без этого шлюза фабрика либо преждевременно начинает coding swarm, либо теряет управляемость изменений.

**Independent Test**: Один и тот же концепт-пакет можно провести через состояние `approved`, `rework_requested`, `rejected` или `pending_decision`, при этом история решений и версий артефактов сохраняется.

**Acceptance Scenarios**:

1. **Given** защита завершилась с доработками, **When** фабрика получает feedback, **Then** она обновляет затронутые артефакты и сохраняет предыдущую версию и решение по защите.
2. **Given** концепция одобрена, **When** результат защиты зафиксирован, **Then** фабрика переводит запрос в состояние готовности к запуску служебного роя.
3. **Given** решение по защите не утверждено, **When** пользователь или фабрика запрашивают запуск производства, **Then** система не начинает производственный рой без явного approval.

---

### User Story 3 - Autonomous Production Swarm To Playground (Priority: P1)

Как администратор фабрики, я хочу после одобрения концепции запускать внутренний служебный рой для автономного создания агента и его playground, чтобы пользователь видел работоспособный результат без ручного сопровождения happy path.

**Why this priority**: Сама ценность фабрики в MVP0 проявляется не только в документах, но и в способности довести одобренную концепцию до демонстрируемого, контейнеризированного результата с минимальным участием человека.

**Independent Test**: Для одного одобренного концепта фабрика проходит стадии кодирования, тестирования, валидации, аудита и сборки и возвращает runnable playground package с evidence bundle.

**Acceptance Scenarios**:

1. **Given** концепция получила approval, **When** фабрика запускает production swarm, **Then** роли coder, tester, validator, auditor и assembler отрабатывают в заданной последовательности с явными входами и выходами.
2. **Given** все служебные стадии завершились успешно, **When** пользователь получает результат, **Then** ему доступен контейнеризированный playground для демонстрации работы агента на тестовых или синтетических данных.
3. **Given** одна из стадий завершается блокирующей ошибкой, **When** happy path прерывается, **Then** фабрика эскалирует только на администратора и не требует от конечного пользователя ручного восстановления производственного процесса.

---

### User Story 4 - Operator Escalation And Evidence (Priority: P2)

Как администратор фабрики, я хочу получать структурированные эскалации, статус этапов и доказательства результатов, чтобы вмешиваться только в исключительных ситуациях и быстро понимать, где именно сломался конвейер.

**Why this priority**: Даже в прототипе служебный рой без операционной прозрачности превращается в непрогнозируемую цепочку скрытых ошибок, что делает демонстрацию и защиту результата недостоверной.

**Independent Test**: Любой блокирующий сбой производства или защиты формирует escalation packet с идентификатором концепта, стадией, ошибкой, evidence и рекомендуемым следующим шагом.

**Acceptance Scenarios**:

1. **Given** production swarm завис или завершился ошибкой, **When** система формирует эскалацию, **Then** администратор получает идентификатор запроса, стадию, сводку ошибки и ссылки на evidence.
2. **Given** пользователь смотрит на прогресс, **When** фабрика обновляет статусы, **Then** пользователь видит разницу между стадиями `concept`, `defense`, `production`, `playground_ready` и `needs_admin_attention`.
3. **Given** операция завершилась успешно или с отказом, **When** later review запрашивает след, **Then** все ключевые переходы, версии и решения доступны в аудите.

---

### User Story 5 - Local Context Continuity For Factory Knowledge (Priority: P2)

Как архитектор платформы, я хочу держать актуальные ASC-концепцию, дорожную карту и локальные factory-артефакты внутри этого репозитория, чтобы будущие planning и implementation сессии не зависели от внешних путей и не теряли контекст фабрики.

**Why this priority**: Пользователь явно требует, чтобы копия документации ASC жила в проектной документации текущего репозитория. Без этого planning drift и context reconstruction будут повторяться в каждой новой сессии.

**Independent Test**: Новый участник сессии может из текущего репозитория найти upstream-концепцию ASC, локальные планы фабрики, активный Speckit package и операционные platform-контракты без обращения к внешнему абсолютному пути.

**Acceptance Scenarios**:

1. **Given** репозиторий открыт в новой сессии, **When** агент ищет базовые документы по фабрике, **Then** он находит ASC roadmap, concept docs, локальные планы и активный Speckit package по in-repo путям.
2. **Given** локальное зеркало обновлено, **When** planning продолжает работу, **Then** документы содержат provenance источника и понятную навигацию к локальным adaptation-артефактам.
3. **Given** planning артефакты ссылаются на ASC-контекст, **When** они ревьюятся, **Then** в них нет зависимости от workstation-specific пути вида `/Users/.../ASC-AI-agent-fabrique`.

### Edge Cases

- Что происходит, если пользователь описывает идею слишком абстрактно и фабрика не может сформировать измеримые критерии успеха?
- Что происходит, если три артефакта сгенерированы частично и расходятся по scope, метрикам или ограничениям?
- Что происходит, если защита возвращает противоречивую обратную связь от разных участников?
- Что происходит, если approval выдан для устаревшей версии концепта, а затем пользователь внёс новые изменения?
- Что происходит, если production swarm проходит тестирование, но проваливает валидацию или аудит соответствия исходному запросу?
- Что происходит, если playground контейнер собирается, но не может быть запущен в изолированной демонстрационной среде?
- Что происходит, если один или несколько служебных ролей роя временно недоступны, но другие стадии уже завершились?
- Что происходит, если локальное зеркало ASC-документации отсутствует, устарело или не содержит критичный концептуальный документ для planning?

## Requirements *(mandatory)*

### Functional Requirements

#### Idea Intake And Artifact Generation

- **FR-001**: System MUST conduct a multi-turn Telegram dialogue to collect the business problem, target users, current workflow, constraints, expected outcomes, and available context for one automation idea.
- **FR-002**: System MUST identify missing critical information and ask follow-up questions before finalizing the concept pack.
- **FR-003**: System MUST consolidate the collected input into a single versioned concept record for the future agent.
- **FR-004**: System MUST generate three synchronized working artifacts for each concept record: project documentation, agent specification, and defense presentation.
- **FR-005**: System MUST keep all three artifacts aligned on problem statement, scope, goals, constraints, risks, and success metrics.
- **FR-006**: Each artifact MUST be available in an editable working format and as a downloadable user-facing output.
- **FR-007**: System MUST allow one artifact to be regenerated or revised without losing synchronization with the other two artifacts.
- **FR-008**: System MUST capture the assumptions, unresolved risks, and relevant ASC patterns used to shape the concept pack.
- **FR-009**: System MUST support Russian-language intake and artifact generation for this prototype by default.
- **FR-010**: System MUST separate user-provided business context from factory-internal production notes and operator evidence.

#### Defense And Decision Workflow

- **FR-011**: System MUST record the defense outcome for each concept as `approved`, `rework_requested`, `rejected`, or `pending_decision`.
- **FR-012**: System MUST capture structured feedback items and map them to impacted artifacts, requirements, or assumptions.
- **FR-013**: System MUST prevent the production swarm from starting until the concept has explicit approval.
- **FR-014**: System MUST support concept rework after feedback while preserving prior artifact versions and decision history.
- **FR-015**: System MUST generate a concise post-defense summary that lists decisions, requested changes, and next actions.
- **FR-016**: System MUST distinguish concept approval from deployment approval; production deployment stays outside this prototype.

#### Autonomous Production Swarm And Playground

- **FR-017**: After concept approval, System MUST orchestrate specialized internal factory roles for coding, testing, validation, audit, and assembly.
- **FR-018**: System MUST define explicit stage order, role ownership, and entry/exit conditions for each internal production stage.
- **FR-019**: System MUST support parallel execution for independent internal stages while preserving required dependencies between stages.
- **FR-020**: System MUST generate a buildable agent package from the approved concept without requiring the end user to manually coordinate the happy path.
- **FR-021**: System MUST package the produced agent into a runnable container together with a playground-ready execution context.
- **FR-022**: Playground execution MUST use only test or synthetic data in this prototype.
- **FR-023**: System MUST publish reviewable evidence for coding, tests, validation, audit, and packaging outcomes.
- **FR-024**: System MUST preserve traceability from approved concept requirements to produced agent behavior and audit conclusions.
- **FR-025**: System MUST support restarting production after concept rework or after playground feedback without recreating the concept from scratch.
- **FR-026**: System MUST stop before production deployment and hand off deployment readiness to the later MVP1 scope.

#### Escalation, Audit, And Governance

- **FR-027**: System MUST escalate only blocker or integrity failures to the factory administrator, not normal happy-path transitions.
- **FR-028**: Each escalation MUST include the concept id, current stage, error summary, evidence bundle, and recommended next step.
- **FR-029**: System MUST provide user-visible status updates that distinguish `concept`, `defense`, `rework`, `production`, `playground_ready`, and `needs_admin_attention`.
- **FR-030**: System MUST maintain an audit trail for concept edits, defense decisions, internal swarm stage transitions, escalations, and artifact publication.
- **FR-031**: System MUST separate end-user dialogue from factory service-agent operations and administrator interventions.
- **FR-032**: System MUST ensure that outdated or partially approved artifacts cannot accidentally trigger a new production run.

#### Local Knowledge Mirror And Context Retention

- **FR-033**: The repository MUST contain a versioned local mirror of the relevant ASC AI Fabrique roadmap and concept documentation.
- **FR-034**: The local mirror MUST provide navigation to upstream provenance and to project-local factory planning artifacts.
- **FR-035**: Prototype planning artifacts MUST reference in-repo ASC documentation instead of workstation-specific absolute paths.
- **FR-036**: Factory documentation in this repository MUST let future sessions locate concept sources, active Speckit packages, local platform contracts, and runbooks without external context reconstruction.
- **FR-037**: Mirror refreshes MUST record the verified upstream source and the local mirror scope.
- **FR-038**: Missing or stale mirror content MUST be detectable during planning or review.

### Key Entities

- **ConceptRequest**: Initial user-submitted automation idea together with collected business context and missing-information prompts.
- **ConceptRecord**: Versioned canonical record of one future agent concept, including current decision state and linked artifacts.
- **ArtifactSet**: The synchronized trio of project documentation, specification, and presentation associated with one concept record.
- **ArtifactVersion**: One immutable revision of an artifact together with provenance, diff reason, and approval relation.
- **DefenseReview**: Recorded result of a concept defense, including decision, reviewers, date, and outcome status.
- **FeedbackItem**: One structured correction, concern, or improvement request mapped to the affected concept elements.
- **ProductionApproval**: Explicit authorization that unlocks the internal production swarm for a specific concept version.
- **SwarmRun**: One autonomous factory production attempt created from an approved concept version.
- **SwarmStageExecution**: One role-specific stage inside a swarm run, with status, evidence, dependencies, and timestamps.
- **PlaygroundPackage**: Runnable containerized demo bundle for the generated agent, limited to test or synthetic data.
- **EscalationPacket**: Operator-facing incident bundle that contains stage, failure summary, evidence, and recommended action.
- **KnowledgeMirrorRecord**: Provenance record that describes which upstream ASC materials are mirrored locally and when they were refreshed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can go from a raw automation idea to a downloadable three-artifact concept pack within one guided intake flow.
- **SC-002**: 100% of generated concept packs keep project documentation, specification, and presentation aligned on scope, goals, constraints, and success metrics.
- **SC-003**: 100% of production swarm runs are blocked until an explicit concept approval exists for the exact concept version being produced.
- **SC-004**: For at least one reference concept, the prototype can produce a runnable playground container and evidence bundle within 2 hours after approval.
- **SC-005**: 100% of blocker failures in concept defense or swarm production create an administrator-facing escalation packet before the run is considered terminal.
- **SC-006**: A user can download the current concept artifacts and the final playground bundle without direct access to the server filesystem.
- **SC-007**: At least one concept can pass through the loop `draft -> defense feedback -> revised artifacts -> approved -> swarm run` without recreating the concept from scratch.
- **SC-008**: A new planning session can find the ASC mirror, local factory plans, the active Speckit package, and platform contracts from repository paths within 5 minutes.
- **SC-009**: 0 production deployment attempts are executed from this prototype scope before MVP1 handoff.
- **SC-010**: Operators can trace any playground result back to the approved concept version and the recorded validation/audit outcomes.

## Assumptions

- Moltinger remains the primary user-facing coordinator and Telegram entry point for this prototype.
- Existing fleet artifacts such as `config/fleet/agents-registry.json` and `config/fleet/policy.json` can serve as the initial control-plane baseline for the future service-agent swarm.
- The internal production roles may start as a mix of existing runtimes, explicit orchestration contracts, or staged future roles as long as the prototype preserves the required stage semantics.
- The canonical working language for dialogue and generated artifacts is Russian unless a future request explicitly changes it.
- The artifact set may use editable source-first formats internally as long as user-facing downloadable outputs are available.

## Dependencies

- Local ASC concept and roadmap mirror maintained through [../../docs/ASC-AI-FABRIQUE-MIRROR.md](../../docs/ASC-AI-FABRIQUE-MIRROR.md).
- Existing local factory plans in [../../docs/plans/parallel-doodling-coral.md](../../docs/plans/parallel-doodling-coral.md) and [../../docs/plans/agent-factory-lifecycle.md](../../docs/plans/agent-factory-lifecycle.md).
- Existing fleet contracts in [../../config/fleet/agents-registry.json](../../config/fleet/agents-registry.json) and [../../config/fleet/policy.json](../../config/fleet/policy.json).
- Existing Moltinger configuration baseline in [../../config/moltis.toml](../../config/moltis.toml).
