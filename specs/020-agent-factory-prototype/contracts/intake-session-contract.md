# Contract: Intake Session

## Purpose

Define the minimum contract for turning a raw user idea from Telegram into a versioned concept record and synchronized concept pack.

## Actors

- `requester`: human user proposing an automation idea
- `coordinator`: Moltinger runtime conducting the intake dialogue
- `artifact generator`: internal factory stage that emits the concept pack

## Required Inputs

- initial idea statement
- target business problem
- target users or beneficiaries
- current workflow summary
- constraints or exclusions
- measurable success expectation

## Allowed Intermediate Behavior

- follow-up questions for missing critical context
- assumption capture when the user cannot provide exact detail
- explicit recording of unresolved risks

## Required Outputs

- one `ConceptRecord`
- one synchronized `ArtifactSet`
- one user-facing download-ready output per artifact

## Rules

- Intake cannot complete while critical scope or success information is still missing.
- Artifact generation must point to one canonical concept version.
- All three artifacts must agree on scope, goals, and constraints before the contract is satisfied.
- User-facing downloads must not require direct server filesystem access.

## Failure Conditions

- concept remains too vague after clarification
- artifact set is only partially generated
- artifacts drift on scope, metrics, or assumptions
- delivery channel cannot publish the resulting files
