# Feature Specification: Safe Batch Recovery of Leaked Beads Issues

**Feature Branch**: `010-beads-recovery-batch`  
**Created**: 2026-03-09  
**Status**: Draft  
**Input**: User description: "Automate safe batch recovery of leaked Beads issues from the canonical root tracker into owner worktrees with an audit-first, fail-closed workflow, explicit blockers for ambiguous ownership, per-run journal/snapshots, and no root cleanup in the same step."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Audit Recovery Candidates Before Any Write (Priority: P1)

An operator runs one recovery audit and gets a deterministic plan that shows which leaked issues are safe to recover automatically, which worktrees must be localized first, and which issues are blocked because ownership is ambiguous or topology is stale.

**Why this priority**: This is the minimum valuable outcome. Without a trustworthy audit-first plan, any automation risks writing tracker state into the wrong worktree or mutating the canonical root tracker blindly.

**Independent Test**: Run the audit against a fixture with mixed local and redirected worktrees plus leaked issues, then confirm the plan clearly separates safe recoveries from blocked cases without modifying tracker state.

**Acceptance Scenarios**:

1. **Given** leaked issues exist only in the canonical root tracker, **When** the operator runs the audit workflow, **Then** the system produces a reviewable plan that lists each issue, its proposed owner worktree if any, and the reason for that decision.
2. **Given** an issue cannot be mapped to one owner worktree with high confidence, **When** the audit workflow runs, **Then** that issue is marked blocked and excluded from automatic recovery.
3. **Given** a target worktree still points to shared Beads state, **When** the audit workflow runs, **Then** the plan marks that worktree as requiring localization before any recovery apply step.

---

### User Story 2 - Apply Only High-Confidence Recoveries Safely (Priority: P2)

An operator applies a previously generated recovery plan and the system recovers only the explicitly safe issues into the correct localized owner worktrees while leaving blocked or ambiguous cases untouched.

**Why this priority**: This is the first automation step that actually removes manual toil while preserving safety boundaries. It must be deterministic, narrow, and fail closed.

**Independent Test**: Generate a plan with both safe and blocked issues, run the apply workflow, and confirm only safe issues are recovered into the intended worktrees while blocked issues and the canonical root tracker remain unchanged.

**Acceptance Scenarios**:

1. **Given** a recovery plan contains high-confidence items and blocked items, **When** the operator runs the apply workflow, **Then** only the high-confidence items are recovered.
2. **Given** a target worktree is redirected but otherwise recoverable, **When** the apply workflow runs, **Then** the system localizes that worktree before recovering its issues.
3. **Given** an issue is already present in the target worktree, **When** the apply workflow runs, **Then** the system records that duplicate state and does not re-import it blindly.

---

### User Story 3 - Leave Reviewable Evidence and Cleanup Guidance (Priority: P3)

After an audit or apply run, the operator gets a durable journal showing what was recovered, what was blocked, which backups were created, and whether root cleanup is still prohibited.

**Why this priority**: Safe automation is not only about doing writes carefully. It must also leave clear evidence for review, rollback, and follow-up cleanup decisions.

**Independent Test**: Run the workflow, inspect the generated journal and backups, and confirm a maintainer can tell exactly what changed, what did not change, and whether canonical root cleanup is still blocked.

**Acceptance Scenarios**:

1. **Given** an audit-only run completed, **When** the operator reads the run journal, **Then** they can see proposed recoveries, blockers, and unresolved items without inspecting raw tracker files manually.
2. **Given** an apply run recovered several issues, **When** the operator reads the run journal, **Then** they can see which issues changed, which backups were created, and which worktrees were touched.
3. **Given** unresolved or blocked issues remain, **When** the workflow finishes, **Then** the output clearly states that canonical root cleanup is still not allowed.

### Edge Cases

- What happens when the same leaked issue appears in both the canonical root tracker and a candidate owner worktree?
- What happens when an ownership mapping points to a branch that exists but currently has no attached worktree?
- What happens when a candidate owner worktree still has `.beads/redirect` or is otherwise not localized?
- What happens when live topology changed after the plan was generated but before apply runs?
- What happens when the current tracker database cannot safely import due to prefix mismatch or other non-owner-related drift?
- What happens when one recovery in a batch fails after earlier recoveries already succeeded?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide an audit-first recovery workflow that produces a deterministic recovery plan before any tracker files are modified.
- **FR-002**: System MUST evaluate leaked issues from the canonical root tracker against live git worktree topology rather than assuming branch ownership from issue IDs alone.
- **FR-003**: System MUST support explicit owner mapping for issues whose ownership cannot be derived safely from live topology.
- **FR-004**: System MUST mark ambiguous, missing, stale, or otherwise unsafe recovery candidates as blocked instead of attempting best-effort recovery.
- **FR-005**: System MUST allow operators to apply recoveries only from a previously generated plan artifact.
- **FR-006**: System MUST recover only high-confidence items during automatic apply.
- **FR-007**: System MUST localize redirected owner worktrees before recovering tracker state into them.
- **FR-008**: System MUST preserve the exact leaked issue record during recovery unless a safety rule explicitly prevents import into the local database.
- **FR-009**: System MUST detect when a target worktree already contains an issue and record that state without duplicating the issue.
- **FR-010**: System MUST create reviewable run evidence, including the plan used, touched worktrees, backups, and per-issue outcomes.
- **FR-011**: System MUST leave blocked items untouched and clearly report why they were excluded from automatic apply.
- **FR-012**: System MUST NOT delete or rewrite canonical root tracker records during the same command that performs recovery apply.
- **FR-013**: System MUST indicate whether canonical root cleanup remains prohibited after each run.
- **FR-014**: System MUST support safe reruns without duplicating previously recovered issues.
- **FR-015**: System MUST degrade gracefully when the local tracker database cannot safely import and still preserve file-level recovery evidence when allowed.

### Key Entities *(include if feature involves data)*

- **RecoveryCandidate**: A leaked issue found in the canonical root tracker with its current status, potential owner, confidence level, and blocker state.
- **OwnershipMapping**: The explicit or derived linkage between an issue and its owner branch/worktree, including the reason that mapping is considered safe or blocked.
- **RecoveryPlan**: A deterministic manifest describing which candidates are safe to apply, which worktrees require localization, and which items are blocked.
- **RecoveryJournal**: A durable per-run record containing decisions, outcomes, touched worktrees, backups, and unresolved blockers.
- **RecoveryBackup**: A point-in-time snapshot of target tracker state created before automatic apply modifies a worktree.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a workstation with the current repository topology, an audit run completes and produces a reviewable recovery plan in under 10 seconds.
- **SC-002**: 100% of ambiguous ownership cases are reported as blocked rather than being applied automatically.
- **SC-003**: An apply run modifies only worktrees listed as safe in the plan and leaves blocked items untouched in 100% of acceptance-test scenarios.
- **SC-004**: Every apply run leaves one durable journal and at least one rollback-relevant backup for each modified worktree.
- **SC-005**: After an apply run with unresolved blockers, the workflow explicitly reports that canonical root cleanup remains prohibited.
