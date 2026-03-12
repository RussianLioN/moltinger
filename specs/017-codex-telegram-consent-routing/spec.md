# Feature Specification: Codex Telegram Consent Routing

**Feature Branch**: `017-codex-telegram-consent-routing`  
**Created**: 2026-03-12  
**Status**: Draft  
**Input**: Follow-up feature after `012-codex-upstream-watcher` to fix the architectural split between watcher-driven Telegram alerts and the main Moltis Telegram ingress. The new feature must make the main bot runtime the authoritative owner of consent replies, provide explicit action affordances instead of ambiguous free-text `да/нет`, and deliver practical recommendations without a second Telegram consumer racing for updates.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Main Telegram Ingress Owns Consent Replies (Priority: P1)

A Telegram user receives a Codex update alert and can answer it through an explicit, correlated action that is handled by the main Moltis Telegram runtime instead of by a side-channel watcher process.

**Why this priority**: The current bug exists because the watcher asks the question, but the main bot owns incoming messages. This story fixes the architectural ownership problem first.

**Independent Test**: Send a fresh watcher alert with an active consent request, then answer through the primary Telegram ingress path and confirm the consent decision is recorded without the generic bot dialog misinterpreting the reply.

**Acceptance Scenarios**:

1. **Given** a watcher alert opened a pending consent request, **When** the user presses an inline action or sends the structured fallback command, **Then** the main Telegram ingress records the decision against the matching consent request.
2. **Given** the user action matches a live consent request, **When** the main Telegram ingress handles it, **Then** the generic bot conversation path does not answer as if the message were an unrelated free-form chat prompt.
3. **Given** the consent request is expired, unknown, or belongs to another chat, **When** the user action arrives, **Then** the bot returns an explicit contextual error instead of pretending the request was accepted.

---

### User Story 2 - The User Gets Recommendations Immediately After Consent (Priority: P1)

A Telegram user who accepts the Codex follow-up question receives the practical project recommendations through the same main bot runtime without waiting for the next watcher scheduler pass.

**Why this priority**: The point of the consent flow is not only to record `yes/no`, but to turn consent into a real second message. Waiting for a later cron loop keeps the UX brittle and delayed.

**Independent Test**: Open a pending consent request, accept it through the main Telegram ingress, and confirm a second Telegram message with practical recommendations is sent promptly in the same chat.

**Acceptance Scenarios**:

1. **Given** a valid consent request with prepared practical recommendations, **When** the user accepts it, **Then** the bot sends a second Telegram message with those recommendations in the same chat.
2. **Given** the user declines the consent request, **When** the main Telegram ingress records the decision, **Then** the pending state closes and no recommendation message is sent.
3. **Given** the same consent action is repeated after successful delivery, **When** the bot receives the duplicate action, **Then** the system does not send the same recommendations twice.

---

### User Story 3 - Operators Can Validate The Full Live Flow And Fail Safe (Priority: P2)

An operator can validate the full live path `alert -> consent -> recommendations` and the feature degrades safely to a one-way alert when the authoritative consent router is unavailable.

**Why this priority**: The current bug slipped through because fixture tests were green while the live chat path was broken. This story makes the real UX observable and safe.

**Independent Test**: Run a live or hermetic E2E that opens a Codex alert, exercises consent through the main Telegram ingress, verifies the recommendation follow-up, and separately confirms that an unavailable consent router downgrades the alert to one-way delivery.

**Acceptance Scenarios**:

1. **Given** the authoritative consent router is healthy, **When** the operator runs a live acceptance test, **Then** the test proves the end-to-end Telegram flow delivers both the alert and the recommendation follow-up.
2. **Given** the authoritative consent router is unavailable or disabled, **When** the watcher sends an alert, **Then** the alert does not promise `да/нет` follow-up that the system cannot actually honor.
3. **Given** the operator inspects one completed consent interaction, **When** they review the machine-readable artifacts, **Then** they can see request id, chat id, decision, delivery result, and expiry state.

### Edge Cases

- What happens when inline callback actions are unavailable and the user client can only send plain text?
- What happens when the user replies after the consent window already expired?
- What happens when the user taps the same action twice or from two devices?
- What happens when the watcher can prepare an alert but cannot prepare project recommendations yet?
- What happens when the main bot ingress is healthy but the recommendation sender path fails after consent?
- What happens when the main bot receives an unrelated `да` message that is not tied to any Codex consent request?
- What happens when the user is allowlisted for the bot generally but not for the specific consent request chat/context?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The main Moltis Telegram ingress MUST be the authoritative owner of Codex consent replies in production.
- **FR-002**: The upstream watcher MUST stop acting as a second live consumer of Telegram updates in the normal production path.
- **FR-003**: Each consent-capable Codex alert MUST carry an explicit correlation identifier that the main Telegram ingress can validate.
- **FR-004**: The primary user action for consent SHOULD be explicit inline Telegram actions instead of ambiguous free-text `да/нет`.
- **FR-005**: The system MUST provide a structured fallback path for clients or situations where inline actions are unavailable.
- **FR-006**: A matched consent action MUST update a shared authoritative consent record instead of only mutating watcher-local state.
- **FR-007**: The system MUST suppress or replace the generic chat-bot interpretation for matched consent actions.
- **FR-008**: Accepting a valid consent request MUST send practical recommendations without waiting for the next watcher scheduler run.
- **FR-009**: Declining a valid consent request MUST close the pending state and MUST NOT send recommendations.
- **FR-010**: Duplicate acceptance or decline actions MUST be idempotent and MUST NOT create duplicate recommendation messages.
- **FR-011**: If the authoritative consent router is unavailable, the watcher MUST degrade to a one-way alert and MUST NOT promise a broken follow-up interaction.
- **FR-012**: The machine-readable interaction record MUST include request id, fingerprint, chat id, decision, timestamps, delivery outcome, and expiry status.
- **FR-013**: Human-facing Telegram text for this feature MUST remain in Russian.
- **FR-014**: MTProto or `real_user` Telegram sessions MAY be used for E2E validation, but MUST NOT become the primary production consent-routing mechanism.
- **FR-015**: The feature MUST provide live acceptance coverage for the real scenario `alert -> consent action -> recommendations`.
- **FR-016**: The feature MUST preserve GitOps deployment discipline through repository-managed config, scripts, workflows, or hooks only.

### Key Entities

- **ConsentRequest**: One pending Codex follow-up request attached to an alert, chat, fingerprint, expiry window, and recommendation payload.
- **ConsentActionToken**: The correlation identifier embedded into inline actions or fallback commands.
- **ConsentDecision**: The normalized user decision (`accept`, `decline`, `expired`, `invalid`, `duplicate`).
- **ConsentStoreRecord**: The authoritative machine-readable state shared between the main ingress and downstream follow-up logic.
- **RecommendationPayload**: The prepared project-facing guidance that is eligible to be sent after acceptance.
- **ConsentRouterResult**: The authoritative ingress result describing how one Telegram action was matched, validated, and resolved.
- **ConsentDeliveryResult**: The outcome of sending the second recommendation message after a valid acceptance.

### Assumptions & Dependencies

- `012-codex-upstream-watcher` remains the producer of Codex upstream alerts and prepared recommendation payloads.
- The main Moltis Telegram ingress continues to be configured through `config/moltis.toml`.
- Existing Moltis extension points such as hooks, commands, or ingress routing are available to integrate authoritative consent handling; if the current hook surface cannot short-circuit generic chat handling, this feature may extend the runtime to add that capability.
- Existing Telegram sender paths remain available for outbound delivery.
- Existing `telegram-e2e-on-demand` and `real_user` harnesses can be extended for live acceptance testing.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a live acceptance test, a user action on a Codex alert produces the correct consent result without the generic bot responding out of context.
- **SC-002**: After acceptance, the recommendation follow-up is delivered in the same chat within 10 seconds in the healthy path.
- **SC-003**: Duplicate consent actions do not produce duplicate recommendation messages.
- **SC-004**: When the authoritative consent router is unavailable, the alert is downgraded to one-way delivery and does not advertise a broken follow-up.
- **SC-005**: The system records enough machine-readable data to audit one consent interaction end-to-end.
- **SC-006**: MTProto remains limited to test and verification flows rather than becoming the production ingress path.
