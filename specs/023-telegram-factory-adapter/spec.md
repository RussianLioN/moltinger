# Feature Specification: Telegram Factory Adapter

**Feature Branch**: `023-telegram-factory-adapter`  
**Created**: 2026-03-14  
**Status**: Draft (Follow-up Adapter)
**Upstream Discovery Context**: [../022-telegram-ba-intake/spec.md](../022-telegram-ba-intake/spec.md)  
**Downstream Factory Context**: [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md)  
**Primary Demo Context**: [../024-web-factory-demo-adapter/spec.md](../024-web-factory-demo-adapter/spec.md)
**Operational Baseline**: [../../docs/runbooks/agent-factory-discovery.md](../../docs/runbooks/agent-factory-discovery.md)  
**Input**: User description: "Сделать первый живой пользовательский интерфейс для фабричного агента-бизнес-аналитика на Moltis через Telegram. Пользователь должен общаться с агентом в реальном Telegram-диалоге, проходить discovery interview, подтверждать requirements brief и без ручного копипаста запускать downstream handoff в существующую фабрику. Telegram в этом slice является первым реальным интерфейсным адаптером к уже готовому discovery runtime, а не отдельной сущностью агента."

## Clarifications

### Session 2026-03-14

- Q: Является ли Telegram отдельным агентом или первым интерфейсным адаптером? → A: Telegram является первым живым интерфейсным адаптером к фабричному агенту на `Moltis`, а не отдельной сущностью агента.
- Q: Должен ли пользователь после `confirmed brief` вручную запускать downstream flow? → A: Нет. Telegram adapter должен автоматически инициировать `handoff -> intake -> concept pack` и вернуть пользователю результат в том же пользовательском канале.
- Q: Остается ли Telegram primary demo path после web-first pivot? → A: Нет. После `024-web-factory-demo-adapter` primary near-term demo path становится web-first browser adapter, а `023` сохраняется как follow-up transport scope.

## Scope Boundary

### In Scope

- Follow-up live пользовательский интерфейс к уже существующему factory discovery runtime через Telegram bot.
- Реальный multi-turn Telegram dialogue для нетехнического бизнес-пользователя на русском языке по умолчанию.
- Привязка Telegram chat/user context к discovery session, brief state, handoff state и active project.
- Передача каждого пользовательского сообщения в существующий `022` discovery runtime без дублирования discovery-логики в adapter-слое.
- Показ пользователю:
  - следующего вопроса
  - clarification
  - reviewable brief summary
  - статуса `confirmed brief`
  - статуса downstream handoff
  - concept-pack readiness и downloadable artifacts
- Явное подтверждение brief из Telegram-диалога.
- Автоматический запуск downstream path после `confirmed brief`:
  - `factory_handoff_record`
  - `agent-factory-intake.py`
  - `agent-factory-artifacts.py`
- Доставка пользователю 3 concept-pack артефактов через Telegram как user-facing outcome:
  - project doc
  - agent spec
  - presentation
- Возобновление прерванной discovery session и переоткрытие confirmed brief из Telegram без потери history.
- User-facing error/status messaging без внутренних stack traces и repo paths.
- Сохранение архитектурного правила: Telegram adapter тонкий и использует готовый factory runtime вместо отдельной business-analysis логики.

### Out of Scope

- Замена discovery runtime из `022-telegram-ba-intake`.
- Замена downstream concept-pack pipeline, defense loop, swarm, playground или deploy из `020-agent-factory-prototype`.
- Неграниченный multi-channel adapter layer для всех будущих UI в одном slice; в этом feature Telegram остается follow-up adapter после primary web-first demo path из `024`.
- Production deployment orchestration и масштабирование bot infrastructure.
- Полный self-serve defense loop и playground interaction внутри Telegram в этом slice.
- Работа с несанаизированными production business data как обязательный сценарий.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Live Telegram Discovery Interview (Priority: P1)

Как бизнес-пользователь, я хочу начать новый проект будущего AI-агента прямо в Telegram и пройти с фабричным агентом discovery interview в обычном чате, чтобы не пользоваться JSON, CLI или ручным описанием требований вне мессенджера.

**Why this priority**: Это первый реальный пользовательский вход в фабрику. Пока его нет, discovery runtime существует только как технический контур для оператора, а не как доступный пользовательский интерфейс.

**Independent Test**: Пользователь пишет боту сырую идею автоматизации в Telegram, получает наводящие вопросы и проходит discovery interview без shell-доступа и без ручной подготовки файла.

**Acceptance Scenarios**:

1. **Given** пользователь начинает новый диалог с ботом, **When** он описывает идею автоматизации в свободной форме, **Then** Telegram adapter создает или выбирает discovery session и возвращает первый business-readable follow-up question из discovery runtime.
2. **Given** пользователь отвечает следующим сообщением в том же чате, **When** adapter передает ответ в discovery runtime, **Then** бот возвращает следующий вопрос, clarification или summary без потери уже собранного контекста.
3. **Given** пользователь говорит простым бизнес-языком, **When** runtime нормализует ответ, **Then** Telegram adapter показывает только user-facing результат, а не внутренние JSON-поля или системные детали.

---

### User Story 2 - Telegram Brief Review And Confirmation (Priority: P1)

Как бизнес-пользователь, я хочу получить brief и подтвердить или поправить его прямо в Telegram, чтобы фабрика не требовала ручного редактирования файлов или перехода в другой инструмент перед следующим этапом.

**Why this priority**: User test считается реальным только если пользователь может завершить discovery до `confirmed brief` полностью внутри одного привычного интерфейса.

**Independent Test**: Пользователь доводит discovery до summary, просит правки в обычном сообщении, затем явно подтверждает brief, оставаясь в Telegram-диалоге.

**Acceptance Scenarios**:

1. **Given** discovery runtime считает brief готовым к review, **When** adapter получает `awaiting_confirmation`, **Then** бот отправляет user-readable summary и инструкции, как внести правку или подтвердить текущую версию.
2. **Given** пользователь просит скорректировать часть brief, **When** adapter передает это в discovery runtime, **Then** бот показывает обновленную версию brief и новый confirmation prompt.
3. **Given** пользователь явно подтверждает brief, **When** adapter получает confirmed state, **Then** Telegram flow фиксирует подтверждение и не требует ручного копипаста в следующий этап.

---

### User Story 3 - Automatic Factory Handoff From Telegram (Priority: P2)

Как бизнес-пользователь, я хочу после подтверждения brief автоматически запустить следующий этап фабрики и получить concept-pack артефакты в Telegram, чтобы сразу увидеть результат своей идеи без операторского участия.

**Why this priority**: Это превращает Telegram adapter из простого chat frontend в реальный self-serve вход в фабрику на уровне MVP user testing.

**Independent Test**: После `confirmed brief` bot автоматически получает `factory_handoff_record`, запускает intake и concept-pack generation, а затем возвращает пользователю 3 готовых артефакта и user-facing status.

**Acceptance Scenarios**:

1. **Given** brief подтвержден, **When** adapter получает `factory_handoff_record.handoff_status = ready`, **Then** он автоматически вызывает downstream intake и concept-pack generation без ручных операторских шагов.
2. **Given** concept pack успешно сгенерирован, **When** adapter публикует результат, **Then** пользователь получает Telegram-visible status и 3 артефакта, пригодных для скачивания и дальнейшей защиты.
3. **Given** handoff еще не готов или generation завершается с ошибкой, **When** adapter сообщает результат, **Then** пользователь видит короткий понятный статус без внутренних stack traces и с указанием следующего действия.

---

### User Story 4 - Resume And Reopen In Telegram (Priority: P2)

Как бизнес-пользователь, я хочу вернуться к своему проекту позже, продолжить discovery или переоткрыть confirmed brief через Telegram, чтобы не начинать процесс заново после паузы или внутренних согласований.

**Why this priority**: Реальные discovery и согласования редко проходят в один непрерывный сеанс. Без resume/reopen user-facing Telegram flow будет ломаться в реальном использовании.

**Independent Test**: Пользователь прерывает работу в Telegram, возвращается позже, получает resume summary, продолжает с нужной точки и при необходимости переоткрывает brief в новую версию без потери history.

**Acceptance Scenarios**:

1. **Given** пользователь вернулся в чат после паузы, **When** bot находит активную discovery session, **Then** он отправляет краткое resume summary и продолжает с pending question или clarification.
2. **Given** у проекта уже есть confirmed brief, **When** пользователь просит внести изменение, **Then** adapter запускает reopen flow, а предыдущие confirmation/handoff записи остаются в истории.
3. **Given** пользователь после reopen снова подтверждает brief, **When** adapter получает новую confirmed version, **Then** downstream handoff работает уже от новой версии, а старая остается traceable.

## Edge Cases

- Пользователь пишет одновременно в несколько Telegram threads или пересылает старые сообщения, и adapter должен корректно выбрать active project/session.
- Пользователь подтверждает brief неявной фразой, и adapter должен различить correction request и explicit confirmation.
- Сообщение пользователя слишком длинное для одного Telegram send, и adapter должен отправить summary в нескольких user-readable сообщениях без потери смысла.
- Генерация concept pack завершилась частично или временно неудачно, и adapter должен сообщить корректный user-facing status, не выдавая внутренние пути или JSON dump.
- Пользователь возвращается после long pause, когда есть несколько historical brief versions, и adapter должен показать актуальный проектный контекст, а не произвольную старую версию.
- Пользователь присылает чувствительные данные, и adapter должен не только пропустить warning discovery runtime, но и показать человеку понятную просьбу прислать sanitized substitute.

## Requirements *(mandatory)*

### Functional Requirements

#### Telegram Adapter Runtime

- **FR-001**: System MUST accept Telegram user messages as one live follow-up adapter input for the factory business-analyst agent on `Moltis`.
- **FR-002**: System MUST map one Telegram user/chat conversation to one active factory project context or explicit project-selection state.
- **FR-003**: System MUST forward user messages into the existing discovery runtime from `023`'s upstream dependency `022-telegram-ba-intake` instead of reimplementing discovery logic in the adapter.
- **FR-004**: System MUST return one user-facing next step after each Telegram turn, such as a follow-up question, clarification, brief summary, confirmation request, or downstream status.
- **FR-005**: System MUST keep Telegram interaction semantics aligned with the discovery runtime contract, including `next_action`, `next_topic`, `next_question`, `resume_context`, and reopen behavior.
- **FR-006**: System MUST support explicit Telegram intents for starting a new project, continuing the active project, and confirming the current brief version.
- **FR-007**: System MUST present business-readable Russian responses by default and MUST NOT expose raw internal JSON to the end user.

#### Brief Review And Confirmation In Telegram

- **FR-008**: System MUST render a reviewable brief summary into Telegram-readable messages when the discovery runtime reaches `awaiting_confirmation`.
- **FR-009**: Users MUST be able to request brief corrections conversationally from Telegram without editing files or using CLI tools.
- **FR-010**: System MUST require explicit confirmation from Telegram before treating the current brief version as confirmed.
- **FR-011**: System MUST support reopening a previously confirmed brief from Telegram while preserving `confirmation_history` and `handoff_history`.

#### Automatic Handoff And Concept Pack Delivery

- **FR-012**: When a Telegram conversation reaches a ready `factory_handoff_record`, system MUST automatically invoke the existing `agent-factory-intake.py` bridge.
- **FR-013**: After successful intake, system MUST automatically invoke the existing concept-pack generation flow from `agent-factory-artifacts.py`.
- **FR-014**: System MUST publish the generated project doc, agent spec, and presentation back to the user through Telegram as downloadable or retrievable artifacts.
- **FR-015**: System MUST preserve provenance from Telegram conversation to discovery session, confirmed brief, handoff record, and generated concept artifacts.
- **FR-016**: System MUST block downstream concept-pack generation when the current brief is unconfirmed, reopened, superseded, or otherwise not handoff-ready.

#### User-Facing Status And Safety

- **FR-017**: System MUST provide concise user-facing status updates for discovery progress, confirmation state, handoff state, and concept-pack delivery state.
- **FR-018**: System MUST hide filesystem paths, stack traces, secrets, and internal factory evidence from Telegram user messages.
- **FR-019**: System MUST surface sanitized-data warnings from the discovery runtime in plain language when user examples appear unsafe for prototype use.
- **FR-020**: System MUST keep Telegram adapter responsibilities limited to transport, session routing, delivery, and user-facing presentation while leaving business-analysis and factory-generation logic to the existing runtimes.

### Key Entities *(include if feature involves data)*

- **TelegramAdapterSession**: The transport-level binding between Telegram user/chat context and the active factory project/session.
- **ActiveProjectPointer**: The current project selection state for one Telegram user, including whether the user is in `new`, `active`, `awaiting_confirmation`, or `handoff_running` flow.
- **TelegramDeliveryArtifact**: A user-facing file or message bundle published back into Telegram, such as brief summary, project doc, spec, or presentation.
- **TelegramCommandIntent**: One user-expressed control intent such as start project, continue session, confirm brief, reopen brief, or request current status.
- **FactoryConversationEnvelope**: The normalized transport payload that the Telegram adapter sends to the discovery runtime and receives back from it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A business user can go from a raw idea to the first live follow-up question entirely inside Telegram without operator shell access.
- **SC-002**: A business user can complete `raw idea -> confirmed brief` inside one Telegram conversation without manual file editing or JSON preparation.
- **SC-003**: 100% of Telegram-triggered downstream concept-pack runs are blocked until the active brief version is explicitly confirmed.
- **SC-004**: In pilot runs, 100% of successful Telegram handoffs deliver all 3 concept-pack artifacts back to the user without manual operator copy-paste.
- **SC-005**: Resumed Telegram sessions do not re-ask already confirmed topics unless the brief was explicitly reopened.
- **SC-006**: 0 Telegram user messages expose internal filesystem paths, secrets, or raw stack traces in normal failure handling.

## Assumptions

- The current repository already contains the reusable discovery runtime in `022-telegram-ba-intake` and the downstream factory pipeline in `020-agent-factory-prototype`.
- Telegram remains a prepared follow-up adapter because transport groundwork already exists in the repo, even though the primary near-term demo path moved to `024-web-factory-demo-adapter`.
- Russian remains the default user language for pilot usage.
- User testing in this slice targets pilot-scale traffic and controlled allowlisted Telegram access, not broad public bot exposure.

## Dependencies

- Discovery runtime and contracts in [../022-telegram-ba-intake/spec.md](../022-telegram-ba-intake/spec.md).
- Downstream concept-pack flow in [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md).
- Primary web-first demo path in [../024-web-factory-demo-adapter/spec.md](../024-web-factory-demo-adapter/spec.md).
- Current Telegram/Moltis runtime configuration in [../../config/moltis.toml](../../config/moltis.toml).
- Existing Telegram operability/testing patterns in [../004-telegram-e2e-harness/spec.md](../004-telegram-e2e-harness/spec.md).
