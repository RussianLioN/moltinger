# Feature Specification: Codex Update Delivery UX

**Feature Branch**: `009-codex-update-delivery-ux`
**Created**: 2026-03-09
**Status**: Draft
**Input**: Follow-up feature after `008-codex-update-advisor` to make Codex update awareness usable through natural-language entrypoints, launch-time alerts, and Telegram delivery.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - User Asks In Plain Language And Gets The Report (Priority: P1)

A user writes a normal text request in Codex, such as asking to check Codex CLI updates for this repository, and receives a short plain-language report without manually composing script flags.

**Why this priority**: This is the requested primary UX. If users still need to remember script commands, the advisor remains an internal tool rather than a usable repo capability.

**Independent Test**: Trigger the delivery entrypoint from a natural-language Codex-facing command or skill wrapper and confirm it runs the advisor flow, returning a short report with recommendation, notification state, and repository follow-up suggestions.

**Acceptance Scenarios**:

1. **Given** the user asks to check Codex CLI updates for this repository, **When** the delivery entrypoint runs, **Then** the user receives a short report in plain language with recommendation, what changed, and what the repo should likely update.
2. **Given** the current advisor result was already seen earlier, **When** the user asks again, **Then** the response explains that the state is already known instead of pretending it is new.
3. **Given** the underlying advisor needs investigation, **When** the user asks for the report, **Then** the response clearly says investigation is needed and does not overstate certainty.

---

### User Story 2 - User Sees An Alert When Launching Codex (Priority: P1)

A user launching Codex through the repository launcher sees a short startup alert when a fresh actionable Codex CLI update exists, without blocking the launch if the check fails.

**Why this priority**: Launch-time visibility is the most practical place to notify an active CLI user. It matches the user's request for Codex-side awareness without requiring background session patching.

**Independent Test**: Launch Codex through the repo launcher with a fixture-backed fresh actionable advisor result and confirm the launcher prints a short alert before entering Codex. Confirm launch still succeeds when the delivery check fails.

**Acceptance Scenarios**:

1. **Given** a fresh actionable update exists, **When** the user launches Codex through the repo launcher, **Then** the launcher prints a short pre-session alert summarizing the change and next action.
2. **Given** the same actionable state was already delivered earlier, **When** the user launches Codex again, **Then** the launcher avoids repeating the same alert.
3. **Given** the delivery check fails or the advisor returns investigate, **When** the user launches Codex, **Then** the launch continues and the alert degrades gracefully instead of blocking Codex startup.
4. **Given** launch-time Telegram delivery is enabled with a configured chat target, **When** the user launches Codex through the repo launcher, **Then** the launcher also triggers background Telegram delivery without delaying Codex startup.

---

### User Story 3 - User Gets Telegram Notification Through Moltinger (Priority: P2)

A user receives a Telegram message through the existing bot path when a fresh actionable Codex update is found, so important changes are visible even outside the terminal.

**Why this priority**: This is the requested ideal UX for asynchronous notification. It turns the advisor into a real delivery surface instead of a terminal-only feature.

**Independent Test**: Run the Telegram delivery flow with a fixture-backed fresh actionable advisor result and a mocked bot sender, then confirm a single concise Telegram message is generated. Repeat with the same state and confirm the duplicate is suppressed.

**Acceptance Scenarios**:

1. **Given** a fresh actionable advisor result and Telegram delivery is enabled, **When** the delivery flow runs, **Then** it sends one concise Telegram message through the existing bot send path.
2. **Given** the same actionable state was already delivered to Telegram, **When** the delivery flow runs again, **Then** it suppresses the duplicate message.
3. **Given** Telegram delivery is enabled but sending fails, **When** the flow completes, **Then** the failure is recorded explicitly without corrupting the overall delivery state.

---

### User Story 4 - Delivery State Stays Coherent Across Surfaces (Priority: P3)

A maintainer can rely on one delivery state model so on-demand reports, startup alerts, and Telegram notifications do not drift or duplicate each other unpredictably.

**Why this priority**: Once multiple surfaces exist, shared state becomes the difference between useful notifications and spam.

**Independent Test**: Exercise on-demand report, launcher alert, and Telegram delivery against the same underlying advisor result and confirm the shared state records which surface already delivered which fingerprint.

**Acceptance Scenarios**:

1. **Given** the same actionable advisor fingerprint reaches multiple delivery surfaces, **When** the shared state is consulted, **Then** each surface can decide whether it should notify, suppress, or retry.
2. **Given** one surface fails while another succeeds, **When** the delivery state is updated, **Then** successful delivery is preserved and the failed surface remains retryable.

### Edge Cases

- What happens when the user asks for a plain-language report but the advisor report does not yet exist?
- What happens when launch-time delivery is enabled but the launcher is not the path used to start Codex?
- What happens when launch-time Telegram is enabled locally but the bot token only exists on the Moltinger host?
- What happens when Telegram delivery is enabled but the chat target is missing?
- What happens when on-demand delivery succeeded but Telegram failed for the same fingerprint?
- What happens when the user wants a fresh report even though the notification is suppressed?
- What happens when a newer Codex version arrives before the previous follow-up work was completed?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST reuse the completed `008-codex-update-advisor` report as the single source of truth for delivery decisions.
- **FR-002**: System MUST provide a Codex-facing natural-language entrypoint so a user can request the current Codex update report without manually composing script arguments.
- **FR-003**: System MUST provide a launch-time delivery path through the repository Codex launcher.
- **FR-004**: Launch-time delivery MUST fail open and MUST NOT block Codex startup.
- **FR-005**: System MUST support Telegram delivery through the existing repository Telegram bot sending path rather than introducing a new bot stack.
- **FR-006**: System MUST support shared delivery state across at least on-demand report, launcher alert, and Telegram surfaces.
- **FR-007**: System MUST suppress duplicate delivery per surface for the same actionable fingerprint.
- **FR-008**: System MUST still let the user request a plain-language report even when the notification state is already known.
- **FR-009**: System MUST produce deterministic machine-readable delivery output for each run.
- **FR-010**: Telegram delivery MUST be configurable and opt-in.
- **FR-011**: Telegram failures MUST be recorded explicitly without hiding on-demand or launcher results.
- **FR-012**: Delivery summaries MUST explain recommendation, freshness, and repository follow-up suggestions in plain language.
- **FR-013**: The feature MUST avoid inventing a second recommendation engine; it only decides how and where to deliver the advisor result.
- **FR-014**: Delivery state corruption or absence MUST degrade safely to a fresh evaluation rather than a silent failure.
- **FR-015**: The design MUST remain compatible with future schedulers or background automation.
- **FR-016**: The repository launcher MUST be able to trigger Telegram delivery in the background when launch-time Telegram automation is enabled.

### Key Entities

- **AdvisorSnapshot**: The current normalized advisor result used for delivery.
- **DeliveryFingerprint**: The stable identifier for the actionable update state being delivered.
- **DeliverySurfaceState**: Per-surface memory for on-demand, launcher, and Telegram delivery results.
- **DeliveryDecision**: The per-surface outcome describing whether that surface should notify, suppress, retry, or investigate.
- **TelegramDeliveryTarget**: The configured Telegram chat destination and delivery settings.
- **DeliveryRunReport**: The top-level machine-readable result for the delivery layer.

### Assumptions & Dependencies

- `scripts/codex-cli-update-advisor.sh` remains the advisor source of truth for recommendation and suggestions.
- `scripts/codex-profile-launch.sh` is the supported launcher path for repository-managed Codex sessions.
- `scripts/telegram-bot-send.sh` remains the delivery primitive for Telegram in v1.
- Launch-time Telegram automation may delegate the actual send to the Moltinger server runtime when the local machine does not hold the bot token.
- In-session push inside an already running Codex TUI is out of scope for v1; launch-time and asynchronous delivery are the practical supported surfaces.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can request the current Codex update status in plain language and receive a plain-language answer in under 2 minutes.
- **SC-002**: When a fresh actionable update exists, the repository launcher shows a short alert before starting Codex without blocking launch.
- **SC-003**: When Telegram delivery is enabled, a fresh actionable update produces one Telegram message and duplicate runs do not resend it.
- **SC-004**: Shared delivery state prevents repeated noise across supported delivery surfaces for the same actionable fingerprint.
- **SC-005**: Delivery failures remain explicit and do not cause silent loss of update visibility.
