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
- apply correction as section-targeted patch (replace/update), not as blind append
- block confirmation until required output-design topics are captured: `result_format`, `processing_algorithm`, `constraints`, `success_metrics` (or explicitly marked as open risk)

## Rules

- The user must be able to see what exact brief version is being confirmed.
- Reopen must create a new version chain rather than overwrite the previous confirmed version.
- Material contradictions or unresolved clarifications must block confirmation.
- Confirmation state must stay traceable back to the upstream discovery session.
- Canonical brief text must be normalized and business-readable; service helper phrases and accidental verbatim user fragments must not pollute final sections.
- Section corrections must not drift into unrelated sections (e.g., `input_examples` edit into `expected_output`).

## Failure Conditions

- the user cannot distinguish correction from confirmation
- a confirmed brief is overwritten in place
- downstream handoff starts from an unconfirmed or superseded brief
- browser confirmation hides which version became active
- UI says “правка применена”, but the original wrong text remains and new text appears in another section
