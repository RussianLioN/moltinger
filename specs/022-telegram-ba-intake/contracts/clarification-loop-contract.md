# Contract: Clarification Loop

## Purpose

Define how the discovery agent handles missing information, ambiguity, contradictions, and unsafe examples before a brief can be confirmed.

## Trigger Conditions

- critical topic missing
- answer too ambiguous for downstream use
- examples conflict with prior requirements
- provided example appears to contain sensitive or production data

## Required Behavior

- create one `ClarificationItem` per material unresolved issue
- ask a user-facing follow-up question in business language
- link the clarification back to the affected topic or example
- either resolve the issue or explicitly carry it into `open_risks`

## Rules

- Contradictions cannot be silently ignored.
- Unsafe examples cannot be treated as acceptable prototype examples without sanitization or replacement.
- Clarifications must be traceable to the conversation and to the affected brief sections.
- The loop ends only when the issue is resolved, intentionally deferred as an open risk, or the brief is reopened for revision.

## Failure Conditions

- contradiction detected but no clarification item created
- unsafe example accepted without warning
- clarification resolved in free text with no structured traceability
- confirmation proceeds while material contradictions remain hidden
