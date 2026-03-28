# Feature Specification: Telegram Cloneable Agent

**Feature Branch**: `038-telegram-cloneable-agent`  
**Created**: 2026-03-29  
**Status**: Draft  
**Input**: User description: "Нужно спроектировать cloneable Moltis/OpenClaw Telegram-агента для long-running задач без типовых болезней transport/runtime path: лёгкий и безопасный user-facing Telegram lane, тяжёлая работа в background/worker lane, явная и надёжная completion delivery, durable state вне chat history, практический шаблон навыка “следить за новой версией и уведомлять пользователя”, учёт рисков `Activity log`, tool-heavy silence, `90s` watchdog, routing/session contamination, слабого heartbeat notify и direct-send fallback, плюс authoritative UAT/verification contract для long-running Telegram path."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Telegram Safely Hands Off Heavy Work (Priority: P1)

Пользователь может из Telegram запустить долгую задачу вроде исследования большого сайта, чтения крупной документации или многошагового анализа, не заставляя user-facing lane зависать в одном длинном turn и не получая служебный `Activity log` вместо нормального ответа.

**Why this priority**: Это минимальный полезный срез. Пока Telegram-вход не стал тонким и безопасным, вся остальная long-running логика остаётся ненадёжной.

**Independent Test**: Отправить в Telegram заведомо тяжёлый запрос, требующий длительной работы, и подтвердить, что user-facing lane быстро возвращает короткий ack, переводит исполнение в worker lane и не публикует raw tool/progress traces.

**Acceptance Scenarios**:

1. **Given** пользователь просит “изучи весь сайт и верни вывод”, **When** запрос попадает в Telegram, **Then** user-facing lane быстро отвечает коротким ack и переводит тяжёлую работу в отдельный worker lane вместо одного длинного синхронного Telegram-turn.
2. **Given** тяжёлая работа уже переведена в background path, **When** пользователь видит первый ответ в Telegram, **Then** в этом ответе нет `Activity log`, raw tool names, raw shell commands или других служебных следов выполнения.
3. **Given** во время активной long-running задачи пользователь отправляет ещё одно тяжёлое сообщение, **When** система принимает решение по новой нагрузке, **Then** она явно сообщает, что запрос поставлен в очередь, присоединён к текущей работе, отклонён или требует замены активной задачи.

---

### User Story 2 - Completion Delivery Is Explicit And Reliable (Priority: P1)

Пользователь получает отдельное, явное и надёжное уведомление о завершении long-running задачи даже тогда, когда исходный Telegram-turn уже завершился, implicit reply path деградировал или исходный routing context нужно восстановить из durable state.

**Why this priority**: Надёжный background path бесполезен, если результат теряется по дороге назад к пользователю.

**Independent Test**: Запустить background worker с искусственно задержанным завершением, затем проверить, что итог доставляется отдельным completion-сообщением через explicit delivery path, а при отказе основного пути срабатывает fallback.

**Acceptance Scenarios**:

1. **Given** worker lane завершил задачу после окончания исходного Telegram-turn, **When** результат готов, **Then** пользователь получает отдельное completion-сообщение с кратким итогом и понятным статусом задачи.
2. **Given** основной delivery path не смог довести completion до пользователя, **When** система пытается завершить доставку, **Then** она использует сохранённый route context и direct-send fallback вместо тихой потери результата.
3. **Given** worker lane завершился с ошибкой, timeout или невозможностью продолжить, **When** выполнение останавливается, **Then** пользователь получает явное финальное уведомление о неуспехе, а оператор получает диагностический сигнал.

---

### User Story 3 - Version Watch Template Uses Durable State Instead Of Chat History (Priority: P1)

Оператор может клонировать практический шаблон навыка “следить за новой версией и уведомлять пользователя”, где scheduled/background monitor хранит версионное состояние и delivery ledger вне chat history, не зависит только от одной сессии и не шлёт дубликаты.

**Why this priority**: Пользователь отдельно попросил практический cloneable шаблон именно для version watching. Это один из самых частых и показательных long-running сценариев.

**Independent Test**: Прогнать monitor в scheduler mode на фикстурах “новая версия”, “та же версия”, “ошибка источника” и подтвердить duplicate-safe уведомления и независимость состояния от chat history.

**Acceptance Scenarios**:

1. **Given** пользователь включил мониторинг новой версии, **When** scheduler видит новый version fingerprint, **Then** система отправляет одно уведомление и помечает этот fingerprint как уже доставленный.
2. **Given** scheduler снова видит тот же fingerprint, **When** monitor повторно выполняется, **Then** уведомление подавляется как уже доставленное.
3. **Given** monitor запускается в isolated cron/custom session, **When** сессия ротируется, heartbeat меняется или chat history очищается, **Then** состояние последней известной версии и история доставки не теряются.

---

### User Story 4 - User Can Interrupt, Queue, Replace, Or Inspect A Running Job (Priority: P2)

Пользователь или оператор может безопасно узнать статус, отменить активную задачу, заменить её новой или поставить новую задачу в очередь, не загрязняя `main`/DM session и не создавая неуправляемое смешивание маршрутов.

**Why this priority**: Long-running path без interrupt/queue policy быстро превращается в хаос из overlapping задач и загрязнённой истории.

**Independent Test**: Во время активной задачи последовательно отправить команды статуса, отмены, замены и ещё один тяжёлый запрос, после чего проверить, что durable state и Telegram ответы отражают выбранную queue/interrupt policy.

**Acceptance Scenarios**:

1. **Given** worker lane уже работает, **When** пользователь запрашивает статус, **Then** система отвечает по данным из durable state, а не пытается реконструировать статус только из chat history.
2. **Given** активная задача уже идёт, **When** пользователь просит отменить или заменить её, **Then** система применяет явную interrupt policy и сообщает результат этой операции пользователю.
3. **Given** во время активной задачи приходит новое тяжёлое сообщение, **When** queue policy принимает решение, **Then** в Telegram фиксируется, поставлена ли новая работа в очередь, объединена ли она с текущей, отклонена или требует ручного подтверждения.

---

### User Story 5 - Watchdog Detects Stalls, Looping, And Delivery Degradation (Priority: P2)

Оператор получает отдельный health/watchdog contract для worker lane и Telegram delivery path, чтобы зависания, отсутствие прогресса, слабый heartbeat notify, delivery drift и routing contamination фиксировались как явные состояния, а не как “бот просто замолчал”.

**Why this priority**: Без watchdog policy long-running задачи деградируют в тишину, а пользователь интерпретирует это как поломку или исчезновение агента.

**Independent Test**: Искусственно воспроизвести stalled worker, repeated no-progress loop и broken delivery path, затем подтвердить, что watchdog поднимает отдельные сигналы и задача остаётся диагностируемой и retryable.

**Acceptance Scenarios**:

1. **Given** worker не обновлял прогресс дольше разрешённого порога, **When** watchdog проверяет состояние, **Then** система помечает задачу stalled/investigate и поднимает явный health signal.
2. **Given** worker зациклился на одинаковых действиях без прогресса, **When** loop-detection policy срабатывает, **Then** выполнение останавливается, ослабляется или переводится в `needs_assistance`, а не продолжает бесконтрольно тратить ресурсы.
3. **Given** completion уже был получен worker lane, но Telegram delivery path не подтвердил доставку пользователю, **When** watchdog переоценивает состояние, **Then** он отличает delivery problem от worker failure и инициирует retry/fallback вместо молчаливой потери результата.

---

### User Story 6 - Authoritative UAT Fails Closed On Telegram Long-Running Regressions (Priority: P2)

Оператор может прогнать authoritative UAT/verification contract, который отдельно доказывает корректность branch/fixture path и отдельно доказывает live remote truth для Telegram, не путая локальную герметичную проверку с live-proof.

**Why this priority**: Для long-running Telegram path обычной happy-path проверки недостаточно. Нужен fail-closed контракт именно на transport/runtime деградации.

**Independent Test**: Выполнить герметичную contract suite и отдельную authoritative remote smoke/UAT suite, затем подтвердить, что они ловят `Activity log` leakage, lost completion, route contamination, duplicate notify и попытку держать тяжёлую задачу в одном sync-turn дольше безопасного порога.

**Acceptance Scenarios**:

1. **Given** long-running Telegram path прогоняется на фикстурах и локальных контрактах, **When** появляются `Activity log`, raw tool traces, duplicate completion или route contamination, **Then** hermetic suite падает fail-closed.
2. **Given** live remote Telegram path проверяется отдельно, **When** authoritative smoke/UAT завершается, **Then** он либо подтверждает корректную user-facing delivery без leakage, либо явно фиксирует live runtime failure.
3. **Given** задача требует больше типового safe sync-window, **When** UAT воспроизводит сценарий heavy/tool-silent workload, **Then** система обязана показать ранний ack + отдельный background completion, а не пытаться удерживать один синхронный turn до timeout.

### Edge Cases

- Что происходит, если пользователь инициирует вторую long-running задачу до завершения первой?
- Что происходит, если worker завершился успешно, но completion reply path потерял исходный thread/topic/account context?
- Что происходит, если cron/worker использует isolated session и `session_state` больше не содержит нужную историю?
- Что происходит, если heartbeat срабатывает, но `target`/delivery policy не позволяет доставить completion пользователю?
- Что происходит, если Telegram polling channel временно деградирует, а worker уже накопил финальный результат?
- Что происходит, если transport-level path показывает `Activity log`, хотя финальный assistant reply в истории чистый?
- Что происходит, если пользователь просит статус после compaction/reset в основной сессии?
- Что происходит, если version watcher видит новую версию, но уведомление отправить не удалось и fingerprint не должен считаться полностью доставленным?

## Requirements *(mandatory)*

### Functional Requirements

#### Lane Architecture

- **FR-001**: Система MUST разделять `user-facing Telegram lane` и `worker/background lane` как разные архитектурные контуры с разной моделью исполнения и рисков.
- **FR-002**: `user-facing Telegram lane` MUST быстро подтверждать получение long-running запроса и MUST NOT пытаться завершить тяжёлое browser/search/MCP-heavy исследование в том же синхронном Telegram-turn.
- **FR-003**: `user-facing Telegram lane` MUST оставаться лёгким и безопасным по tool surface и MUST трактовать `Activity log`, raw tool names, raw shell commands и другие служебные следы как failure signature.
- **FR-004**: Тяжёлая работа MUST исполняться через отдельный background/isolated worker path, выбранный по классу задачи.
- **FR-005**: Архитектура MUST поддерживать как минимум следующие worker patterns: isolated sub-agent/session, isolated cron or custom session monitor, и detached process/workflow path для script-heavy задач.

#### Durable State Model

- **FR-006**: Система MUST хранить job state и monitor state вне chat history.
- **FR-007**: `session_state` MAY использоваться для per-user conversational preferences, но durable job/monitor/version state MUST NOT зависеть только от `session_state`, если задача работает в isolated/background path.
- **FR-008**: Durable job state MUST включать идентификатор задачи, краткое описание запроса, phase/status, last-progress timestamp, route context, delivery attempts и ссылки на итоговые артефакты.
- **FR-009**: Durable monitor state MUST хранить последний известный version fingerprint и per-target delivery ledger.
- **FR-010**: Система MUST уметь отвечать на status/cancel/resume запросы после reset, compaction или смены session id, опираясь на durable state.

#### Notify / Delivery Model

- **FR-011**: Completion delivery MUST быть отдельной явной операцией, а не неявным хвостом исходного long-running turn.
- **FR-012**: Delivery model MUST сохранять channel/account/thread routing context, достаточный для корректной финальной доставки результата пользователю.
- **FR-013**: Система MUST предпочитать explicit delivery/direct send path для completion-сообщений и MUST иметь retry/fallback contract, если основной путь не сработал.
- **FR-014**: Потеря implicit reply, weak heartbeat notify или announce drift MUST NOT приводить к молчаливой потере финального результата.
- **FR-015**: Version-watch notifications MUST быть duplicate-safe для одного и того же version fingerprint.

#### Interrupt / Queue Policy

- **FR-016**: Система MUST определить одну авторитетную queue/interrupt policy для новых входящих сообщений, пока worker lane активен.
- **FR-017**: Queue/interrupt policy MUST поддерживать как минимум `status`, `cancel`, `replace`, `queue/steer`, и `reject with explanation`.
- **FR-018**: `user-facing Telegram lane` MUST явно сообщать пользователю, что произошло с новым запросом: принят, объединён, поставлен в очередь, отклонён или требует ручной замены.
- **FR-019**: Queue/interrupt policy MUST не загрязнять `main`/DM session внутренним состоянием worker lane и MUST не создавать routing/session contamination между независимыми задачами.

#### Health-Check / Watchdog Policy

- **FR-020**: Система MUST иметь отдельный health/watchdog contract для no-progress timeout, delivery failure, repeated no-progress loops и channel degradation.
- **FR-021**: Watchdog MUST использовать progress/update semantics, а не только queue age или время с момента создания задачи.
- **FR-022**: Heartbeat MAY использоваться как вспомогательный awareness layer, но MUST NOT быть единственным scheduler или единственным completion-delivery механизмом для long-running path.
- **FR-023**: Система MUST предусматривать direct-send fallback, если heartbeat/announce/system-event path недостаточно надёжен.

#### Authoritative UAT / Verification

- **FR-024**: Система MUST иметь authoritative Telegram UAT contract специально для long-running path.
- **FR-025**: UAT MUST fail closed на `Activity log` leakage, raw tool/progress traces, lost completion delivery, duplicate completion delivery, route/session contamination и попытку держать тяжёлую задачу в одном sync-turn дольше safe window.
- **FR-026**: Hermetic fixtures MAY подтверждать branch correctness, но MUST NOT использоваться как доказательство того, что shared remote Telegram service работает сейчас.
- **FR-027**: Отдельный remote smoke/UAT MAY подтверждать, что live Telegram path работает сейчас, но MUST NOT считаться главным доказательством correctness branch/refactor logic.
- **FR-028**: Фича MUST предоставить практический cloneable template для навыка “следить за новой версией и уведомлять пользователя”.
- **FR-029**: Cloneable template MUST описывать выбор worker pattern, durable state contract, delivery/fallback contract и UAT obligations так, чтобы его можно было повторно использовать для других Moltis/OpenClaw Telegram-агентов.

### Key Entities

- **TelegramUserLane**: Тонкий безопасный пользовательский контур, который принимает Telegram requests, быстро отвечает и делегирует тяжёлую работу.
- **WorkerLaneRun**: Отдельное long-running выполнение, изолированное от user-facing lane и управляемое собственным lifecycle/status.
- **DurableJobState**: Постоянное состояние конкретной long-running задачи с phase/status, progress timestamp, route context и delivery history.
- **VersionMonitorState**: Durable состояние monitor-задачи, хранящее last-seen fingerprint, retryability и duplicate-suppression ledger.
- **DeliveryRouteContext**: Набор данных для explicit completion delivery: channel, target, account, thread/topic, correlation id.
- **DeliveryAttempt**: Одна попытка финальной доставки результата пользователю или оператору с outcome и retry metadata.
- **QueueDecision**: Явное решение по новому входящему сообщению при активном worker lane: accept, merge, queue, replace, reject, needs_confirmation.
- **WatchdogSignal**: Формализованный health event о stalled worker, broken delivery, loop detection или channel degradation.
- **CloneableAgentTemplate**: Повторно используемый шаблон навыка/конфигурации для long-running Telegram path.
- **UATScenario**: Проверяемый end-to-end contract, который доказывает отсутствие leakage и наличие корректной completion delivery.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Для long-running Telegram запросов пользователь получает initial ack в безопасное короткое окно, а authoritative UAT подтверждает отсутствие `Activity log` и других служебных traces в user-facing reply.
- **SC-002**: Long-running completion доставляется пользователю отдельным explicit completion-сообщением или отдельным explicit failure-сообщением; silent drop не допускается.
- **SC-003**: Status/resume/cancel поведение остаётся корректным после reset, compaction или смены session id, потому что durable state хранится вне chat history.
- **SC-004**: Version-watch template отправляет ровно одно уведомление на новый version fingerprint и не шлёт дубликаты на повторных проверках того же состояния.
- **SC-005**: Watchdog/UAT обнаруживают stalled worker, tool-heavy silence, delivery drift и route contamination до того, как пользователь интерпретирует проблему как “бот исчез”.
- **SC-006**: Герметичная contract suite и authoritative remote smoke/UAT покрывают разные классы доказательств и не подменяют друг друга.
- **SC-007**: Получившийся blueprint можно клонировать для других Telegram-агентов без возврата к chat-history-only state, heartbeat-only notify или одному длинному sync-turn.
