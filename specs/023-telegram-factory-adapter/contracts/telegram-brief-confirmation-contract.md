# Contract: Telegram Brief Confirmation

## Purpose

Define how the Telegram adapter presents a reviewable requirements brief, accepts corrections, and records explicit confirmation or reopen actions from inside the messenger conversation.

## Required Prerequisites

- one active discovery snapshot that has reached `awaiting_confirmation`
- one renderable brief version from the `022` runtime
- one active Telegram adapter session and project pointer

## Required Outputs

- Telegram-readable brief summary messages
- one or more correction requests mapped back into the discovery runtime when needed
- one explicit confirmation event or one reopen event
- updated user-facing status text after each brief action

## Rules

- The adapter must not expose raw JSON or internal schema objects when rendering the brief.
- The adapter must support conversational correction requests without asking the user to edit files.
- Confirmation must be explicit and tied to one exact brief version.
- Reopening must preserve prior confirmation and handoff history instead of overwriting it.
- The adapter must block downstream handoff while the brief is draft, reopened, or superseded.

## Failure Conditions

- the user cannot tell which brief version is being confirmed
- the adapter confirms a brief without an explicit Telegram confirmation action
- a correction request is accepted but not mapped back into the underlying brief state
- reopen silently mutates a previously confirmed brief instead of versioning it
