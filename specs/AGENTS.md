# Specs Instructions

This directory contains Speckit-style planning artifacts. These files are part of the implementation contract, not optional documentation.

## Core Rule

Before changing runtime code for a spec-driven task, reconcile the spec artifacts first.

At minimum verify:
- `spec.md`
- `plan.md`
- `tasks.md`

Optional supporting artifacts such as `research.md`, `quickstart.md`, `data-model.md`, or `backlog.md` must also stay coherent if they exist.

## Rules

1. Keep branch and spec intent aligned.
   If work is clearly tied to a spec package, the branch should match that effort.
2. Do not update runtime behavior and leave `tasks.md` stale.
   Completed implementation steps should be reflected in the checklist.
3. Do not hide spec drift.
   If implementation diverges from the plan, update the spec artifacts or explicitly call out the divergence.
4. Prefer artifact-first clarification.
   If the task is underspecified, improve the spec before improvising in code.
5. Do not leave untracked spec files behind.
   Hidden spec artifacts create process drift.

## Validation

Before concluding spec-driven work, check:
- the relevant spec package is tracked and complete
- task checkboxes reflect actual completion
- implementation and artifacts tell the same story

## Escalation

Stop and ask if:
- the requested implementation clearly contradicts the spec
- the wrong branch and spec pairing is being used
- multiple spec packages appear to apply at once
