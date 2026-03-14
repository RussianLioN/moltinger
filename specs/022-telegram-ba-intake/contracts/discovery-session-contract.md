# Contract: Discovery Session

## Purpose

Define the minimum contract for turning a raw factory-interface conversation into a structured, reviewable discovery session for a future AI-agent project.

## Actors

- `business_user`: non-technical инициатор автоматизации
- `discovery_agent`: factory digital employee on Moltis acting as AI business analyst
- `factory_coordinator`: downstream factory logic that waits for confirmed input

## Required Inputs

- initial automation idea in free-form text
- target business problem or pain point
- target users or beneficiaries
- current workflow summary
- desired outcome

## Allowed Intermediate Behavior

- adaptive follow-up questions
- assumption capture when details are unavailable
- explicit unresolved-topic tracking
- contradiction detection and clarification requests
- example capture for inputs, outputs, rules, and exceptions

## Required Outputs

- one `DiscoverySession`
- topic-level progress across required requirement areas
- zero or more `ClarificationItem` records
- one reviewable draft `RequirementBrief`

## Rules

- Discovery cannot be treated as complete while critical topics remain unresolved without being represented as open risks.
- The user must be able to answer in non-technical language.
- The session must survive interruption and later continuation without losing confirmed context.
- The agent must not skip directly to downstream concept-pack generation from raw dialogue alone.

## Failure Conditions

- the session loses previously confirmed context after interruption
- the agent repeatedly asks already confirmed questions with no justification
- the session appears complete but critical topics are still missing
- free-form examples are not captured into structured discovery state
