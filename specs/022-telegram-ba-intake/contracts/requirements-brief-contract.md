# Contract: Requirements Brief

## Purpose

Define the business-readable brief that the user reviews and confirms before the factory begins concept-pack generation.

## Required Sections

- problem statement
- target users
- current process
- desired outcome
- scope boundaries
- user story
- input examples
- expected outputs
- business rules
- exception cases
- constraints
- success metrics
- open risks

## Rules

- The brief must be understandable to the business user who provided the requirements.
- The user must be able to request corrections conversationally before confirmation.
- Confirmation must create an immutable confirmed snapshot for one exact brief version.
- Reopening a confirmed brief must create a new version instead of overwriting the previous confirmed version.

## Required Outputs

- one current draft or confirmed `RequirementBrief`
- one or more `BriefRevision` records when meaningful changes occur
- one active `ConfirmationSnapshot` only for the current confirmed version
- optional `confirmation_history` when a previously confirmed brief is reopened or superseded

## Failure Conditions

- the brief omits user story, examples, constraints, or success metrics
- the user cannot correct the brief without manual file editing
- a confirmed version is overwritten in place
- downstream generation is triggered from an unconfirmed draft
- reopening the brief destroys the previous confirmation snapshot instead of archiving it
