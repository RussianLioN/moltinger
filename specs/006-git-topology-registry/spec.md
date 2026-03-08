# Feature Specification: Auto-Maintained Git Topology Registry

**Feature Branch**: `006-git-topology-registry`  
**Created**: 2026-03-08  
**Status**: Draft  
**Input**: User description: "Create an auto-maintained git topology registry with a deterministic script, sanitized committed snapshot, sidecar intent file, /worktree and /session-summary integration, and a thin command/skill interface for refresh/check/status/doctor."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Trust Current Git Topology (Priority: P1)

An operator or LLM session opens one shared registry and sees the current branch/worktree topology that matters for coordination, cleanup, and branch decisions without rediscovering it from scratch.

**Why this priority**: This is the minimum valuable outcome. Without a trustworthy shared topology snapshot, every cleanup or branch decision requires fresh ad hoc investigation and is prone to drift.

**Independent Test**: Create or remove a branch/worktree, refresh the registry, and confirm the committed registry reflects the new topology while staying sanitized and readable.

**Acceptance Scenarios**:

1. **Given** the repository contains multiple active worktrees and feature branches, **When** an operator reads the registry, **Then** they see the current shared topology in one place.
2. **Given** topology changed and the registry was refreshed, **When** the operator reads the registry, **Then** the old topology is no longer shown.
3. **Given** the registry is committed to the repo, **When** it is reviewed, **Then** it does not expose absolute workstation paths or other unnecessary local-only details.

---

### User Story 2 - Keep Registry Current Through Managed Workflows (Priority: P2)

When topology changes through managed repo workflows, the registry is refreshed or validated in the same operational flow so that session handoff and cleanup actions do not rely on stale information.

**Why this priority**: The registry only helps if it stays current during the main workflows already used by the team, especially worktree lifecycle and session handoff.

**Independent Test**: Run a topology-changing managed workflow, then verify the registry is either refreshed automatically or the operator is explicitly stopped with a clear remediation step before handoff/cleanup.

**Acceptance Scenarios**:

1. **Given** a managed worktree-start flow creates a new branch/worktree, **When** the flow finishes successfully, **Then** the registry is refreshed in the same session.
2. **Given** a managed cleanup flow removes a worktree or branch, **When** the flow finishes successfully, **Then** the registry no longer lists the removed topology.
3. **Given** the registry is stale at session handoff time, **When** the handoff workflow runs, **Then** the operator receives a clear refresh/check path before relying on the registry.

---

### User Story 3 - Preserve Human Intent and Recover From Drift (Priority: P3)

The team can keep reviewed branch/worktree intent separately from generated git facts, and can recover safely when topology changes were made manually outside the managed workflows.

**Why this priority**: Git can discover structure, but not operational meaning. The system must preserve human decisions while still recovering from out-of-band user actions.

**Independent Test**: Add reviewed intent for a branch, change topology outside the managed workflows, run recovery/refresh, and confirm both the regenerated topology and preserved intent are still correct.

**Acceptance Scenarios**:

1. **Given** a branch has reviewed intent metadata, **When** the registry is regenerated, **Then** the reviewed intent remains attached to that branch.
2. **Given** a user changed branches or worktrees manually outside the managed flows, **When** the operator runs the recovery/check path, **Then** the registry can be reconciled back to live git state.
3. **Given** topology has not changed, **When** the refresh path runs repeatedly, **Then** it does not create meaningless diffs or churn.

---

### Edge Cases

- What happens when topology changes occur outside the managed repo workflows?
- How does the system behave when the repo has no `origin/main` or no remote at all?
- How does the system behave when a worktree is detached, stale, or otherwise incomplete?
- What happens when reviewed intent exists for a branch or worktree that no longer exists?
- How does the system behave when two topology refreshes are attempted at nearly the same time?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST produce one committed git topology registry that reflects current shared branch/worktree state relevant to repository coordination.
- **FR-002**: System MUST derive topology facts from live git state rather than from hand-maintained markdown.
- **FR-003**: System MUST keep reviewed human intent separate from generated git facts and preserve that intent across registry regeneration.
- **FR-004**: System MUST provide explicit lifecycle actions to refresh, check, inspect status, and recover the registry when drift is detected.
- **FR-005**: System MUST refresh or validate the registry during managed topology-changing workflows and during session handoff workflows.
- **FR-006**: System MUST treat live git state as the source of truth whenever the registry and git disagree.
- **FR-007**: System MUST update the committed registry only when normalized topology content has changed.
- **FR-008**: System MUST render the committed registry in a deterministic, low-churn format suitable for review in git.
- **FR-009**: System MUST sanitize the committed registry so it does not expose unnecessary local-only details such as absolute workstation paths.
- **FR-010**: System MUST support safe reconciliation after topology changes initiated manually by the user outside managed workflows.
- **FR-011**: System MUST provide actionable stale-state feedback before destructive cleanup or handoff workflows rely on the registry.
- **FR-012**: System MUST preserve useful coordination context for active, historical, protected, and undecided branches/worktrees.
- **FR-013**: System MUST degrade gracefully when expected remote topology context is unavailable.
- **FR-014**: System MUST NOT change git topology itself as part of registry maintenance.

### Key Entities *(include if feature involves data)*

- **LiveTopologySnapshot**: The normalized set of current worktrees, local branches, relevant remote branches, and their shared state as discovered from live git.
- **TopologyIntentRecord**: Reviewed, non-derivable coordination metadata attached to a branch or worktree, such as protection, historical status, or cleanup intent.
- **TopologyRegistryDocument**: The committed, sanitized markdown view used by operators and LLM sessions.
- **TopologyRegistryHealth**: The freshness and recoverability state of the registry compared with current live git topology.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a managed topology mutation, the registry can be refreshed to the correct new state in the same session in under 5 seconds on a normal developer machine.
- **SC-002**: Re-running the refresh path with unchanged topology produces no committed diff.
- **SC-003**: 100% of managed topology workflows either refresh the registry or stop with an actionable stale-state instruction before handoff/cleanup.
- **SC-004**: The committed registry contains no absolute local workstation paths in its rendered topology tables.
- **SC-005**: Reviewed intent metadata survives regeneration for 100% of covered branches/worktrees in the acceptance test scenarios.
