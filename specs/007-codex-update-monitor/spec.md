# Feature Specification: Codex CLI Update Monitor

**Feature Branch**: `007-codex-update-monitor`  
**Created**: 2026-03-09  
**Status**: Draft  
**Input**: Synthesized from `docs/plans/codex-cli-update-monitoring-speckit-seed.md` and `docs/research/codex-cli-update-monitoring-2026-03-09.md`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operator Gets An Update Decision Fast (Priority: P1)

An operator runs one command and receives a machine-readable report plus a concise human summary showing whether the locally installed Codex CLI should be upgraded now, reviewed later, ignored, or investigated.

**Why this priority**: This is the minimum useful outcome. Without a fast recommendation, the repository still depends on manual changelog reading and ad hoc memory.

**Independent Test**: Run the monitor against a known local Codex installation and receive a deterministic report that includes local version, latest checked version, recommendation, and supporting evidence.

**Acceptance Scenarios**:

1. **Given** the local Codex CLI is installed and upstream release information is reachable, **When** the operator runs the monitor, **Then** the workflow returns a structured report and human summary with a recommendation status.
2. **Given** the local Codex CLI is current and no workflow-relevant change is detected, **When** the operator runs the monitor, **Then** the workflow recommends `ignore` or `upgrade-later` instead of creating noisy follow-up work.
3. **Given** upstream release information is temporarily unavailable, **When** the operator runs the monitor, **Then** the workflow returns `investigate` with actionable evidence about which source failed.

---

### User Story 2 - Maintainer Gets Repository-Relevant Analysis (Priority: P2)

A repository maintainer receives an explanation of which upstream Codex changes matter to this repository's real working patterns, such as worktrees, approvals, AGENTS boundaries, skills, and non-interactive runs.

**Why this priority**: A raw version delta is not enough. The repository needs upgrade advice tied to its actual operating model, not a generic release digest.

**Independent Test**: Run the monitor on a fixture set of upstream changes and confirm the output separates workflow-relevant changes from non-relevant changes while explaining the reasoning.

**Acceptance Scenarios**:

1. **Given** an upstream release contains features affecting worktrees, approvals, or non-interactive execution, **When** the monitor evaluates the release, **Then** those changes appear in the report as relevant with repository-specific rationale.
2. **Given** an upstream release contains changes that do not materially affect this repository, **When** the monitor evaluates the release, **Then** those changes are classified as non-relevant and do not drive an aggressive recommendation.

---

### User Story 3 - Backlog Follow-Up Is Optional But Actionable (Priority: P3)

A backlog owner can explicitly request follow-up issue sync so that upgrade-worthy changes become tracked work with evidence and next steps, without making tracker mutation the default behavior.

**Why this priority**: Valuable upgrades should not disappear into chat history, but default runs must remain safe and non-mutating.

**Independent Test**: Run the monitor once without tracker flags and confirm it is read-only, then run it with explicit issue-sync flags and confirm it prepares or updates a tracked follow-up with evidence.

**Acceptance Scenarios**:

1. **Given** the operator runs the monitor without tracker flags, **When** the recommendation is `upgrade-now`, **Then** the workflow reports the suggested issue action without mutating tracker state.
2. **Given** the operator runs the monitor with explicit tracker-sync flags, **When** the recommendation crosses the configured action threshold, **Then** the workflow creates or updates a Beads follow-up item with evidence and next steps.
3. **Given** the monitor is asked to sync tracker state but prerequisites for tracker access are unavailable, **When** execution completes, **Then** the workflow reports `investigate` or `skipped` issue action without hiding the failure.

---

### User Story 4 - The Contract Stays Reusable (Priority: P4)

A future maintainer can wrap the monitor in a skill or other thin orchestration layer without rewriting the collector logic or scraping free-form output.

**Why this priority**: The repository wants reusable operational building blocks, but v1 should avoid over-investing in a plugin-first or agent-first design.

**Independent Test**: Invoke the monitor through a wrapper-style command path and confirm the wrapper can rely on stable outputs, exit behavior, and report fields without parsing ad hoc prose.

**Acceptance Scenarios**:

1. **Given** a thin wrapper invokes the monitor, **When** the monitor completes successfully, **Then** the wrapper can consume stable machine-readable outputs and a separate human summary.
2. **Given** the monitor returns a precondition or source error, **When** a wrapper consumes the result, **Then** the failure mode remains explicit and machine-readable.

### Edge Cases

- What happens when the local Codex CLI is missing from `PATH`?
- What happens when the local version is ahead of, equal to, or behind the latest verified upstream release?
- How does the workflow behave when upstream release notes are reachable but optional issue feeds are not?
- How does the workflow behave when local feature detection succeeds only partially?
- What happens when tracker sync is requested but the target issue cannot be read or updated?
- How does the workflow behave when the same recommendation is generated repeatedly across consecutive runs?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect the locally installed Codex CLI version.
- **FR-002**: System MUST detect the local workflow traits that materially affect repository behavior, including enabled Codex features and relevant repository operating-model signals.
- **FR-003**: System MUST compare local state against the latest official Codex release information.
- **FR-004**: System MUST support optional upstream issue-signal analysis as secondary evidence without making it a hard dependency for baseline execution.
- **FR-005**: System MUST produce a deterministic machine-readable report for every completed run.
- **FR-006**: System MUST produce a concise human-readable summary that cites the evidence behind its recommendation.
- **FR-007**: System MUST classify each run as `upgrade-now`, `upgrade-later`, `ignore`, or `investigate`.
- **FR-008**: System MUST explain which upstream changes are relevant to this repository and which are not.
- **FR-009**: Default execution MUST be read-only with respect to repository runtime behavior and tracker state.
- **FR-010**: Tracker mutation MUST require an explicit operator opt-in.
- **FR-011**: Initial tracker integration MUST target Beads only while keeping the design open to future sinks.
- **FR-012**: System MUST support both on-demand local execution and a CI-safe manual automation entrypoint.
- **FR-013**: System MUST keep issue-signal evidence advisory; remote issue activity alone MUST NOT force an upgrade recommendation.
- **FR-014**: System MUST provide enough evidence in `upgrade-now` and `investigate` results for an operator to open or update a tracked follow-up item without rereading source material.
- **FR-015**: The output contract MUST remain stable enough to be wrapped later by a thin skill or other orchestration layer.

### Key Entities

- **LocalCodexState**: The observed local Codex CLI version, feature flags, and workflow-relevant configuration traits at the time of the run.
- **UpstreamReleaseSnapshot**: The verified upstream release information used for comparison, including version, date, and notable changes.
- **UpstreamIssueSignal**: Optional issue-feed evidence that may raise or lower urgency without becoming the sole decision driver.
- **RepoWorkflowProfile**: A normalized view of repository traits such as worktree discipline, approval boundaries, skills, AGENTS zones, and non-interactive usage patterns.
- **RecommendationDecision**: The final classification, rationale, evidence set, and suggested next steps for the run.
- **IssueAction**: The requested or suggested tracker action, including whether it was skipped, created, updated, or intentionally left unchanged.

### Assumptions & Dependencies

- Official Codex release information remains reachable often enough for periodic verification.
- The repository continues to use Beads as its default tracked follow-up system during v1.
- Optional issue-feed inputs may be unavailable on some runs and must not block baseline recommendation output.
- Local Codex state may be partially detectable, but partial detection must still produce an explicit and auditable result.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can determine whether action is needed in under 5 minutes without manually browsing upstream release pages.
- **SC-002**: Every successful run reports the local version, latest checked version, recommendation, and top workflow-relevant changes for this repository.
- **SC-003**: When the recommendation is `upgrade-now` or `investigate`, the report includes enough evidence to open or update a follow-up task without additional source gathering.
- **SC-004**: Default runs do not mutate tracker state or repository runtime behavior.
- **SC-005**: When no workflow-relevant change exists, the workflow recommends `ignore` or `upgrade-later` instead of generating noisy follow-up work.
- **SC-006**: A thin wrapper can consume the machine-readable contract without scraping free-form prose.
