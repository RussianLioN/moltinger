# Feature Specification: Moltis Live Codex Update Telegram Runtime Gap

**Feature Branch**: `035-moltis-live-codex-update-telegram-runtime-gap`  
**Created**: 2026-03-28  
**Status**: Draft  
**Input**: User description: "расследовать residual live defect из n15; перепроверить codex-update false-negative; перепроверить Activity log leakage; разделить repo-owned и upstream-owned; учесть deferred redesign из 0ph: codex-update должен стать advisory/notification-only для remote Moltis"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remote Codex Update Contract Is Advisory-Safe (Priority: P1)

Пользователь спрашивает в Telegram про новые версии Codex CLI, а Moltis отвечает честно и полезно, не делая ложных выводов по sandbox-visible filesystem и не обещая удалённо выполнить локальный Codex update workflow.

**Why this priority**: Это прямой user-facing дефект. Пока remote surface обещает не тот контракт или говорит "skill не существует" по host-path probes, live capability выглядит сломанной даже при корректном runtime discovery.

**Independent Test**: Отправить authoritative remote UAT запрос вроде `Что с новыми версиями codex?` и убедиться, что ответ не содержит false-negative по skill path, не раскрывает host paths и не обещает server-side execution локального Codex update path.

**Acceptance Scenarios**:

1. **Given** live runtime already advertises `codex-update` in available skills, **When** remote Telegram user asks about Codex updates, **Then** the reply MUST NOT treat sandbox-invisible host paths as proof that the skill is missing.
2. **Given** the request comes from a sandboxed remote user-facing surface, **When** `codex-update` is activated, **Then** the reply MUST stay advisory/notification-only and MUST NOT imply that the server can update the user's local Codex installation.
3. **Given** the same capability is used from a trusted operator/local surface that can truly access canonical runtime paths, **When** the operator asks for the canonical runtime, **Then** docs and guidance may still reference the operator-only execution path explicitly.

---

### User Story 2 - Remote UAT Fails Closed On Contract Drift And Leakage (Priority: P1)

Оператор запускает authoritative Telegram remote UAT и получает точный verdict, который различает `codex-update` contract drift, host-path leakage и `Activity log` leakage, а не пропускает их как зелёный результат.

**Why this priority**: Пока regression gates не fail-closed, repo может снова принять user-facing drift за норму и поздно заметить повторную live поломку.

**Independent Test**: Подставить green helper payloads с искусственно плохими reply shapes и убедиться, что wrapper завершает run как `failed` с семантически точным failure code.

**Acceptance Scenarios**:

1. **Given** helper payload выглядит зелёным, **When** reply содержит `Activity log` или внутренний tool-progress, **Then** authoritative wrapper MUST return failed semantic verdict.
2. **Given** helper payload выглядит зелёным, **When** reply раскрывает `/home/moltis/.moltis/skills`, `/server/scripts/...` или аналогичные internal paths, **Then** authoritative wrapper MUST return failed semantic verdict.
3. **Given** helper payload выглядит зелёным, **When** remote `codex-update` answer promises direct server-side execution or local-machine update behavior, **Then** authoritative wrapper MUST return failed semantic verdict for remote contract violation.

---

### User Story 3 - Residual Live Gap Is Split Into Repo-Owned And Upstream-Owned Closure Paths (Priority: P2)

Оператор или следующий исполнитель видит, какие части проблемы закрываются в этом репозитории, а какие остаются upstream/runtime gap и требуют отдельного handoff, вместо размытых формулировок "всё ещё что-то течёт в Telegram".

**Why this priority**: Без чёткого split между repo-owned и upstream-owned кусками команда либо переоценивает локальный фикс, либо бесконечно "долечивает" чужой runtime bug в неправильном месте.

**Independent Test**: Прочитать spec/docs/handoff и убедиться, что для `codex-update` false-negative, remote execution drift и `Activity log` leakage отдельно описаны repo-owned mitigation, authoritative re-check path и upstream closure criteria.

**Acceptance Scenarios**:

1. **Given** residual live defect still reproduces после repo-owned carrier, **When** оператор читает handoff artifacts, **Then** он видит чёткое разделение repo-owned mitigation и upstream-owned closure path.
2. **Given** live re-check показывает чистый final reply, но Telegram transport всё ещё светит `Activity log`, **When** результат классифицируется, **Then** это описывается как transport/runtime leakage, а не как prompt-only defect.
3. **Given** deferred redesign из `034/0ph` ещё не полностью закрыт, **When** feature package фиксирует scope, **Then** package явно описывает `codex-update` на remote surfaces как advisory/notification capability, а не remote executor.

### Edge Cases

- Что происходит, если remote runtime advertises `codex-update`, но sandboxed `exec` всё ещё не видит host/runtime paths?
- Что происходит, если final assistant reply в истории чистый, а отдельный `Activity log` попадает пользователю транспортом?
- Что происходит, если trusted operator/local surface реально видит `/server`, но user-facing Telegram surface не должна повторять этот execution contract?
- Что происходит, если authoritative remote UAT зелёный локально по helper payload, но live production still exhibits upstream transport leakage?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST treat `codex-update` as advisory/notification-only on remote user-facing Moltis surfaces unless a trusted operator/local context explicitly proves direct runtime execution is available on that surface.
- **FR-002**: System MUST NOT disprove live `codex-update` availability through sandbox filesystem probes against `/home/moltis/.moltis/skills`, `/server`, or similar host/runtime paths.
- **FR-003**: Remote user-facing replies MUST NOT expose internal host paths, repo runtime scripts, or raw execution details for `codex-update`.
- **FR-004**: Remote user-facing replies MUST NOT imply that the Moltis server/container can update the user's local Codex installation.
- **FR-005**: Authoritative Telegram remote UAT MUST fail closed on `Activity log` leakage.
- **FR-006**: Authoritative Telegram remote UAT MUST fail closed on `codex-update` false negatives caused by sandbox-invisible host paths.
- **FR-007**: Authoritative Telegram remote UAT MUST fail closed on remote execution-contract violations for `codex-update`.
- **FR-008**: Documentation and handoff artifacts MUST separate repo-owned fixes from upstream-owned runtime/transport closure conditions.
- **FR-009**: Operator/local surfaces MAY keep the canonical runtime path for `codex-update`, but that path MUST be documented as surface-specific rather than universal.

### Key Entities *(include if feature involves data)*

- **RemoteCodexUpdateSurface**: User-facing Moltis surface such as Telegram or other sandboxed chat session that can answer about Codex updates but must stay advisory-only.
- **OperatorCodexUpdateSurface**: Trusted operator/local context that can legitimately inspect or run canonical runtime entrypoints when `/server` and writable state are truly available.
- **TelegramSemanticVerdict**: Authoritative UAT classification for reply shapes such as `activity leak`, `host path leak`, `false negative`, or `remote contract violation`.
- **ResidualRuntimeGap**: Remaining defect after repo-owned mitigation, tracked as either repo-owned carrier drift or upstream-owned runtime/transport behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Remote Telegram `codex-update` replies no longer claim that the skill is missing solely because sandbox-visible host paths are absent.
- **SC-002**: Remote Telegram `codex-update` replies no longer imply server-side execution of local Codex update actions on behalf of the user.
- **SC-003**: Authoritative Telegram remote UAT returns deterministic failed semantic verdicts for `Activity log` leakage, host-path leakage, and remote `codex-update` contract violations.
- **SC-004**: Feature artifacts for `035` let the next operator identify which parts are closed in-repo and which still require upstream/runtime remediation.
