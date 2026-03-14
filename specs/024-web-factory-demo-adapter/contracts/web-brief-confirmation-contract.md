# Contract: Web Brief Confirmation

## Purpose

Define how the browser UI presents a reviewable requirements brief, accepts conversational corrections, and records explicit confirmation or reopen actions.

## Required Inputs

- active `WebDemoSession`
- one current draft or confirmed `RequirementBrief`
- zero or more correction requests

## Required Behavior

- render the brief into readable browser sections
- accept conversational corrections without file editing
- require explicit confirmation before downstream handoff
- preserve versioned confirmation history when reopening a confirmed brief

## Rules

- The user must be able to see what exact brief version is being confirmed.
- Reopen must create a new version chain rather than overwrite the previous confirmed version.
- Material contradictions or unresolved clarifications must block confirmation.
- Confirmation state must stay traceable back to the upstream discovery session.

## Failure Conditions

- the user cannot distinguish correction from confirmation
- a confirmed brief is overwritten in place
- downstream handoff starts from an unconfirmed or superseded brief
- browser confirmation hides which version became active
