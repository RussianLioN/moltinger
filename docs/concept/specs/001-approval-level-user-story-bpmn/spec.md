# Feature Specification: Сквозной путь фабрики от пользовательского кейса до исполнения цифровым сотрудником

**Feature Branch**: `001-approval-level-user-story-bpmn`  
**Created**: 2026-03-17  
**Status**: Draft  
**Scope Note**: Идентификатор feature сохранен, но артефакт расширен с approval-level baseline до полного end-to-end маршрута фабрики.
**Input**: User description: "Нужен весь сквозной путь фабрики: от кейса, заданного пользователем на поверхности, через оркестратор, фабрику, регистрацию цифрового сотрудника в реестре, публикацию в оркестратор и исполнение исходного кейса."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Закрыть кейс переиспользованием без новой разработки (Priority: P1)

Как сотрудник корпорации, я хочу получить результат по своему кейсу сразу через поверхность и оркестратор, если подходящий цифровой сотрудник уже существует и может быть безопасно маршрутизирован.

**Why this priority**: Это самый быстрый путь к первой полезности и базовая проверка того, что фабрика не производит новые активы без необходимости.

**Independent Test**: История independently testable, если новый пользовательский кейс проходит через поверхность и оркестратор, находится routeable-актив, кейс исполняется и результат возвращается пользователю без запуска нового производственного трека.

**Acceptance Scenarios**:

1. **Given** пользователь отправил кейс на поверхность, **When** оркестратор находит опубликованный и routeable цифровой сотрудник с подходящим `capability_scope`, **Then** кейс маршрутизируется на существующий актив без передачи в фабрику.
2. **Given** кейс исполнен существующим активом, **When** результат доставлен пользователю, **Then** система фиксирует завершение кейса и запускает базовый слой feedback/effect tracking.
3. **Given** оркестратор знает тип решения, но published capability временно недоступен, **When** routeable-актива нет, **Then** кейс возвращается в фабрику по `factory_reentry_policy`, а не теряется на поверхности.

---

### User Story 2 - Построить новый цифровой сотрудник, если готового маршрута нет (Priority: P2)

Как фабрика, я хочу принять кейс, квалифицировать его, собрать пакет артефактов и провести его через согласование и production, чтобы создать новый routeable цифровой сотрудник.

**Why this priority**: Это центральный производственный путь фабрики, который превращает неудовлетворенный спрос в новый reusable-актив.

**Independent Test**: История independently testable, если для кейса без готового routeable-решения фабрика создает инициативу, проходит подтверждение, approval, production и регистрирует новый актив в едином реестре исполняемых сущностей.

**Acceptance Scenarios**:

1. **Given** оркестратор не находит готовый routeable-актив, **When** кейс передается в фабрику, **Then** фабрика регистрирует спрос, выполняет архитектурную квалификацию и создает карту инициативы.
2. **Given** фабрика определила, что нужен новый производственный трек, **When** собран первый пакет артефактов и пользователь подтверждает понимание, **Then** кейс передается в согласовательный контур.
3. **Given** пакет согласован и принят во 2-й контур, **When** production создает актив и подтверждает intake, **Then** новый цифровой сотрудник регистрируется в едином реестре исполняемых активов с governance, ownership и capability-атрибутами.

---

### User Story 3 - Опубликовать новый актив в оркестратор и исполнить исходный кейс (Priority: P3)

Как фабрика и оркестратор, мы хотим после создания актива опубликовать его в operational projection и повторно маршрутизировать исходный кейс, чтобы пользователь получил результат уже от нового цифрового сотрудника.

**Why this priority**: Создание актива без публикации и повторного исполнения исходного кейса не дает замкнутого end-to-end результата.

**Independent Test**: История independently testable, если новый актив становится publishable, попадает в operational projection оркестратора, получает исходный кейс и возвращает пользователю результат.

**Acceptance Scenarios**:

1. **Given** новый актив создан и зарегистрирован, **When** его class, governance, ownership health и routeability позволяют публикацию, **Then** capability-узел публикуется в operational projection оркестратора.
2. **Given** capability опубликован, **When** исходный кейс повторно запускается через оркестратор, **Then** он маршрутизируется уже на нового цифрового сотрудника.
3. **Given** новый актив исполнил исходный кейс, **When** пользователь получает результат, **Then** фабрика фиксирует `готово` и переводит кейс в `на оценке эффекта`.

---

### User Story 4 - Управлять исключениями, эффектом, scaling и correction loops (Priority: P4)

Как фабрика, я хочу обрабатывать unclear requests, альтернативные исходы, возвраты, rollback и correction loops, чтобы весь маршрут оставался управляемым и не ломал reuse-контур.

**Why this priority**: Реальный factory flow не ограничивается happy path; без exception handling и effect loops модель будет непригодна для эксплуатации.

**Independent Test**: История independently testable, если кейс можно перевести в facilitated interview, заморозку, fallback/alternative, correction cycle или scaling path без потери lineage и исходного контекста.

**Acceptance Scenarios**:

1. **Given** пользователь сформулировал кейс неясно, **When** фасилитируемое интервью не приводит к достаточной ясности, **Then** кейс замораживается с сохранением контекста и возможностью разморозки.
2. **Given** созданный или уже существующий актив показывает плохой эффект или проблемное поведение, **When** мониторинг фиксирует отклонение, **Then** фабрика открывает correction loop или новый improvement-case, а не меняет production-контур задним числом.
3. **Given** исходный запрос безопаснее закрыть альтернативой, fallback или процессной инициативой, **When** новый цифровой сотрудник не нужен или недопустим, **Then** кейс закрывается допустимой альтернативой с явным business-summary.

---

### Edge Cases

- Оркестратор знает published capability, но под ним временно нет routeable-актива, и кейс должен вернуться в фабрику через `factory_reentry_policy`.
- Кейс требует нового актива, но подтвержденного `primary operational owner` для корпоративного reuse нет, поэтому актив не может быть опубликован как полноценный corporate-reuse asset.
- Пользователь меняет смысл кейса после показа summary, и фабрика должна пересобрать initiative map, а не продолжать старый маршрут вслепую.
- Approval contour и production принимают разные решения о готовности пакета, что создает двойной возврат на доработку.
- Актив успешно выполнен для первого кейса, но effect tracking показывает слабую пользу, и кейс должен перейти в корректировку вместо фиктивного успеха.
- Локальный актив начинает массово переиспользоваться и должен быть переведен в более высокий класс, не ломая действующий routing.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Сквозной процесс MUST начинаться с пользовательского кейса на внешней поверхности, а не с внутреннего шага фабрики.
- **FR-002**: Оркестратор MUST сначала проверять operational projection доступных сущностей и правил маршрутизации, а не весь внутренний граф фабрики.
- **FR-003**: Если опубликованный и routeable актив покрывает кейс, оркестратор MUST закрывать потребность переиспользованием без запуска нового производственного трека.
- **FR-004**: Если published capability известен, но routeable-актива сейчас нет, система MUST возвращать кейс в фабрику по `factory_reentry_policy`.
- **FR-005**: Если готового решения нет, фабрика MUST регистрировать кейс в реестре спроса и запускать архитектурную квалификацию.
- **FR-006**: Архитектурная квалификация MUST нормализовать формулировку кейса, создавать summary и карту инициативы.
- **FR-007**: Если кейс недостаточно ясен, фабрика MUST запускать facilitated interview, а при сохранении неясности переводить кейс в `заморожен` без потери контекста.
- **FR-008**: После квалификации фабрика MUST различать по крайней мере три исхода: reuse/alternative, новый цифровой сотрудник, более высокий process-level маршрут.
- **FR-009**: Если выбран путь нового цифрового сотрудника, фабрика MUST собирать минимальный пакет артефактов первого этапа, включая BPMN, пользовательскую историю, спецификацию и проектную документацию.
- **FR-010**: Перед передачей на внешнее согласование фабрика MUST получить подтверждение пользователя о корректности понимания кейса и proposed route.
- **FR-011**: Если нужен новый актив, процесс MUST включать внешний approval contour с исходами `approve`, `revise/resubmit`, `escalate`, `defer/close with alternative`.
- **FR-012**: После одобрения фабрика MUST передавать согласованный пакет во 2-й контур и сохранять ownership handoff за фабрикой.
- **FR-013**: Production contour MUST либо принять пакет и начать исполнение, либо вернуть пакет в фабрику на доработку, не общаясь напрямую с пользователем.
- **FR-014**: После создания нового актива фабрика MUST регистрировать его в едином реестре исполняемых активов как минимум с атрибутами `asset_type`, `capability_scope`, `status`, `class`, `governance_level`, `ownership_health_state`, `routeable` и `lineage_links`.
- **FR-015**: Актив MUST получать class/governance/ownership-параметры до публикации; для корпоративного reuse без подтвержденного `primary operational owner` публикация не допускается, кроме low-risk исключений.
- **FR-016**: Оркестратор MUST видеть только опубликованную operational projection capability-layer, а не полный внутренний реестр.
- **FR-017**: Публикация capability в оркестратор MUST зависеть от `routeable`, `capability_scope`, `status`, `class`, `ownership_health_state`, `availability_scope` и `routing_policy`.
- **FR-018**: После публикации нового актива система MUST повторно маршрутизировать исходный пользовательский кейс через оркестратор к новому цифровому сотруднику.
- **FR-019**: Исполнение кейса MUST завершаться возвратом результата пользователю через поверхность/оркестратор, а не внутренними production-каналами.
- **FR-020**: После исполнения кейса система MUST фиксировать `готово`, запускать `на оценке эффекта` и собирать feedback, reuse-сигналы и признаки проблемного поведения.
- **FR-021**: Если effect tracking показывает ухудшение, слабую пользу или проблемное поведение актива, фабрика MUST запускать correction loop, rollback or improvement-case вместо прямого изменения работающего контура.
- **FR-022**: Если актив подтверждает результат и reuse-потенциал, фабрика MUST поддерживать scaling, segmentation и controlled rollout без утраты lineage.
- **FR-023**: Альтернативные и fallback-исходы MUST описываться как допустимые финалы с явным business-summary и без скрытия причины отказа от нового актива.
- **FR-024**: Спецификация MUST использовать канонические lifecycle-статусы кейса и актива: `зарегистрирован`, `требует подтверждения пользователя`, `на согласовании`, `в производстве`, `готово`, `на оценке эффекта`, `на корректировке`, `доступен`, `проблемный`, `выведен из использования`.
- **FR-025**: Любое изменение уже работающего актива или уже завершенного production-маршрута MUST оформляться как новый кейс или correction-cycle с сохранением lineage, а не как молчаливое редактирование задним числом.
- **FR-026**: Сквозная спецификация MUST ссылаться на канонический BPMN 2.0 артефакт, который покрывает direct reuse, factory creation, approval, production, registry, publication, re-routing, execution и effect loops.
- **FR-027**: Допущения, зависимости и open questions MUST быть отделены от принятых правил, чтобы `command-speckit-plan` мог использовать спецификацию как стабильный baseline.

### Key Entities *(include if feature involves data)*

- **Кейс**: пользовательский запрос, проходящий путь от surface-intake через reuse или factory-route к результату, effect tracking и correction/scaling.
- **Инициатива**: управленческая сущность, возникающая из кейса и ведущая новый трек создания, изменения или масштабирования решения.
- **Approval Package**: пакет артефактов первого этапа фабрики, который подтверждает понимание кейса и готовность к производству.
- **Цифровой сотрудник**: исполняемый актив типа `digital_employee`, который после регистрации и публикации может получать кейсы от оркестратора.
- **Registry Record**: запись в едином реестре исполняемых активов, содержащая жизненный цикл, class, governance и routing-атрибуты актива.
- **Published Capability Node**: опубликованный в operational projection capability-узел, по которому оркестратор определяет возможность маршрутизации.
- **Execution Result**: результат исполнения кейса существующим или новым цифровым сотрудником, возвращаемый пользователю.
- **Effect Evaluation**: слой подтверждения пользы, reuse-потенциала, проблемности и необходимости correction/scaling loops.

### Assumptions & Dependencies *(include if relevant)*

- **Assumption A1**: Поверхность и внешний оркестратор уже существуют как единая front-door для сотрудников корпорации.
- **Assumption A2**: Внутренняя модель фабрики остается source of truth, а BPMN и Markdown-артефакты являются производными, но канонизированными входами для дальнейшего planning.
- **Assumption A3**: Сквозной маршрут может завершаться как прямым reuse, так и созданием нового актива; оба пути считаются полноценными исходами фабрики.
- **Dependency D1**: Канонические роли, lifecycle-статусы, ownership rules, capability-layer и KPI-слой зависят от документа `docs/concept/asc-ai-fabrique-2-0-user-story-q-and-a.md`.
- **Dependency D2**: Полный new-asset path зависит от production-контура, который умеет создать актив, зарегистрировать его и подготовить к публикации.
- **Dependency D3**: Публикация в оркестратор зависит от operational projection, capability taxonomy и governance-правил, которые еще предстоит детализировать schema-level артефактами.

### Open Questions *(include only if truly unresolved)*

- **OQ-001**: Какой формальный schema-level контракт должен описывать единый реестр активов, published capability-layer и operational asset projection для оркестратора?
- **OQ-002**: Какие SLA, пороги тревоги и пороги эскалации должны применяться на стадиях qualification, approval, publication и effect evaluation?
- **OQ-003**: Где проходит точная граница между новым цифровым сотрудником, сегментной веткой существующего актива и process-level инициативой более высокого порядка?

## Canonical BPMN 2.0 Basis *(mandatory for this feature)*

**Canonical Artifact**: `specs/001-approval-level-user-story-bpmn/factory-e2e.bpmn`
**Supporting Zoom-In**: `specs/001-approval-level-user-story-bpmn/approval-level.bpmn`

### Process Boundary

- **Start trigger**: пользователь отправляет кейс на внешнюю поверхность.
- **End states in scope**:
  - кейс успешно закрыт существующим или новым цифровым сотрудником и переведен в effect tracking;
  - кейс заморожен до нового цикла уточнения;
  - кейс закрыт допустимой альтернативой;
  - кейс завершен без подтвержденного результата после effect evaluation или correction loop.
- **Out of scope**:
  - низкоуровневая структура внутренних реестров;
  - численные KPI-пороги и SLA;
  - детальное техническое устройство production runtime.

### Phases

1. **Surface Intake and Orchestrator Routing**: приём кейса, проверка operational projection, direct reuse или factory reentry.
2. **Factory Qualification**: регистрация спроса, summary, initiative map, facilitated interview, выбор производственного или альтернативного маршрута.
3. **Approval and Production**: подтверждение пользователя, review, escalation, handoff во 2-й контур, создание нового актива.
4. **Registry and Publication**: регистрация актива, назначение class/owner/governance, публикация capability в оркестратор.
5. **Execution and Effect Loop**: повторный routing исходного кейса, исполнение, возврат результата, effect evaluation, scaling or correction.

### Roles and Lanes

- **Пользователь**: формулирует кейс, уточняет его и получает результат.
- **Поверхность и оркестратор**: принимает кейс, ищет published route, выполняет повторный routing и возвращает результат.
- **Фабрика**: квалифицирует кейс, строит инициативу, собирает пакет артефактов, владеет lineage и correction loops.
- **Группа верификаторов / стейкхолдеров**: принимает approval decision и escalation outcomes.
- **Production / Registry**: создает новый актив, регистрирует его и принимает решение о publishability.
- **Runtime / Monitoring**: исполняет кейс активом и измеряет эффект, reuse и признаки проблемности.

### Core Inputs

- пользовательский кейс;
- operational projection capability-layer;
- данные qualification и initiative map;
- approval package;
- production intake result;
- registry/publication state;
- execution result and effect signals.

### Core Outputs

- direct reuse result;
- approval and production decisions;
- registry record цифрового сотрудника;
- published capability in orchestrator;
- исполненный кейс и возвращенный пользователю результат;
- effect outcome, scaling signal or correction trigger.

### BPMN Gateways

- **Routeable solution exists?** Делит маршрут на direct reuse и factory-route.
- **Understanding sufficient?** Делит маршрут на qualification progress и facilitated interview/freeze.
- **New asset required?** Делит маршрут на alternative/fallback и production path.
- **User confirmed package?** Делит маршрут на approval flow и revision loop.
- **Approval decision?** Делит маршрут на approve, revise, escalate.
- **Escalation outcome?** Делит маршрут на approve, revise, defer/alternative.
- **Publication allowed?** Делит маршрут на publish и pre-publication correction.
- **Effect confirmed?** Делит маршрут на success, correction/improvement, no confirmed result.

### Responsibility Handoffs

- Пользователь передает кейс поверхности.
- Оркестратор либо исполняет кейс через существующий актив, либо передает его в фабрику.
- Фабрика передает approval package во внешний review.
- Review возвращает решение фабрике.
- Фабрика передает approved package в production.
- Production регистрирует актив и публикует capability обратно в operational layer оркестратора.
- Оркестратор повторно направляет исходный кейс уже на опубликованный актив.

### Approval-Level Zoom-In

- `approval-level.bpmn` детализирует подмаршрут от готового approval package до одного из финалов: `в производстве`, `заморожен`, `закрыт с альтернативой` или `opportunity frozen`.
- Zoom-in явно кодирует Q&amp;A-дополнения: `next step`, timeout/reminder/escalation, переназначение инициатора, безопасную альтернативу и owner search для self-generated инициатив.
- Этот под-артефакт остается производным от того же internal route, что и `factory-e2e.bpmn`, и не заменяет канонический E2E baseline.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Спецификация покрывает единую непрерывную цепочку от пользовательского кейса на поверхности до возвращенного пользователю результата и запуска effect tracking.
- **SC-002**: В спецификации явно различены direct reuse path и new-asset path, и оба пути приводят к управляемому исходу кейса.
- **SC-003**: Регистрация цифрового сотрудника в реестре, назначение governance/ownership и публикация в operational projection описаны как обязательные фазы, а не неявные последствия production.
- **SC-004**: Канонический BPMN 2.0 артефакт отражает не менее шести ролей/lanes и все ключевые ветки: reuse, qualification loop, approval, escalation, production return, publication, execution, correction/effect loop.
- **SC-005**: Открытые вопросы и schema-level неопределенности вынесены отдельно и не мешают переходу к `command-speckit-plan`.

## Planning Readiness *(mandatory)*

- Эта спецификация, `factory-e2e.bpmn` и `approval-level.bpmn` являются каноническим входом для последующих `command-speckit-plan` и `command-speckit-tasks`.
- Следующая фаза должна опираться на этот baseline при формализации data model реестров, published capability-layer, handoff contracts и decomposition по фазам процесса.
- Если в `plan` потребуется детализация, она должна развивать `Open Questions`, а не сужать уже зафиксированный сквозной маршрут.
