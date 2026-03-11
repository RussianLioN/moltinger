# Feature Specification: Worktree Handoff Hardening

**Feature Branch**: `011-worktree-handoff-hardening`  
**Created**: 2026-03-09  
**Status**: Draft  
**Input**: User description: "Create a feature for hardening the `command-worktree` Phase A / Phase B boundary and manual handoff contract."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enforce Stop After Phase A (Priority: P1)

As an operator or agent using `command-worktree`, I need create and attach flows to stop exactly at the handoff boundary so the originating session cannot continue downstream work by accident.

**Why this priority**: The primary defect is unsafe boundary leakage. If the originating session can continue Phase B, the workflow becomes untrustworthy even when worktree setup succeeds.

**Independent Test**: Submit a mixed request that asks `command-worktree` to create or attach a worktree and then continue downstream work. The flow is successful only if it returns the handoff payload and stops without continuing the downstream task in the originating session.

**Acceptance Scenarios**:

1. **Given** a create request that also includes downstream work for the target worktree, **When** `command-worktree` completes Phase A successfully, **Then** it returns the handoff output and stops without executing or preparing Phase B in the originating session.
2. **Given** an attach request for an existing branch that also includes downstream work, **When** the attach flow succeeds, **Then** it stops at handoff with the same hard boundary instead of continuing downstream execution locally.
3. **Given** the user explicitly requests automatic Codex or terminal launch, **When** that launch succeeds, **Then** the originating session reports the launched handoff and stops immediately afterward.
4. **Given** the user explicitly requests automatic Codex or terminal launch, **When** that launch is unavailable or fails, **Then** the workflow degrades to manual handoff and still stops after Phase A.

---

### User Story 2 - Preserve Rich Manual Handoff Intent (Priority: P1)

As an operator handing off complex downstream work manually, I need the workflow to preserve rich downstream intent so the next session can continue accurately without losing constraints, feature descriptions, or stopping rules.

**Why this priority**: The current one-line `pending_summary` is too lossy for Speckit startup and other structured requests, which makes manual handoff unreliable for the workflows that need it most.

**Independent Test**: Submit a long, structured downstream request such as Speckit startup with explicit boundaries and defaults. The handoff is successful only if the concise summary remains available while a richer carrier preserves critical downstream intent for the next session.

**Acceptance Scenarios**:

1. **Given** a mixed request with a long, structured downstream task, **When** Phase A completes, **Then** the handoff preserves a short pending summary and a richer Phase B seed payload or equivalent structured carrier for the downstream session.
2. **Given** a downstream request that contains exact feature descriptions, scope boundaries, defaults, and stop conditions, **When** manual handoff is rendered, **Then** those critical constraints are preserved without being collapsed into a single lossy sentence.
3. **Given** a simple downstream request, **When** manual handoff is rendered, **Then** the workflow may keep the payload concise without forcing unnecessary verbosity.

---

### User Story 3 - Align Helper Output And Workflow Contract (Priority: P2)

As a maintainer of the worktree workflow, I need helper output, command instructions, and handoff semantics to agree so operators and tests can rely on one consistent boundary contract.

**Why this priority**: Boundary hardening fails if helper behavior, workflow instructions, and visible output describe different rules.

**Independent Test**: Compare the documented contract, helper output, and user-facing guidance for the same create or attach flow. The story passes only if they express the same boundary, handoff modes, and payload semantics.

**Acceptance Scenarios**:

1. **Given** a successful manual handoff flow, **When** the helper output and workflow instructions are reviewed together, **Then** they agree on the authoritative stop-after-Phase-A boundary.
2. **Given** a handoff that includes both concise and rich downstream intent carriers, **When** the contract is reviewed, **Then** each carrier has a clear role and the workflow does not treat them as interchangeable.
3. **Given** an operator reads the helper output alone, **When** they follow it, **Then** they are not instructed to resume or continue Phase B in the originating session.

---

### User Story 4 - Guard Against Regression For Complex Prompts (Priority: P2)

As a maintainer shipping future worktree changes, I need regression coverage for long and structured downstream requests so the boundary and handoff contract do not silently weaken later.

**Why this priority**: The defect was exposed by realistic complex prompts rather than by trivial create flows. Coverage must reflect that operational reality.

**Independent Test**: Run the regression suite against create and attach flows that include complex downstream requests. The story passes only if the suite detects boundary leakage, lost intent, or contract drift.

**Acceptance Scenarios**:

1. **Given** a long Speckit-oriented downstream request, **When** regression coverage is executed, **Then** it verifies strict stop-after-Phase-A behavior and preservation of critical downstream intent.
2. **Given** future changes to helper output or workflow instructions, **When** regression coverage is executed, **Then** it fails if boundary behavior or handoff payload semantics drift from the contract.

---

### Edge Cases

- A mixed request includes multiline downstream intent with bullets, quoted text, explicit defaults, and stop conditions.
- The originating session successfully creates or attaches the worktree but the requested automatic handoff launch fails.
- The request contains no explicit downstream task; the workflow must still stop after Phase A without inventing extra Phase B work.
- The concise pending summary and the richer downstream seed diverge; the contract must define which one is authoritative for which purpose.
- Existing worktree creation and attach behavior must remain stable unless a change is required to enforce the boundary or preserve handoff correctness.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `command-worktree` MUST remain a Phase A-only workflow unless an explicit launched handoff session takes over Phase B.
- **FR-002**: Successful create flows MUST stop after handoff and MUST NOT continue downstream execution in the originating session.
- **FR-003**: Successful attach flows MUST stop after handoff and MUST NOT continue downstream execution in the originating session.
- **FR-004**: Mixed requests that combine worktree setup with downstream work MUST treat the downstream work as deferred payload only during Phase A.
- **FR-005**: During Phase A, the workflow MUST NOT analyze, decompose, implement, or otherwise advance deferred downstream work beyond packaging it for handoff.
- **FR-006**: During Phase A, the workflow MUST NOT create or update downstream artifacts such as Speckit packages, Beads tasks, plans, checklists, or implementation notes.
- **FR-007**: Manual handoff MUST preserve a concise `pending_summary` or equivalent short pending field for quick human scanning.
- **FR-008**: Manual handoff MUST also preserve richer downstream intent for complex requests via a structured Phase B seed payload or an equivalent explicit carrier that is distinct from the short pending field.
- **FR-009**: The contract MUST clearly distinguish the purpose of the short pending summary from the richer downstream intent carrier.
- **FR-010**: The richer downstream intent carrier MUST preserve critical constraints from the originating request, including exact feature descriptions, scope boundaries, defaults, and stop conditions when they were provided.
- **FR-011**: If no rich downstream intent was provided by the user, the workflow MAY omit the richer carrier while still preserving the hard Phase A stop behavior.
- **FR-012**: Manual handoff MUST remain the default mode.
- **FR-013**: Automatic Codex or terminal handoff MUST remain opt-in only.
- **FR-014**: If automatic handoff launch is requested but unavailable, the workflow MUST degrade to manual handoff without weakening the stop-after-handoff boundary.
- **FR-015**: Helper output, workflow instructions, and any user-facing command guidance MUST agree on the same boundary semantics, handoff modes, and payload roles.
- **FR-016**: The feature MUST document and reproduce the boundary-violation scenario that motivated this change so future maintainers can understand the defect.
- **FR-017**: The feature MUST define the expected manual handoff contract for both short pending intent and rich downstream intent.
- **FR-018**: The feature MUST require regression coverage for long, structured downstream requests, including Speckit startup flows.
- **FR-019**: Regression coverage MUST fail if create or attach flows continue downstream work in the originating session after a successful handoff.
- **FR-020**: Regression coverage MUST fail if critical downstream constraints from a structured request are lost from the handoff contract.
- **FR-021**: The fix MUST remain compatible with existing worktree creation flows unless a behavior change is necessary for boundary or handoff correctness.
- **FR-022**: The fix MUST remain Speckit-compatible for downstream startup workflows and MUST NOT weaken the stop-after-handoff boundary.
- **FR-023**: The feature MUST stay within worktree boundary and handoff scope and MUST NOT redesign unrelated Beads flows, unrelated topology workflows, production behavior, or unrelated features.

### Key Entities *(include if feature involves data)*

- **Phase A Boundary**: The authoritative stop point for `command-worktree` create and attach flows, after which the originating session may only report handoff status and must not continue downstream work.
- **Manual Handoff Contract**: The user-facing and machine-readable description of what the next session should do, which boundary applies, and which handoff mode is in effect.
- **Pending Summary**: A concise human-readable summary of deferred downstream work intended for quick scanning.
- **Phase B Seed Payload**: A richer downstream-intent carrier that preserves structured instructions, constraints, defaults, and stopping rules needed by the follow-up session.
- **Regression Scenario**: A representative create or attach request, especially Speckit-oriented, used to prove the boundary and handoff behavior do not regress.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of validated create and attach mixed-request scenarios, the originating session stops at handoff and does not continue downstream execution after Phase A succeeds.
- **SC-002**: In 100% of validated structured downstream-request scenarios, critical constraints from the originating request are preserved in the handoff contract without relying only on a one-line summary.
- **SC-003**: In 100% of validated manual-handoff scenarios, the contract clearly distinguishes the short pending summary from the richer downstream-intent carrier when both are present.
- **SC-004**: Helper output, workflow instructions, and regression tests all encode the same boundary semantics and handoff expectations for the covered scenarios.
- **SC-005**: Regression coverage includes at least one long, structured Speckit startup request and fails when either boundary leakage or downstream-intent loss is reintroduced.
- **SC-006**: Existing non-defective worktree setup behavior remains unchanged in validated scenarios except where adjustment is required to enforce the boundary or preserve handoff correctness.
