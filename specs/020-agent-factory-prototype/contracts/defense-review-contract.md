# Contract: Defense Review

## Purpose

Define how a concept pack moves through review, feedback, approval, and rework before any production swarm is allowed to start.

## Required Review Inputs

- concept id
- concept version
- current artifact set
- review outcome
- structured feedback items

## Allowed Outcomes

- `approved`
- `rework_requested`
- `rejected`
- `pending_decision`

## Rules

- Approval applies only to one exact concept version.
- `rework_requested` must preserve the previously reviewed version and feedback history.
- `approved` may unlock production only when the approval record is active.
- `rejected` must block production for that concept version.
- `pending_decision` must not be treated as implicit approval.

## Required Outputs

- one `DefenseReview`
- zero or more `FeedbackItem` records
- updated `ConceptRecord.decision_state`
- explicit next-step summary

## Failure Conditions

- approval is missing version linkage
- feedback is captured only in freeform text with no impacted artifact mapping
- production is triggered from a non-approved concept version
