# Feature Specification: Codex CLI Update Advisor

**Feature Branch**: `008-codex-update-advisor`
**Created**: 2026-03-09
**Status**: Draft
**Input**: Synthesized from the completed `007-codex-update-monitor` package plus the follow-up requirement that users should receive low-noise update notifications and concrete repository change suggestions.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operator Gets A Low-Noise Alert (Priority: P1)

An operator runs one advisor command and quickly sees whether this Codex update needs attention now, has already been seen, can be ignored, or needs investigation, without rereading the same result every time.

**Why this priority**: If the advisor repeats the same alert on every run, people will stop trusting it. Noise control is the minimum requirement for making update monitoring operationally useful.

**Independent Test**: Run the advisor twice against the same upgrade-worthy input and the same state file. The first run should notify; the second run should suppress the duplicate while preserving a complete report.

**Acceptance Scenarios**:

1. **Given** the monitor reports a new upgrade-worthy change and no prior advisor state exists, **When** the operator runs the advisor, **Then** the advisor records a notify-worthy result and explains what changed.
2. **Given** the same advisor fingerprint was already recorded earlier, **When** the operator runs the advisor again, **Then** the advisor suppresses the duplicate notification and explains that the result was already seen.
3. **Given** the advisor state file is missing or malformed, **When** the operator runs the advisor, **Then** the advisor still returns a complete report and treats the run as a fresh evaluation instead of failing opaquely.

---

### User Story 2 - Maintainer Gets Concrete Project Change Suggestions (Priority: P2)

A repository maintainer receives a short, prioritized list of project changes worth considering, with rationale and impacted repository surfaces such as docs, scripts, workflows, or AGENTS guidance.

**Why this priority**: A version recommendation alone still leaves the team asking what to change in this repository. The advisor is only useful if it translates Codex changes into likely repository follow-up work.

**Independent Test**: Run the advisor on fixture-backed monitor results that include workflow-relevant changes and verify the output includes concrete suggestions tied to impacted repository paths and rationale.

**Acceptance Scenarios**:

1. **Given** upstream changes affect worktree behavior, approvals, or `js_repl`, **When** the advisor processes the monitor result, **Then** it proposes repository-specific follow-up changes with impacted paths and reasons.
2. **Given** upstream changes do not materially affect this repository, **When** the advisor processes the monitor result, **Then** it avoids generic churn and produces either no suggestions or only clearly low-priority notes.
3. **Given** multiple relevant change categories appear in one run, **When** the advisor generates suggestions, **Then** it groups or prioritizes them so the maintainer can see the most important follow-up work first.

---

### User Story 3 - Backlog Owner Gets A Ready-To-Track Implementation Brief (Priority: P3)

A backlog owner can explicitly request a tracked follow-up so that the advisor turns the current recommendation and project suggestions into a Beads item with clear next steps, while default runs remain read-only.

**Why this priority**: Valuable advice should not disappear into terminal history, but tracker mutation must remain deliberate and auditable.

**Independent Test**: Run the advisor once without tracker flags and once with explicit tracker-sync flags. Confirm the default path is read-only and the opt-in path creates or updates a Beads brief that includes suggestions and impacted paths.

**Acceptance Scenarios**:

1. **Given** a notify-worthy advisor result and no tracker flags, **When** the advisor finishes, **Then** it reports a suggested follow-up without mutating Beads.
2. **Given** explicit tracker-sync flags and a notify-worthy result, **When** the advisor finishes, **Then** it creates or updates a Beads item containing the recommendation, project suggestions, and next steps.
3. **Given** tracker sync was requested but Beads is unavailable or the target cannot be updated, **When** the advisor finishes, **Then** it returns an explicit skipped or investigate outcome instead of hiding the failure.

---

### User Story 4 - Wrapper Or Scheduler Can Consume The Advisor Safely (Priority: P4)

A future thin wrapper, manual workflow, or scheduler can consume the advisor through a stable JSON contract, predictable stdout behavior, and explicit state handling.

**Why this priority**: The advisor should become a reusable operational building block, not a terminal-only one-off.

**Independent Test**: Invoke the advisor in wrapper-style mode and confirm callers can rely on stable JSON fields for notification state, suggestions, and issue action without scraping free-form prose.

**Acceptance Scenarios**:

1. **Given** a wrapper calls the advisor with machine-readable output enabled, **When** the advisor succeeds, **Then** the wrapper can read notification status, suggestions, and next steps from structured output.
2. **Given** the advisor consumes an existing monitor report instead of running the monitor itself, **When** execution completes, **Then** the resulting advisor contract remains the same.

### Edge Cases

- What happens when the monitor report is missing required fields or is internally inconsistent?
- What happens when the latest Codex version changed but the repository-relevant fingerprint did not?
- What happens when the advisor state directory does not exist yet?
- What happens when the advisor sees `investigate` from the monitor and cannot safely suggest specific repository changes?
- What happens when the same Beads target is updated repeatedly from repeated advisor runs?
- What happens when the monitor finds no relevant changes but the local version is behind?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST be able to consume an existing monitor report or invoke the existing Codex update monitor to obtain baseline evidence.
- **FR-002**: System MUST treat the completed `007-codex-update-monitor` contract as the single source of truth for version and relevance evidence rather than reimplementing upstream comparison logic.
- **FR-003**: System MUST compute a stable notification fingerprint from the current monitor evidence and repository-relevant decision data.
- **FR-004**: System MUST support a configurable state file so repeated runs can suppress duplicate notifications.
- **FR-005**: System MUST classify notification behavior for each run as at least `notify`, `suppressed`, `none`, or `investigate`.
- **FR-006**: System MUST produce a deterministic machine-readable advisor report for every completed run.
- **FR-007**: System MUST produce a concise human-readable summary in plain language.
- **FR-008**: System MUST generate prioritized repository change suggestions with rationale and impacted repository surfaces.
- **FR-009**: Suggestions MUST be traceable to monitor evidence and repository workflow traits; the advisor MUST NOT invent generic follow-up tasks without rationale.
- **FR-010**: Default execution MUST remain read-only with respect to tracker state and repository runtime behavior.
- **FR-011**: Tracker mutation MUST require explicit operator opt-in.
- **FR-012**: When tracker sync is requested, the follow-up brief MUST include the recommendation, notification state, suggestions, impacted paths, and next steps.
- **FR-013**: Missing or malformed advisor state MUST NOT block report generation.
- **FR-014**: The advisor MUST support wrapper-safe stdout behavior and stable exit semantics.
- **FR-015**: If no notify-worthy change exists, the advisor MUST avoid creating noisy follow-up work.

### Key Entities

- **MonitorSnapshot**: The normalized subset of the monitor contract that the advisor uses as input.
- **NotificationFingerprint**: A stable digest representing the current actionable state so repeated runs can suppress duplicates safely.
- **AdvisorState**: Persisted local record of the last notified fingerprint and related metadata.
- **NotificationDecision**: The per-run decision describing whether the advisor should notify, suppress, stay silent, or investigate.
- **ProjectChangeSuggestion**: A concrete repository follow-up item with priority, rationale, impacted paths, and next steps.
- **ImplementationBrief**: A concise grouped handoff payload for tracker sync or human review.
- **AdvisorIssueAction**: The requested or suggested tracker action that results from the advisor run.

### Assumptions & Dependencies

- The existing `scripts/codex-cli-update-monitor.sh` remains available as the baseline evidence collector.
- V1 notification surfaces are limited to terminal summary, JSON or Markdown artifacts, and optional Beads follow-up; external push channels are out of scope.
- The local advisor state file may live outside git-tracked paths and may be created on first run.
- Beads remains the only tracker sink in v1.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can understand whether the current update needs fresh attention in under 2 minutes from one advisor run.
- **SC-002**: The first notify-worthy run includes at least one concrete repository change suggestion tied to impacted paths or explicitly states why no concrete suggestion is safe.
- **SC-003**: Re-running the advisor with unchanged actionable state suppresses duplicate notifications instead of repeating the same alert.
- **SC-004**: A backlog owner can create or update a tracked follow-up from one explicit advisor run without rereading upstream release notes.
- **SC-005**: Default runs do not mutate tracker state.
- **SC-006**: A thin wrapper can consume the advisor JSON contract without scraping prose.
