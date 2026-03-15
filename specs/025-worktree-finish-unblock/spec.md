# Feature Specification: Safely Unblock `command-worktree finish`

**Feature Branch**: `025-worktree-finish-unblock`  
**Created**: 2026-03-15  
**Status**: In Progress  
**Input**: User description: "Безопасно разблокировать ordinary `command-worktree finish` без регрессии local Beads ownership и без auto-publish topology."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Safe Issue Resolution for Ordinary Flows (Priority: P1)

As a maintainer finishing or diagnosing an ordinary worktree, I need the branch-to-issue resolution to stay conservative so the workflow never closes the wrong Beads issue or epic.

**Why this priority**: A false-positive issue resolution can close the wrong tracking item and is more damaging than skipping close with `Issue: n/a`.

**Independent Test**: Can be tested by running the helper and targeted shell tests against ambiguous branch names, local Beads ownership, and ordinary doctor/finish output.

**Acceptance Scenarios**:

1. **Given** a branch name that matches more than one issue id prefix, **When** ordinary finish or readiness resolves the issue, **Then** the report prints `Issue: n/a`.
2. **Given** a dedicated worktree already reporting `beads_state=local`, **When** ordinary doctor inspects it, **Then** the helper keeps the worktree ready and does not route to `beads-worktree-localize.sh`.
3. **Given** topology registry status is stale, **When** ordinary doctor or finish runs, **Then** the result stays actionable with a deferred publish warning instead of a blocker or auto-publish step.

---

### User Story 2 - Honest Finish Contract for `command-worktree` (Priority: P2)

As a maintainer using the documented `command-worktree finish` flow, I need the command contract to promise only safe ordinary-flow behavior: plain `bd`, `Issue: n/a` skip-close behavior, and deferred topology publication through a dedicated path.

**Why this priority**: The command documentation is the operator contract. If it still promises wrapper-specific or auto-publish behavior, future sessions can reintroduce unsafe finish behavior even after the helper is fixed.

**Independent Test**: Can be tested by static assertions over `.claude/commands/worktree.md` and the ordinary worktree ownership guard suite.

**Acceptance Scenarios**:

1. **Given** the ordinary `command-worktree` contract, **When** finish steps are rendered, **Then** they use plain `bd` instead of `bd-local.sh`.
2. **Given** no issue id can be resolved confidently, **When** finish runs, **Then** the contract says `Issue: n/a` and skips `bd close`.
3. **Given** topology registry status is stale, **When** ordinary finish or doctor is described, **Then** the contract defers publication to a dedicated non-main publish path and never promises auto-publication from the working branch.

## Edge Cases

- Overlapping issue ids where one normalized id is a prefix of another normalized id.
- Dedicated worktrees whose Beads probe succeeds and returns `local`, even if the worktree path differs from the derived preview path.
- Ordinary worktree flows executed while `scripts/git-topology-registry.sh check` reports `status=stale`.
- Finish flows with no confidently resolved issue id, where skipping close is safer than inferring from prose context or branch-name prefixes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Ordinary worktree readiness MUST treat branch-to-issue resolution as confident only when exactly one Beads issue id matches the normalized branch prefix.
- **FR-002**: Ordinary worktree readiness MUST emit `Issue: n/a` when branch-to-issue resolution is ambiguous or absent.
- **FR-003**: Ordinary doctor MUST preserve `beads_state=local` as a ready local-ownership state and MUST NOT route that state into `beads-worktree-localize.sh`.
- **FR-004**: Ordinary doctor and ordinary finish MUST treat stale topology as a warning with deferred publication guidance, not as a blocker and not as a trigger for automatic topology publication.
- **FR-005**: `scripts/worktree-ready.sh` MUST expose an ordinary `finish` mode that reports the resolved branch/worktree, conservative issue result, and exact next steps without auto-publishing topology from the invoking branch.
- **FR-006**: The documented ordinary `command-worktree finish` contract MUST use plain `bd` commands rather than `bd-local.sh`.
- **FR-007**: The documented ordinary `command-worktree finish` contract MUST explicitly skip `bd close` when the issue id cannot be resolved confidently and the report shows `Issue: n/a`.
- **FR-008**: The documented ordinary `command-worktree` contract MUST state that topology publication happens only through a dedicated non-main publish path, never as an automatic side effect of ordinary `doctor` or `finish`.
- **FR-009**: The implementation diff MUST stay limited to `scripts/worktree-ready.sh`, `.claude/commands/worktree.md`, `tests/unit/test_worktree_ready.sh`, `tests/static/test_beads_worktree_ownership.sh`, and `specs/025-worktree-finish-unblock/*`.

### Key Entities

- **Ordinary Worktree Report**: The human/env handoff and doctor output that includes branch, issue, topology, Beads state, warnings, and exact next steps.
- **Issue Resolution Confidence**: The helper rule deciding whether a branch name maps to exactly one Beads issue id or must fall back to `n/a`.
- **Topology Publish Path**: The dedicated non-main worktree/branch path used for `docs/GIT-TOPOLOGY-REGISTRY.md` publication when the registry is stale.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `tests/unit/test_worktree_ready.sh` passes with explicit coverage for ambiguous branch-to-issue mapping, local Beads ownership, and stale topology in ordinary doctor/finish flows.
- **SC-002**: `tests/static/test_beads_worktree_ownership.sh` passes with guards proving ordinary worktree/finish documentation does not reintroduce `bd-local.sh` or auto topology publication.
- **SC-003**: If `.claude/commands/worktree.md` changes, `make codex-check` passes without requiring edits outside the approved scope.
- **SC-004**: The final branch is pushed, a PR is opened, GitHub Actions logs are reviewed, and all PR checks are green.
