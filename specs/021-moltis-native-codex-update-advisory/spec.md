# Feature Specification: Moltis-Native Codex Update Advisory Flow

**Feature Branch**: `021-moltis-native-codex-update-advisory`  
**Created**: 2026-03-12  
**Status**: Draft  
**Input**: Follow-up feature after `012-codex-upstream-watcher` and `017-codex-telegram-consent-routing`, based on the consilium decision that repo-side scripts should remain producers of normalized Codex update signals while Moltis becomes the single owner of the user-facing Telegram advisory flow.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Moltis Sends The Codex Update Alert As The Telegram Owner (Priority: P1)

A Telegram user receives a Codex update advisory from Moltis itself, not from a repo-side pseudo-dialog, and the alert already carries the right Russian summary plus real inline actions when interactive follow-up is available.

**Why this priority**: The current bug exists because the repo tries to drive a Telegram dialogue even though Moltis already owns Telegram ingress. This story fixes the ownership model first.

**Independent Test**: Feed one normalized Codex advisory event into Moltis and confirm that Moltis sends the alert in Telegram without relying on reply-keyboard text commands such as `/codex_da`.

**Acceptance Scenarios**:

1. **Given** a fresh normalized Codex advisory event, **When** Moltis processes it, **Then** it sends one Russian Telegram alert through its own runtime and records the alert state.
2. **Given** interactive advisory mode is healthy, **When** Moltis sends the alert, **Then** the alert uses real inline actions instead of text commands that fall back into generic chat.
3. **Given** interactive advisory mode is unavailable, **When** Moltis sends the alert, **Then** the alert degrades to one-way delivery and does not promise a broken follow-up.

---

### User Story 2 - Acceptance Produces Immediate Practical Recommendations (Priority: P1)

A Telegram user accepts the advisory follow-up and immediately receives practical project recommendations in the same chat, handled by Moltis without racing the generic LLM chat path.

**Why this priority**: The value of the feature is not just noticing a new Codex release, but turning that alert into usable project guidance without confusing chat replies.

**Independent Test**: Trigger a fresh advisory alert, press the inline accept action, and confirm Moltis sends the recommendation follow-up immediately in the same chat.

**Acceptance Scenarios**:

1. **Given** a live advisory alert with prepared recommendation payload, **When** the user presses the accept action, **Then** Moltis sends a second Russian Telegram message with the practical recommendations.
2. **Given** the user presses the decline action, **When** Moltis handles it, **Then** the pending advisory closes and no follow-up recommendation message is sent.
3. **Given** the same accept action is repeated, **When** Moltis receives the duplicate callback, **Then** the system remains idempotent and does not send duplicate recommendations.

---

### User Story 3 - Operators Can Audit, Degrade, And Recover Safely (Priority: P2)

An operator can prove the full live flow `signal -> alert -> callback -> follow-up`, and the system safely degrades to a one-way alert when callback routing or recommendation delivery is unavailable.

**Why this priority**: The previous repo-side flow looked good in fixtures but failed in live Telegram UX. This story makes the production path observable and honest.

**Independent Test**: Run one live or hermetic E2E where Moltis sends an alert, receives a callback, sends a follow-up, and separately confirm that a callback-path failure produces only a one-way alert.

**Acceptance Scenarios**:

1. **Given** Moltis callback routing is healthy, **When** an operator runs the live acceptance flow, **Then** the audit trail shows alert delivery, callback receipt, and follow-up delivery in order.
2. **Given** callback routing is unavailable, **When** Moltis receives a fresh advisory event, **Then** it sends a one-way alert and records the degraded reason.
3. **Given** the operator inspects one completed advisory interaction, **When** they review the machine-readable record, **Then** they can see advisory id, fingerprint, chat id, action result, and follow-up delivery state.

### Edge Cases

- What happens when Moltis receives a second advisory event for the same fingerprint before the first one is resolved?
- What happens when the user taps an old inline button after the advisory already expired?
- What happens when recommendations are not ready yet but the alert must still be delivered?
- What happens when callback routing succeeds but the follow-up message send fails?
- What happens when the same chat has several active advisories at once?
- What happens when Moltis receives a free-form `да` that is unrelated to any Codex advisory?
- What happens when the repo-side producer emits a malformed or partial advisory event?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Moltis MUST become the single production owner of Telegram ingress and advisory dialogue state for Codex update follow-ups.
- **FR-002**: Repo-side watcher and advisor layers MUST remain producers of normalized Codex update evidence and recommendation payloads, not live Telegram dialogue owners.
- **FR-003**: The production Telegram UX MUST NOT depend on reply-keyboard text commands such as `/codex_da` or `/codex_net`.
- **FR-004**: The primary interactive Telegram UX SHOULD use inline callback actions handled directly by Moltis.
- **FR-005**: Moltis MUST support a structured fallback path such as deep-link or tokenized command recovery when inline callbacks are unavailable.
- **FR-006**: Moltis MUST accept one stable normalized advisory event/report contract from the repo-side producer.
- **FR-007**: Moltis MUST validate advisory id, chat binding, expiry, and idempotency before sending follow-up recommendations.
- **FR-008**: Accepting a valid advisory MUST send practical recommendations immediately without waiting for another watcher or scheduler cycle.
- **FR-009**: Declining a valid advisory MUST close the advisory state and MUST NOT send recommendations.
- **FR-010**: Duplicate accepts or declines MUST be idempotent and MUST NOT create duplicate recommendation messages.
- **FR-011**: If the callback path is unavailable, Moltis MUST degrade to one-way alerting and MUST NOT advertise a broken interaction path.
- **FR-012**: Human-facing Telegram content for this feature MUST remain in Russian.
- **FR-013**: The machine-readable advisory interaction record MUST include advisory id, upstream fingerprint, chat id, alert message id, callback result, follow-up status, and timestamps.
- **FR-014**: Repo-side Codex bridge assets for the old delivery UX MUST stay retired while the Moltis-native feature is the planned replacement.
- **FR-015**: The feature MUST provide live acceptance coverage for the real path `alert -> callback -> follow-up`.
- **FR-016**: The deployment model MUST preserve GitOps discipline through repository-managed configuration, docs, workflows, or scripts only.

### Key Entities

- **CodexAdvisoryEvent**: Normalized event emitted by repo-side tooling that describes one fresh Codex update state plus recommendation context.
- **MoltisAdvisoryAlert**: Telegram-facing alert state created by Moltis from one advisory event.
- **AdvisoryConsentSession**: Pending interactive state tied to a chat, alert message id, advisory id, and expiry window.
- **RecommendationEnvelope**: Project-facing recommendation payload that Moltis can send after acceptance.
- **AdvisoryInteractionRecord**: Audit record describing the alert, callback resolution, and follow-up delivery outcome.
- **AdvisoryFallbackLink**: Optional deep-link or structured fallback action used only when inline callbacks are unavailable.

### Assumptions & Dependencies

- `012-codex-upstream-watcher` remains the producer of official-source Codex update signals.
- Project-specific recommendations can continue to be prepared by the existing advisor logic, but their user-facing Telegram delivery moves into Moltis.
- Moltis already owns Telegram ingress through its configured webhook or polling runtime.
- Implementing the final interactive path may require Moltis runtime changes beyond simple repo-side shell hooks.
- Until the Moltis-native path lands, production remains in `one-way alert` mode.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A live Telegram alert for a fresh Codex advisory is sent by Moltis without asking the user to type text commands such as `/codex_da`.
- **SC-002**: After the user accepts the alert, practical recommendations arrive in the same chat within 10 seconds on the healthy path.
- **SC-003**: Duplicate callback actions do not create duplicate recommendation messages.
- **SC-004**: When callback routing is unavailable, Moltis degrades to one-way alerting and records the degraded reason.
- **SC-005**: Operators can inspect one complete interaction record covering alert creation, callback handling, and follow-up delivery.
- **SC-006**: The old repo-side Codex skill/command entrypoint stays disabled until the Moltis-native flow replaces it.
