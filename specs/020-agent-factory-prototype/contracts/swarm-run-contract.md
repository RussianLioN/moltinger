# Contract: Swarm Run

## Purpose

Define the minimum contract for autonomous production after concept approval.

## Required Prerequisites

- active `ProductionApproval`
- approved concept version
- mapped stage owners for:
  - coding
  - testing
  - validation
  - audit
  - assembly

## Stage Expectations

### Coding

- transforms the approved concept into buildable agent output

### Testing

- verifies expected behavior against the approved concept and prototype checks

### Validation

- confirms the produced behavior still matches the approved scope and acceptance posture

### Audit

- checks governance, compliance, and concept-to-output alignment

### Assembly

- packages the approved output into a runnable playground bundle

## Rules

- Every stage must have explicit entry and exit status.
- Parallel execution is allowed only for independent work that does not break stage traceability.
- Blocker failures create an `EscalationPacket`.
- Completion requires evidence for every required stage.
- The swarm run ends at `PlaygroundPackage`, not deployment.

## Terminal Outcomes

- `completed`
- `failed`
- `blocked`
- `cancelled`

## Failure Conditions

- stage evidence is missing
- a downstream stage runs without prerequisite completion
- a non-approved concept version is used as source
- the swarm reaches terminal state with no reviewable evidence bundle
