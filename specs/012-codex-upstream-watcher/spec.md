# Feature Specification: Codex Upstream Watcher

**Feature Branch**: `012-codex-upstream-watcher`  
**Created**: 2026-03-09  
**Status**: Draft  
**Input**: Follow-up feature after `009-codex-update-delivery-ux` to watch official Codex CLI sources on a schedule, assign severity, optionally batch alerts into a digest, and send Telegram alerts through Moltinger without depending on a locally installed Codex CLI. The watcher also exposes an opt-in bridge to project-facing practical recommendations.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operator Can Run An Official-Source Watch Check Manually (Priority: P1)

An operator can run one command on the Moltinger side and get a short Russian report about whether Codex CLI published a new upstream version, how important it is, what changed in plain language, and whether the result is new or already known.

**Why this priority**: A manual run is the smallest reliable slice. It proves the watcher can read official sources, compute stable freshness, and summarize upstream changes before any scheduler starts sending Telegram automatically.

**Independent Test**: Run the watcher against fixture-backed official source inputs and confirm it emits a deterministic report with upstream version, key changes, source status, fingerprint, and freshness decision.

**Acceptance Scenarios**:

1. **Given** the watcher reads the official Codex changelog and optional advisory issue signals, **When** the operator runs the watcher manually, **Then** the output clearly says whether a new upstream Codex state exists, assigns a severity level, and summarizes the changes in plain Russian.
2. **Given** the same upstream fingerprint was already recorded earlier, **When** the operator runs the watcher again, **Then** the report says the state is already known instead of treating it as fresh.
3. **Given** one upstream source is unavailable or malformed, **When** the watcher runs, **Then** the report explicitly marks investigation or partial evidence without pretending the upstream state is fully known.

---

### User Story 2 - Moltinger Sends Telegram When A Fresh Upstream State Appears (Priority: P1)

A user receives one Telegram alert through the existing Moltinger bot when the official Codex CLI sources publish a fresh actionable upstream state, even if the user did not launch Codex locally.

**Why this priority**: This is the missing async UX. It closes the gap between “I can ask Codex manually” and “I automatically hear about new upstream Codex releases or important changes”.

**Independent Test**: Run the watcher in scheduler mode with a fresh actionable fixture and a mocked Telegram sender, then confirm a single Telegram message is sent. Repeat with the same fingerprint and confirm no duplicate is sent.

**Acceptance Scenarios**:

1. **Given** a fresh upstream fingerprint is found and Telegram delivery is enabled, **When** the scheduler mode runs, **Then** one concise Telegram message is sent through the existing Moltinger bot sender with a severity level and a plain-language explanation of what changed.
2. **Given** the same upstream fingerprint was already delivered to Telegram, **When** the scheduler runs again, **Then** the message is suppressed.
3. **Given** Telegram sending fails for a fresh upstream fingerprint, **When** the run completes, **Then** the failure is recorded explicitly and the fingerprint remains retryable.

---

### User Story 3 - Users Can Ask For Practical Project Recommendations After The Alert (Priority: P2)

A user who receives a Telegram alert can explicitly answer whether they want practical recommendations for applying the new Codex capabilities in this project, and if they agree, the watcher sends those recommendations through an advisor bridge instead of guessing silently.

**Why this priority**: Upstream awareness is useful on its own, but the real UX jump is converting “there is a new release” into “here is what to review in this project” without spamming unsolicited implementation advice.

**Independent Test**: Send a scheduler alert through a mocked Telegram sender, store a pending consent state, replay a `yes` reply through fixture-backed Bot API updates, and confirm a second Telegram message contains project-facing practical recommendations.

**Acceptance Scenarios**:

1. **Given** the watcher sends a fresh Telegram alert and practical recommendations are available, **When** the alert is delivered, **Then** the message also asks whether the user wants project-facing practical recommendations.
2. **Given** the user replies `да`, **When** the next scheduler run processes Telegram replies, **Then** the watcher sends practical recommendations and closes the pending consent state.
3. **Given** the user replies `нет`, **When** the next scheduler run processes Telegram replies, **Then** the watcher does not send a second recommendation message and closes the pending consent state.

---

### User Story 4 - Scheduled Runs Can Batch Non-Critical Signals Into A Digest (Priority: P2)

A maintainer can switch the watcher into digest mode so non-critical upstream events are batched into fewer Telegram messages while critical events still stay visible immediately.

**Why this priority**: Without batching, a run of minor upstream updates can create noise. Digest mode keeps the watcher useful instead of becoming background spam.

**Independent Test**: Run the watcher in scheduler mode with digest delivery, accumulate two different non-critical upstream fingerprints, and confirm the second run sends one combined digest message instead of two separate alerts.

**Acceptance Scenarios**:

1. **Given** digest mode is enabled and a first non-critical upstream fingerprint is found, **When** the scheduler runs, **Then** the event is queued instead of being sent immediately.
2. **Given** digest mode is enabled and the digest threshold is reached, **When** the scheduler runs, **Then** one combined Telegram digest is sent and the pending queue is cleared.
3. **Given** a critical upstream signal appears while digest mode is enabled, **When** the scheduler runs, **Then** the watcher may bypass the digest queue and send the alert immediately.

---

### User Story 5 - Scheduled Runs Stay Safe During Source Failures And Recovery (Priority: P2)

A maintainer can rely on the scheduled watcher to behave safely when official sources fail temporarily, recover later, or disagree with each other, without spamming Telegram or losing auditability.

**Why this priority**: Scheduled watchers fail in the real world. If the source state becomes flaky, the watcher must degrade safely instead of creating false certainty or repeated noise.

**Independent Test**: Exercise scheduler mode across source failure, recovery, and changed-source fixtures and confirm state, report, and Telegram behavior remain coherent and retry-safe.

**Acceptance Scenarios**:

1. **Given** the official changelog is unreachable, **When** the scheduler runs, **Then** the run records investigation or failure state without sending a misleading success alert.
2. **Given** the source recovers and exposes the same already-known fingerprint, **When** the scheduler runs, **Then** the watcher records recovery without resending the same alert.
3. **Given** the source recovers and exposes a newer fingerprint, **When** the scheduler runs, **Then** the watcher sends one fresh Telegram alert and updates persisted state cleanly.

### Edge Cases

- What happens when the official changelog changes markup but still contains the same release information?
- What happens when the changelog and advisory issue signals disagree about freshness or severity?
- What happens when the watcher has no previous state file?
- What happens when Telegram delivery is enabled on the server but `TELEGRAM_ALLOWED_USERS` or target chat settings are incomplete?
- What happens when the same upstream fingerprint should notify Telegram but the user later asks the local Codex delivery layer for repo-specific applicability?
- What happens when digest mode is enabled but a critical signal appears?
- What happens when the watcher can send Telegram alerts but cannot read Telegram replies for the consent follow-up?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST monitor official Codex upstream sources without requiring a locally installed Codex CLI on the watcher host.
- **FR-002**: System MUST treat the official Codex changelog as the primary source of release truth.
- **FR-003**: System MAY ingest advisory upstream issue signals, but advisory signals MUST NOT override the primary release source on their own.
- **FR-004**: System MUST emit a deterministic machine-readable watcher report for every run.
- **FR-005**: System MUST compute and persist a stable upstream fingerprint so repeated runs can distinguish fresh, known, failed, and retryable states.
- **FR-006**: System MUST support a manual operator run that returns a short plain-language summary.
- **FR-007**: System MUST support scheduled execution on the Moltinger host using repository-managed automation.
- **FR-008**: Scheduled execution MUST send Telegram through the existing Moltinger bot sender instead of introducing a new Telegram transport stack.
- **FR-009**: Telegram alerts MUST be duplicate-safe per upstream fingerprint.
- **FR-010**: Telegram send failures MUST be recorded explicitly and MUST leave the affected fingerprint retryable.
- **FR-011**: Source failures or malformed upstream data MUST degrade to an explicit investigate or failed state rather than a false clean result.
- **FR-012**: The watcher MUST keep its scope to upstream awareness and MUST NOT claim local repo applicability on its own.
- **FR-013**: The watcher output MUST be reusable by future integrations that want to bridge upstream awareness into local advisor or delivery flows.
- **FR-014**: The scheduler path MUST remain fail-open with respect to the rest of Moltinger; watcher failure must not break unrelated services.
- **FR-015**: The feature MUST preserve GitOps deployment discipline by installing scheduled automation from repository-managed scripts or workflows only.
- **FR-016**: Human-facing watcher output and Telegram summaries MUST be provided in Russian.
- **FR-017**: The watcher MUST assign a severity level so operators can distinguish routine upstream changes from critical or investigate-only states.
- **FR-018**: The watcher MUST support a digest delivery mode for non-critical upstream events.
- **FR-019**: Critical upstream events MAY bypass digest batching when delaying them would reduce operator awareness.
- **FR-020**: The watcher MUST be able to ask the user in Telegram whether they want practical project recommendations after a fresh alert.
- **FR-021**: If the user explicitly agrees in Telegram and recommendations are available, the watcher MUST send a follow-up recommendation message through the existing Telegram transport.
- **FR-022**: Project-facing recommendations MUST be produced through an advisor bridge rather than hard-coding repo-specific assumptions inside the upstream watcher summary.
- **FR-023**: Direct Bot API reply polling MUST stay opt-in and MUST refuse to use `getUpdates` when an active Telegram webhook is detected.

### Key Entities

- **UpstreamSnapshot**: The normalized upstream Codex state derived from official release and advisory inputs.
- **UpstreamFingerprint**: The stable identifier for the current upstream Codex state.
- **WatcherState**: Persisted memory describing the last seen fingerprint and last delivery outcome.
- **WatcherDecision**: The run-time result describing whether the current upstream state is fresh, known, investigate, or retryable.
- **WatcherSeverity**: The normalized importance level assigned to one upstream state.
- **WatcherTelegramTarget**: The Telegram delivery configuration used by the scheduled watcher.
- **WatcherDigestState**: Persisted queue of non-critical upstream states waiting for a combined digest message.
- **WatcherConsentState**: Persisted pending question/answer state for Telegram follow-up recommendations.
- **WatcherAdvisorBridge**: The normalized project-facing recommendation payload built from the local advisor layer.
- **WatcherRunReport**: The top-level machine-readable output for one watcher run.

### Assumptions & Dependencies

- Official Codex release truth is available from the Codex changelog and remains reachable from the Moltinger host or equivalent runner.
- Existing Moltinger Telegram delivery paths remain available through `scripts/telegram-bot-send.sh`.
- Local repo applicability and “what should this repository change?” remain the responsibility of the existing local monitor/advisor/delivery stack.
- The watcher may prepare practical recommendations only through an explicit bridge to the existing monitor/advisor stack and only send them after user consent.
- The Moltinger deploy workflow continues to install scripts and cron jobs from repository-managed files.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A manual watcher run produces a readable upstream report in under 2 minutes without requiring a local Codex binary.
- **SC-002**: A fresh upstream fingerprint causes exactly one Telegram alert on the first scheduled run and zero duplicate alerts on repeated identical runs.
- **SC-003**: Source failures are visible in the watcher report and do not silently masquerade as `ignore` or already-known success.
- **SC-004**: Scheduled automation can be deployed through existing GitOps paths without manual server-only cron drift.
- **SC-005**: The watcher clearly distinguishes upstream awareness from local repo applicability so users are not misled about whether they personally need to change their local Codex setup.
- **SC-006**: Non-critical upstream events can be batched into a digest without losing visibility of critical events.
- **SC-007**: After a Telegram alert, a user can explicitly opt into practical project recommendations and receive them in a second Telegram message.
