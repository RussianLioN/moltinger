# Feature Specification: Codex Upstream Watcher

**Feature Branch**: `012-codex-upstream-watcher`  
**Created**: 2026-03-09  
**Status**: Draft  
**Input**: Follow-up feature after `009-codex-update-delivery-ux` to watch official Codex CLI sources on a schedule and send Telegram alerts through Moltinger without depending on a locally installed Codex CLI.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operator Can Run An Official-Source Watch Check Manually (Priority: P1)

An operator can run one command on the Moltinger side and get a short report about whether Codex CLI published a new upstream version, what changed, and whether the result is new or already known.

**Why this priority**: A manual run is the smallest reliable slice. It proves the watcher can read official sources, compute stable freshness, and summarize upstream changes before any scheduler starts sending Telegram automatically.

**Independent Test**: Run the watcher against fixture-backed official source inputs and confirm it emits a deterministic report with upstream version, key changes, source status, fingerprint, and freshness decision.

**Acceptance Scenarios**:

1. **Given** the watcher reads the official Codex changelog and optional advisory issue signals, **When** the operator runs the watcher manually, **Then** the output clearly says whether a new upstream Codex state exists and summarizes the changes in plain language.
2. **Given** the same upstream fingerprint was already recorded earlier, **When** the operator runs the watcher again, **Then** the report says the state is already known instead of treating it as fresh.
3. **Given** one upstream source is unavailable or malformed, **When** the watcher runs, **Then** the report explicitly marks investigation or partial evidence without pretending the upstream state is fully known.

---

### User Story 2 - Moltinger Sends Telegram When A Fresh Upstream State Appears (Priority: P1)

A user receives one Telegram alert through the existing Moltinger bot when the official Codex CLI sources publish a fresh actionable upstream state, even if the user did not launch Codex locally.

**Why this priority**: This is the missing async UX. It closes the gap between “I can ask Codex manually” and “I automatically hear about new upstream Codex releases or important changes”.

**Independent Test**: Run the watcher in scheduler mode with a fresh actionable fixture and a mocked Telegram sender, then confirm a single Telegram message is sent. Repeat with the same fingerprint and confirm no duplicate is sent.

**Acceptance Scenarios**:

1. **Given** a fresh upstream fingerprint is found and Telegram delivery is enabled, **When** the scheduler mode runs, **Then** one concise Telegram message is sent through the existing Moltinger bot sender.
2. **Given** the same upstream fingerprint was already delivered to Telegram, **When** the scheduler runs again, **Then** the message is suppressed.
3. **Given** Telegram sending fails for a fresh upstream fingerprint, **When** the run completes, **Then** the failure is recorded explicitly and the fingerprint remains retryable.

---

### User Story 3 - Scheduled Runs Stay Safe During Source Failures And Recovery (Priority: P2)

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

### Key Entities

- **UpstreamSnapshot**: The normalized upstream Codex state derived from official release and advisory inputs.
- **UpstreamFingerprint**: The stable identifier for the current upstream Codex state.
- **WatcherState**: Persisted memory describing the last seen fingerprint and last delivery outcome.
- **WatcherDecision**: The run-time result describing whether the current upstream state is fresh, known, investigate, or retryable.
- **WatcherTelegramTarget**: The Telegram delivery configuration used by the scheduled watcher.
- **WatcherRunReport**: The top-level machine-readable output for one watcher run.

### Assumptions & Dependencies

- Official Codex release truth is available from the Codex changelog and remains reachable from the Moltinger host or equivalent runner.
- Existing Moltinger Telegram delivery paths remain available through `scripts/telegram-bot-send.sh`.
- Local repo applicability and “what should this repository change?” remain the responsibility of the existing local monitor/advisor/delivery stack.
- The Moltinger deploy workflow continues to install scripts and cron jobs from repository-managed files.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A manual watcher run produces a readable upstream report in under 2 minutes without requiring a local Codex binary.
- **SC-002**: A fresh upstream fingerprint causes exactly one Telegram alert on the first scheduled run and zero duplicate alerts on repeated identical runs.
- **SC-003**: Source failures are visible in the watcher report and do not silently masquerade as `ignore` or already-known success.
- **SC-004**: Scheduled automation can be deployed through existing GitOps paths without manual server-only cron drift.
- **SC-005**: The watcher clearly distinguishes upstream awareness from local repo applicability so users are not misled about whether they personally need to change their local Codex setup.
