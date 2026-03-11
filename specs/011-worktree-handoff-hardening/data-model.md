# Data Model: Worktree Handoff Hardening

## PhaseABoundary

- **Purpose**: Represents the authoritative stop condition for `command-worktree` create and attach flows.
- **Fields**:
  - `command_type`: `create` or `attach`
  - `phase`: always `Phase A` for the originating session contract
  - `stop_required`: whether the originating session must stop after handoff
  - `automatic_launch_requested`: whether Codex or terminal launch was explicitly requested
  - `automatic_launch_succeeded`: whether the requested launch actually succeeded
  - `final_state`: resulting handoff or blocked state reported to the operator
- **Relationships**:
  - Owns one `ManualHandoffContract` when the flow reaches handoff
  - Is validated by one or more `RegressionScenario` records

## PendingSummary

- **Purpose**: Holds the short, human-readable summary of deferred downstream work.
- **Fields**:
  - `text`: concise summary for quick scanning
  - `source_present`: whether the originating request included downstream work
  - `intended_use`: quick handoff scanning, not full downstream reconstruction
- **Relationships**:
  - Belongs to one `ManualHandoffContract`
  - May coexist with one `PhaseBSeedPayload`

## PhaseBSeedPayload

- **Purpose**: Preserves rich downstream intent when the originating request is too complex for a one-line summary.
- **Fields**:
  - `payload_present`: whether a richer carrier is needed
  - `feature_description`: exact downstream feature description when provided
  - `constraints`: preserved scope boundaries and do-not-do rules
  - `defaults`: auto-resolved defaults that must carry into Phase B
  - `stop_conditions`: explicit stop rules that the follow-up session must respect
  - `intended_use`: structured seed for the downstream session only
- **Relationships**:
  - Belongs to one `ManualHandoffContract`
  - Supplements, but does not replace, `PendingSummary`

## ManualHandoffContract

- **Purpose**: Defines what the originating session returns when Phase A completes and the workflow hands off manually.
- **Fields**:
  - `worktree_path`: target worktree path
  - `branch`: target branch
  - `handoff_mode`: manual, terminal, or Codex
  - `boundary_state`: stop-after-create or stop-after-attach outcome
  - `pending_summary`: short deferred-intent carrier
  - `phase_b_seed_payload`: optional richer deferred-intent carrier
  - `next_steps`: exact operator actions for the next session
- **Relationships**:
  - Is produced by one `PhaseABoundary`
  - Is exercised by one or more `RegressionScenario` records

## RegressionScenario

- **Purpose**: Represents a testable workflow example used to prove the contract.
- **Fields**:
  - `name`: scenario identifier
  - `flow_type`: create or attach
  - `downstream_prompt_shape`: none, short, or structured
  - `launch_mode`: manual, terminal, or Codex
  - `expected_boundary`: required stop-after-Phase-A behavior
  - `expected_handoff_fields`: the boundary and payload signals that must remain present
- **Relationships**:
  - Validates one `PhaseABoundary`
  - Verifies one `ManualHandoffContract`
