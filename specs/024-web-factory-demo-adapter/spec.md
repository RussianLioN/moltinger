# Feature Specification: Web Factory Demo Adapter

**Feature Branch**: `024-web-factory-demo-adapter`  
**Created**: 2026-03-14  
**Status**: Draft  
**Upstream Discovery Context**: [../022-telegram-ba-intake/spec.md](../022-telegram-ba-intake/spec.md)  
**Downstream Factory Context**: [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md)  
**Follow-up Transport Context**: [../023-telegram-factory-adapter/spec.md](../023-telegram-factory-adapter/spec.md)  
**Operational Baseline**: [../../docs/runbooks/clawdiy-deploy.md](../../docs/runbooks/clawdiy-deploy.md)  
**Input**: User description: "Зафиксировать pivot на web-first demo adapter и сделать первичный пользовательский demo path через отдельный subdomain вроде `asc.ainetic.tech`, чтобы бизнес-пользователь мог из корпоративного контура без Telegram/VPN ограничений пройти discovery-диалог, подтвердить brief и получить concept pack. Telegram из `023` остается follow-up adapter и не теряется как будущий transport scope."

## Clarifications

### Session 2026-03-14

- Q: Что становится primary demo path для ближайшей демонстрации фабрики? → A: Primary demo path становится web-first adapter на выделенном HTTPS subdomain по умолчанию `asc.ainetic.tech`; Telegram остается follow-up adapter backlog.
- Q: Является ли web UI новым агентом? → A: Нет. Фабричный агент по-прежнему реализован на `Moltis`, а web UI является только первым приоритетным demo adapter поверх уже существующего discovery/factory runtime.
- Q: Требуется ли для demo новый heavy frontend stack? → A: Нет. Для MVP этого slice достаточно thin web adapter с chat-like UX, стандартным HTTPS transport и загрузкой артефактов без обязательного нового SPA build stack.

### Session 2026-03-20

- Q: Что обязательно должно происходить сразу после `confirm brief`? → A: Правая панель должна автоматически раскрываться в режиме preview и показывать главный результат (`one_page_summary`), а не пустой контейнер.
- Q: Достаточно ли пересказа brief как результата OnePage? → A: Нет. OnePage обязан содержать фактическую суммаризацию приложенных данных и согласованных правил обработки, а не копию brief.
- Q: Можно ли считать accepted сценарий, если preview строится из mock fallback? → A: Нет. Mock/placeholder допустим только как явный failure state, но не как успешный post-brief результат.
- Q: Какие UX-паттерны обязательны для чата? → A: Sticky topbar с доступными контролами `Brief`/panel toggle, корректный scroll anchoring после send, единый индикатор работы агента, отсутствие дублей и service-noise в transcript.
- Q: Когда разрешено `confirm brief`? → A: Только после сбора обязательных параметров результата (`result_format`, `processing_algorithm`, `constraints`, `success_metrics`) и закрытия unresolved clarification.
- Q: Нужно ли требовать от пользователя отдельные подтверждения обезличенности входных примеров? → A: Нет. По умолчанию все пользовательские данные в этом прототипе считаются обезличенными; повторные доказательства/подтверждения не требуются.

## Scope Boundary

### In Scope

- Первый приоритетный пользовательский demo adapter для фабричного агента-бизнес-аналитика на `Moltis` через web UI.
- Отдельный human-facing HTTPS subdomain для controlled demo, по умолчанию `asc.ainetic.tech`.
- Chat-like web experience для нетехнического бизнес-пользователя:
  - старт нового проекта
  - multi-turn discovery interview
  - просмотр текущего статуса
  - reviewable requirements brief
  - внесение corrections
  - explicit confirmation
- Передача каждого пользовательского turn в уже реализованный discovery runtime из `022-telegram-ba-intake` без дублирования business-analysis логики.
- Автоматический downstream path после confirmed brief:
  - `factory_handoff_record`
  - `agent-factory-intake.py`
  - `agent-factory-artifacts.py`
- Browser download или browser-retrievable delivery для трех user-facing артефактов:
  - project doc
  - agent spec
  - presentation
- Resume после refresh/revisit и reopen confirmed brief без потери provenance.
- Минимальный demo access gate, пригодный для controlled corporate demo без полноценного enterprise auth rollout.
- User-facing status и failure messaging без repo paths, stack traces и внутреннего evidence dump.
- Сохранение `023-telegram-factory-adapter` как follow-up adapter scope и transport backlog, а не замена этого пакета.

### Out of Scope

- Замена discovery runtime из `022-telegram-ba-intake`.
- Замена downstream factory lifecycle из `020-agent-factory-prototype`, включая defense, swarm, playground и deploy.
- Полноценный product portal, generalized multi-tenant SaaS UI или enterprise IAM rollout.
- Обязательная websocket-only transport model; core demo path должен оставаться работоспособным через обычный HTTPS browser flow.
- Полная реализация Telegram adapter в этом slice; этот scope сохраняется в `023-telegram-factory-adapter`.
- Работа с несанитизированными production business data как обязательный сценарий demo.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Live Web Discovery Interview (Priority: P1)

Как бизнес-пользователь, я хочу открыть одну web-ссылку и начать диалог с фабричным агентом простыми словами, чтобы без Telegram, JSON и CLI описать, что именно нужно автоматизировать.

**Why this priority**: Пока нет browser-accessible user path, discovery runtime остается техническим контуром. Для ближайшей демонстрации важнее всего убрать зависимость от Telegram/VPN и дать понятный web вход.

**Independent Test**: Пользователь открывает demo URL, проходит первый discovery turn и получает следующий полезный вопрос от фабричного агента в браузере без shell-доступа и без мессенджера.

**Acceptance Scenarios**:

1. **Given** пользователь открыл demo subdomain и прошел минимальный access gate, **When** он описывает идею автоматизации в свободной форме, **Then** web adapter создает или выбирает project/session context и показывает первый follow-up question из discovery runtime.
2. **Given** пользователь отвечает следующим сообщением в web UI, **When** adapter передает ответ в discovery runtime, **Then** интерфейс показывает следующий question, clarification или summary без потери уже собранного контекста.
3. **Given** пользователь использует простой бизнес-язык, **When** runtime нормализует ответ, **Then** web UI показывает только business-readable результат, а не внутренние JSON-структуры.

---

### User Story 2 - Web Brief Review And Confirmation (Priority: P1)

Как бизнес-пользователь, я хочу просмотреть, исправить и подтвердить requirements brief прямо в браузере, чтобы фабрика не запускала следующий этап по неверно понятой идее.

**Why this priority**: Value demo возникает только если пользователь может закончить discovery до `confirmed brief` целиком внутри одного интерфейса, а не уходить в файлы или ручной copy-paste.

**Independent Test**: Пользователь доводит discovery до review state, просит исправить часть brief и затем явно подтверждает текущую версию прямо в web UI.

**Acceptance Scenarios**:

1. **Given** discovery runtime считает brief готовым к review, **When** web adapter получает `awaiting_confirmation`, **Then** он показывает readable summary и объясняет, как внести правку или подтвердить brief.
2. **Given** пользователь просит скорректировать часть brief, **When** adapter передает correction в discovery runtime, **Then** интерфейс показывает обновленную версию brief и новый confirmation prompt.
3. **Given** пользователь явно подтверждает brief, **When** adapter получает confirmed state, **Then** текущая версия фиксируется как confirmed и становится единственным валидным входом в downstream handoff.

---

### User Story 3 - Automatic Handoff And Artifact Downloads (Priority: P2)

Как бизнес-пользователь, я хочу после confirmation автоматически получить concept pack и скачать его прямо из web UI, чтобы сразу унести материалы на защиту без участия оператора.

**Why this priority**: Это превращает web demo из просто удобного discovery frontend в настоящий self-serve demo path для фабрики.

**Independent Test**: После `confirmed brief` adapter автоматически запускает downstream handoff/intake/artifacts path и показывает пользователю три downloadable артефакта в браузере.

**Acceptance Scenarios**:

1. **Given** brief подтвержден, **When** adapter получает `factory_handoff_record.handoff_status = ready`, **Then** он автоматически запускает downstream path без ручного вмешательства пользователя.
2. **Given** concept-pack generation завершилась успешно, **When** web UI обновляет состояние проекта, **Then** пользователь видит и скачивает `project doc`, `agent spec` и `presentation`.
3. **Given** downstream handoff еще не готов или generation завершилась ошибкой, **When** adapter сообщает статус, **Then** пользователь получает понятное краткое объяснение и следующий шаг без внутренних путей и stack traces.

---

### User Story 4 - Controlled Subdomain Demo Access (Priority: P2)

Как оператор фабрики, я хочу публиковать demo path на отдельном subdomain с минимальным контролем доступа, чтобы бизнес-пользователи могли открыть интерфейс из корпоративного браузера без зависимости от Telegram и сложного VPN-пути.

**Why this priority**: Даже хороший UI не решает задачу демонстрации, если его сложно опубликовать и стабильно открывать в нужном контуре. Надежный subdomain rollout здесь часть пользовательской ценности.

**Independent Test**: Оператор разворачивает demo stack на отдельном subdomain, открывает health/UI и выдает пользователю рабочую ссылку или access token без изменения downstream core.

**Acceptance Scenarios**:

1. **Given** оператор deploys demo adapter по same-host subdomain pattern, **When** пользователь открывает `asc.ainetic.tech`, **Then** он попадает в web demo path фабрики, а не в внутренний control plane или raw API.
2. **Given** доступ ограничен demo gate, **When** неавторизованный пользователь открывает URL, **Then** он получает controlled access prompt вместо внутренней ошибки или полного доступа.
3. **Given** demo adapter недоступен или unhealthy, **When** оператор проверяет состояние, **Then** у него есть явный health/status signal для диагностики.

---

### User Story 5 - Resume And Reopen In Browser (Priority: P3)

Как бизнес-пользователь, я хочу вернуться к проекту позже, увидеть текущий статус и при необходимости переоткрыть confirmed brief в браузере, чтобы не начинать весь процесс заново после внутреннего согласования.

**Why this priority**: Реальные обсуждения требований почти всегда прерываются. Resume/reopen делает web demo пригодным не только для разовой презентации, но и для реального пилота.

**Independent Test**: Пользователь refreshes page или возвращается позже по тому же demo path, видит актуальный контекст проекта и продолжает с нужного шага без повторного ответа на уже confirmed topics.

**Acceptance Scenarios**:

1. **Given** пользователь refreshes страницу или возвращается позже, **When** web adapter находит активную session/project pointer, **Then** он показывает resume summary и pending question, clarification или current status.
2. **Given** у проекта уже есть confirmed brief, **When** пользователь запрашивает изменение, **Then** adapter запускает reopen flow, а предыдущие confirmation/handoff записи остаются в истории.
3. **Given** пользователь после reopen снова подтверждает brief, **When** новая confirmed version становится ready, **Then** downstream handoff выполняется уже от новой версии, а старая остается traceable.

## Edge Cases

- Пользователь открывает один и тот же demo project в нескольких browser tabs, и adapter должен не терять active context и не дублировать downstream launch.
- Корпоративный proxy режет websocket или long-lived connection, и core chat flow должен продолжать работать через обычный HTTPS request/response path.
- Пользователь refreshes страницу в момент, когда adapter уже ждет clarification или confirmation.
- Brief summary слишком длинный для одного экрана или одной карточки, и UI должен разбить его на читаемые sections без потери смысла.
- Пользователь пытается скачать артефакты, пока generation еще идет или один из файлов еще не готов.
- Пользователь вводит явно чувствительные данные, уверенно распознанные runtime, и adapter должен показать plain-language warning и попросить заменить формулировку, но не требовать отдельных доказательств обезличенности.
- У проекта есть несколько historical brief versions, и UI должен явно показывать, какая версия current, какая archived и какая handoff-ready.

## Requirements *(mandatory)*

### Functional Requirements

#### Web Access And Sessioning

- **FR-001**: System MUST expose one dedicated HTTPS demo entrypoint for the factory business-analyst agent through a browser-accessible subdomain.
- **FR-002**: System MUST treat the web UI as an adapter over the factory agent on `Moltis`, not as a separate agent identity.
- **FR-003**: System MUST support one controlled demo access gate before the user enters an active factory project workspace.
- **FR-004**: System MUST map one browser session to one active factory project context or an explicit project-selection state.
- **FR-005**: System MUST forward user turns into the existing discovery runtime from `022-telegram-ba-intake` instead of reimplementing discovery logic in the web adapter.
- **FR-006**: System MUST return one user-facing next step after each browser turn, such as a follow-up question, clarification, brief summary, confirmation request, or downstream status.
- **FR-007**: System MUST keep the core demo path functional over standard HTTPS request/response semantics and MUST NOT require websocket-only transport for discovery, confirmation, or artifact download.
- **FR-008**: System MUST present business-readable Russian responses by default and MUST NOT expose raw internal JSON to the end user.

#### Brief Review And Confirmation

- **FR-009**: System MUST render a reviewable requirements brief into browser-readable sections when the discovery runtime reaches `awaiting_confirmation`.
- **FR-010**: Users MUST be able to request brief corrections conversationally from the browser without editing files or using CLI tools.
- **FR-011**: System MUST require explicit confirmation in the web UI before treating the current brief version as confirmed.
- **FR-012**: System MUST support reopening a previously confirmed brief from the browser while preserving `confirmation_history` and `handoff_history`.

#### Automatic Handoff And Artifact Delivery

- **FR-013**: When the web conversation reaches a ready `factory_handoff_record`, system MUST automatically invoke the existing `agent-factory-intake.py` bridge.
- **FR-014**: After successful intake, system MUST automatically invoke the existing concept-pack generation flow from `agent-factory-artifacts.py`.
- **FR-015**: System MUST publish the generated project doc, agent spec, and presentation back to the user as downloadable or browser-retrievable artifacts.
- **FR-016**: System MUST preserve provenance from browser conversation to discovery session, confirmed brief, handoff record, and generated concept artifacts.
- **FR-017**: System MUST block downstream concept-pack generation when the current brief is unconfirmed, reopened, superseded, or otherwise not handoff-ready.

#### Subdomain Demo Delivery And Safety

- **FR-018**: System MUST support deployment as a dedicated same-host subdomain demo surface that stays operationally separate from the main `moltis.ainetic.tech` runtime surface.
- **FR-019**: System MUST provide concise user-facing status updates for discovery progress, confirmation state, handoff state, and concept-pack delivery state.
- **FR-020**: System MUST hide filesystem paths, stack traces, secrets, and internal factory evidence from browser user messages.
- **FR-021**: System MUST surface plain-language safety warnings only when runtime confidently detects explicitly unsafe example content and MUST NOT require additional anonymization proofs by default.
- **FR-022**: System MUST provide an operator-visible health/status signal for the demo adapter without requiring direct inspection of user conversations.

#### Resume, Governance, And Adapter Boundaries

- **FR-023**: System MUST let the user resume the active project after page refresh or later revisit without losing already confirmed context.
- **FR-024**: System MUST keep web adapter responsibilities limited to access gating, session routing, user-facing rendering, download delivery, and operator-safe status publication while leaving business-analysis and factory-generation logic to the existing runtimes.
- **FR-025**: System MUST preserve semantic compatibility with future UI adapters and MUST NOT make `023-telegram-factory-adapter` obsolete as a follow-up transport slice.
- **FR-026**: System MUST support one project having multiple discovery and confirmation iterations without requiring the user to restart from an empty session each time.

#### Interaction Correctness, Brief Semantics, And Post-Brief Quality

- **FR-027**: System MUST show one visible agent-processing indicator bound to in-flight state and MUST clear it immediately on terminal success/error state.
- **FR-028**: System MUST keep a sticky workspace topbar with always-available `Brief` and right-panel toggle controls during vertical transcript scrolling.
- **FR-029**: After each user send action, system MUST preserve scroll anchoring on the active question and the latest user turn in both collapsed and expanded sidebar modes.
- **FR-030**: System MUST prevent duplicate user turns caused by repeated send actions while one request is already in-flight.
- **FR-031**: For `input_examples`, the first valid user-provided example (text or attachment) MUST close the topic by default and prevent repeated requests for anonymization proof or duplicate evidence.
- **FR-032**: Brief corrections MUST apply as section-targeted replacements/patches and MUST NOT duplicate content into unrelated sections or copy service/user helper phrases verbatim into canonical brief text.
- **FR-033**: System MUST block `confirm brief` until required output-design topics are captured: `result_format`, `processing_algorithm`, `constraints`, and `success_metrics` (or explicitly unresolved with visible risk flag).
- **FR-034**: Immediately after `confirm brief`, system MUST auto-open the right panel in preview mode for the primary artifact (`one_page_summary`).
- **FR-035**: Preview MUST render markdown artifacts as readable content and MUST NOT show empty preview when artifact content exists.
- **FR-036**: The generated `one_page_summary` MUST include synthesized facts from input data sources and agreed processing rules and MUST NOT be accepted when it is only a brief paraphrase.
- **FR-037**: Downstream handoff and artifact metadata MUST carry traceable provenance fields at minimum: `confirmed_brief_version`, `result_format`, `processing_algorithm`, `delivery_channel`, and source artifact references.

### Key Entities *(include if feature involves data)*

- **WebDemoSession**: The browser-bound adapter session that maps one user access context to one active factory project, brief state, and downstream status.
- **DemoAccessGrant**: One minimal access credential or operator-issued entry token that opens the controlled demo surface.
- **BrowserProjectPointer**: The current project-selection state for one browser session, including whether the user is in `new`, `active`, `awaiting_confirmation`, `handoff_running`, or `download_ready` flow.
- **WebConversationEnvelope**: The normalized user turn and adapter response payload that bridges the browser UI with the channel-neutral discovery runtime.
- **WebReplyCard**: One user-visible rendered unit in the web UI, such as a question, clarification, brief section, status card, or download prompt.
- **BriefDownloadArtifact**: One downloadable artifact exposed to the user after downstream generation, such as `project doc`, `agent spec`, or `presentation`.
- **WebDemoStatusSnapshot**: One operator-safe and user-safe projection of the current discovery, confirmation, handoff, and download state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A non-technical business user can go from a raw automation idea to the first follow-up question entirely inside the browser without Telegram, JSON, or CLI access.
- **SC-002**: A business user can complete `raw idea -> confirmed brief` inside one web interface without manual file editing or copy-paste between tools.
- **SC-003**: 100% of web-triggered downstream concept-pack runs are blocked until the active brief version is explicitly confirmed.
- **SC-004**: In pilot demos, a user inside the target corporate contour can open the demo URL in a standard browser and start the workflow without relying on Telegram availability or a messenger-specific VPN path.
- **SC-005**: In successful pilot runs, 100% of completed handoffs expose all 3 concept-pack artifacts as browser downloads from the same UI session.
- **SC-006**: Resumed web sessions do not re-ask already confirmed topics unless the brief was explicitly reopened.
- **SC-007**: 0 normal user-facing errors expose internal filesystem paths, secrets, or raw stack traces.
- **SC-008**: Operators can trace any downloaded concept pack back to the exact confirmed brief version and discovery session that produced it.
- **SC-009**: In pilot and regression runs, 100% of `confirm brief` events auto-open right-panel preview and show non-empty render for available markdown artifacts.
- **SC-010**: In validated synthetic scenarios, 0 completed sessions produce `one_page_summary` outputs that are only brief restatements without source-derived facts.
- **SC-011**: In regression suite runs, 0 accepted `input_examples` turns trigger repeated anonymization-proof requests or duplicate evidence prompts.

## Assumptions

- The current repository already contains the reusable discovery runtime in `022-telegram-ba-intake` and the downstream factory pipeline in `020-agent-factory-prototype`.
- `023-telegram-factory-adapter` remains valuable as the prepared follow-up transport slice after the web-first demo path is in place.
- The default demo hostname is `asc.ainetic.tech`, but deployment-specific values may be overridden by environment-specific config later.
- Pilot users can work with sanitized or surrogate examples instead of production-sensitive data.
- For the nearest demo, a lightweight access gate is sufficient; full SSO or enterprise identity rollout is deferred.

## Dependencies

- Discovery runtime and contracts in [../022-telegram-ba-intake/spec.md](../022-telegram-ba-intake/spec.md).
- Downstream concept-pack flow in [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md).
- Telegram follow-up transport scope preserved in [../023-telegram-factory-adapter/spec.md](../023-telegram-factory-adapter/spec.md).
- Same-host subdomain deployment pattern in [../../docker-compose.clawdiy.yml](../../docker-compose.clawdiy.yml) and [../../docs/runbooks/clawdiy-deploy.md](../../docs/runbooks/clawdiy-deploy.md).
