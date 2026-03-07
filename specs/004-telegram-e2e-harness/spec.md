# Feature Specification: On-Demand Telegram E2E Harness

**Feature Branch**: `004-telegram-e2e-harness`
**Created**: 2026-03-07
**Status**: Draft
**Input**: User description: "Speckit: On-Demand Telegram E2E Harness (CLI + Workflow, Manual Verdict)"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - On-Demand Synthetic E2E (Priority: P1)

An operator launches a one-shot E2E test command from a Codex chat and submits any input message. The system sends that message through Moltis HTTP chat transport and returns an execution report with the observed response.

**Why this priority**: This is the minimum viable capability needed to debug Telegram-adjacent behavior quickly without changing production bot runtime mode.

**Independent Test**: Run a single command with `/status` and receive a JSON report that includes non-empty `observed_response`, execution timestamps, and `status="completed"`.

**Acceptance Scenarios**:

1. **Given** Moltis is reachable and credentials are valid, **When** operator runs synthetic mode with message `/status`, **Then** a JSON report is produced with non-empty `observed_response` and technical metadata.
2. **Given** invalid Moltis credentials, **When** operator runs synthetic mode, **Then** execution returns an upstream/precondition failure report without leaking secrets.
3. **Given** Moltis does not return content before timeout, **When** operator runs synthetic mode, **Then** execution returns `status="timeout"` with timeout metadata.

---

### User Story 2 - Dual Trigger Interface (Priority: P2)

The same test scenario can be run either locally via CLI or remotely via GitHub `workflow_dispatch`, and both execution paths generate the same report schema.

**Why this priority**: Operators need chat-driven execution in different environments (local Codex session and GitHub-driven remote run).

**Independent Test**: Run equivalent inputs via CLI and workflow and confirm both artifacts conform to the same schema and include consistent core fields.

**Acceptance Scenarios**:

1. **Given** operator has local shell access, **When** they run CLI with required args, **Then** result artifact is created and includes required fields.
2. **Given** operator has GitHub workflow access, **When** they dispatch workflow with the same message and mode, **Then** workflow uploads compatible JSON artifact.

---

### User Story 3 - Real User Mode Contract (Deferred) (Priority: P3)

A reserved `real_user` mode is exposed for future true Telegram user emulation. In MVP it does not send messages yet, but it validates prerequisites and returns explicit deferred diagnostics.

**Why this priority**: Protects architecture from rework and allows controlled future extension without blocking MVP.

**Independent Test**: Run `mode=real_user` without required future secrets and get structured deferred/precondition diagnostics while synthetic mode remains unaffected.

**Acceptance Scenarios**:

1. **Given** `mode=real_user` is requested in MVP, **When** prerequisites are incomplete, **Then** system returns a structured deferred status with actionable hints.
2. **Given** synthetic mode is operational, **When** real_user mode is invoked and deferred, **Then** synthetic mode behavior remains unchanged.

---

### Edge Cases

- What happens when message contains quotes, unicode, markdown, or long payloads close to transport limits?
- How does system behave when output path directory does not exist or is not writable?
- How does system behave when response body is valid JSON but missing expected content fields?
- How does system behave when workflow input is empty or whitespace-only message?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support on-demand execution with parameters `mode`, `message`, and `timeout`.
- **FR-002**: System MUST support two triggers: local CLI and GitHub `workflow_dispatch`.
- **FR-003**: System MUST emit a structured JSON artifact with execution input, observed response, timing, status, and context metadata.
- **FR-004**: System MUST NOT change default production Telegram runtime behavior.
- **FR-005**: In `synthetic` mode, system MUST use existing Moltis HTTP endpoints for auth and chat (`/api/auth/login`, `/api/v1/chat`).
- **FR-006**: In MVP, `real_user` mode MUST validate prerequisites and return transparent deferred diagnostics without message delivery.
- **FR-007**: System MUST be safe for repeated manual runs (idempotent operational behavior, no persistent test-mode side effects).
- **FR-008**: System MUST redact sensitive information (passwords, tokens, session cookies) from logs and artifacts.
- **FR-009**: CLI MUST expose documented exit codes for completed, precondition/config failure, timeout, and upstream/auth failure.
- **FR-010**: Workflow MUST always upload execution artifacts even when command exits non-zero.
- **FR-011**: `real_user` mode MUST return one of `deferred_real_user` or `precondition_failed` in a structured way.

### Key Entities

- **E2ETestRun**: One execution instance with run id, trigger source, mode, message, timing, status, and context.
- **E2EReportArtifact**: JSON output document produced per run, intended for manual verdict and debugging.
- **ExecutionContext**: Transport and diagnostic metadata (HTTP codes, attempts, timeout values, prerequisite checks) with secret redaction.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operator can start a test from chat context with one command (CLI or workflow dispatch command).
- **SC-002**: A report artifact is generated within `timeout + 5 seconds` for synthetic runs.
- **SC-003**: At least 95% of synthetic runs in healthy environment produce valid JSON artifact with required schema fields.
- **SC-004**: Routine bot conversations remain available after test runs (no persistent runtime mode drift).
- **SC-005**: 100% of error paths produce structured status and error metadata without exposing secrets.
