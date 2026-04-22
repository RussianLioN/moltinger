# Feature Specification: Telegram Skill CRUD UAT Hardening

**Feature Branch**: `feat/moltinger-wdj0-telegram-skill-crud-uat`  
**Created**: 2026-04-22  
**Status**: Draft  
**Input**: User description: "Продолжай: после merge native Telegram skill CRUD надо довести authoritative remote UAT до полного proof для update/delete, а не только create."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Authoritative Create/Update/Delete Verdicts (Priority: P1)

Как оператор, я хочу запускать один authoritative Telegram remote UAT и получать review-safe verdict не только для создания навыка, но и для update/delete mutation flow, чтобы live proof соответствовал уже задеплоенному runtime contract.

**Why this priority**: Сейчас runtime умеет больше, чем authoritative UAT способен доказать автоматически. Это оставляет ручной разрыв между реализацией и live acceptance.

**Independent Test**: Component contract tests for `scripts/telegram-e2e-on-demand.sh` confirm deterministic semantic verdicts for create, update, and delete skill mutation turns without touching live production.

**Acceptance Scenarios**:

1. **Given** оператор запускает authoritative remote UAT с сообщением на update существующего skill, **When** Telegram reply приходит без leakage, **Then** review-safe artifact фиксирует update-specific semantic success и подтверждает, что target skill оставался видимым после mutation.
2. **Given** оператор запускает authoritative remote UAT с сообщением на delete существующего skill, **When** Telegram reply приходит без leakage, **Then** review-safe artifact фиксирует delete-specific semantic success и подтверждает, что target skill исчез из live `/api/skills`.
3. **Given** Telegram reply по mutation turn уходит в `Activity log`, host paths, internal planning или ложный filesystem вывод, **When** wrapper выполняет semantic review, **Then** verdict становится deterministic `failed` с named failure code.

---

### User Story 2 - Review-Safe Mutation Failure Taxonomy (Priority: P1)

Как оператор, я хочу, чтобы update/delete mutation failures различались по понятным semantic classes, а не растворялись в generic "probe failed".

**Why this priority**: Mutation UAT полезен только тогда, когда по артефакту видно, что именно сломалось: target skill отсутствовал до send, не сохранился после update, не исчез после delete, reply не упомянул target skill, или наружу протёк internal tail.

**Independent Test**: Component tests can force each mutation-specific negative path and verify the failure code and diagnostic context.

**Acceptance Scenarios**:

1. **Given** update requested for skill, которого не было до send, **When** wrapper делает semantic review, **Then** artifact получает named failure class про missing preexisting target.
2. **Given** delete requested for skill, который после reply всё ещё остаётся в live skills list, **When** semantic review finishes, **Then** artifact получает delete-specific failure class instead of generic mismatch.
3. **Given** reply не упоминает target skill name после update/delete, **When** semantic review finishes, **Then** artifact получает visibility/name mismatch failure class with diagnostic context.

---

### User Story 3 - Operator Documentation Matches Real Mutation Coverage (Priority: P2)

Как оператор, я хочу, чтобы `docs/telegram-e2e-on-demand.md` явно описывал, какие skill mutation flows authoritative UAT умеет доказывать, какие guardrails есть для shared production, и где остаются осознанные ограничения.

**Why this priority**: После расширения mutation coverage операторский contract не должен оставаться на уровне старого create-only поведения.

**Independent Test**: Review the updated doc and confirm it documents create/update/delete semantics, result interpretation, and safety limits without undocumented assumptions.

**Acceptance Scenarios**:

1. **Given** оператор читает `docs/telegram-e2e-on-demand.md`, **When** он ищет guidance по skill mutation UAT, **Then** видит явное описание create/update/delete coverage и review-safe artifact semantics.
2. **Given** shared production остаётся общим target, **When** оператор читает doc, **Then** он видит явные safety notes про осознанный mutation scope и отсутствие скрытого destructive поведения.

---

### Edge Cases

- Что делать, если update/delete запрос не даёт однозначно извлечь target skill name?
- Что делать, если target skill уже отсутствует до delete turn или уже отсутствует после create baseline?
- Что делать, если mutation reply выглядит "чисто", но live `/api/skills` не подтверждает реальный state transition?
- Что делать, если create/update/delete проходит, но reply не называет target skill явно?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `scripts/telegram-e2e-on-demand.sh` MUST различать create, update, and delete skill mutation turns during semantic review.
- **FR-002**: Authoritative review-safe artifact MUST содержать deterministic success/failure semantics для update/delete, аналогично уже существующему create flow.
- **FR-003**: For update turns, semantic review MUST prove that the target skill existed before send and remains visible after the mutation.
- **FR-004**: For delete turns, semantic review MUST prove that the target skill existed before send and is absent from live `/api/skills` after the mutation.
- **FR-005**: Mutation semantic failures MUST have named failure codes for at least target-not-found-before-send, post-update-visibility mismatch, post-delete-persistence mismatch, reply-name mismatch, activity/internal-planning leakage, and host-path leakage.
- **FR-006**: Component tests MUST cover positive and negative semantic review paths for update/delete without requiring live production credentials.
- **FR-007**: `docs/telegram-e2e-on-demand.md` MUST document authoritative mutation coverage and shared-production safety notes.
- **FR-008**: The implementation MUST remain review-safe and MUST NOT introduce hidden destructive automation outside the explicit operator-triggered mutation turn.

### Key Entities

- **SkillMutationIntent**: Normalized semantic category for create, update, or delete turn under authoritative Telegram UAT.
- **MutationSemanticReview**: The post-reply verification stage that compares pre-send and post-reply runtime skill state against the requested mutation intent.
- **MutationTargetSkill**: The normalized skill name extracted from the operator message and used for baseline and post-mutation verification.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Component remote-UAT contract tests pass for create, update, and delete mutation verdicts with deterministic named outcomes.
- **SC-002**: Update/delete negative cases produce mutation-specific failure codes instead of generic probe failure.
- **SC-003**: Operator doc clearly states that authoritative mutation coverage includes create/update/delete and explains the review-safe mutation semantics.
- **SC-004**: No new mutation path reintroduces `Activity log`, internal planning, raw tool names, or host-path leakage into review-safe artifacts.
