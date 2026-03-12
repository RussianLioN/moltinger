# Contract: Factory Handoff

## Purpose

Define how a confirmed discovery brief becomes the upstream source for the existing concept-pack pipeline.

## Required Prerequisites

- active `DiscoverySession`
- current `RequirementBrief` in confirmed state
- active `ConfirmationSnapshot` for the exact brief version
- no unresolved blocker that should prevent downstream generation

## Required Outputs

- one canonical `FactoryHandoffRecord`
- explicit next-step summary for concept-pack generation
- provenance links back to discovery session and confirmed brief version

## Rules

- Handoff applies only to one exact confirmed brief version.
- Downstream concept-pack generation must be blocked if the brief is still draft, reopened, or superseded.
- The handoff record must preserve traceability from conversational discovery to downstream concept artifacts.
- Users must not need to manually copy requirements from chat into factory files.

## Failure Conditions

- a concept pack is generated from an unconfirmed or superseded brief
- the handoff record has no version linkage to the confirmed brief
- provenance back to the discovery session is lost
- downstream artifact generation requires manual reconstruction of the brief
