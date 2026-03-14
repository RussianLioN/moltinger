# Contract: Telegram Delivery And Handoff

## Purpose

Define how a confirmed Telegram-driven brief automatically enters the downstream factory pipeline and how the generated user-facing artifacts are delivered back to the same Telegram conversation.

## Required Prerequisites

- one active `TelegramAdapterSession`
- one confirmed `RequirementBrief`
- one ready `FactoryHandoffRecord`
- downstream concept-pack generation available through the existing `020` scripts

## Required Outputs

- one downstream launch acknowledgement in Telegram
- one successful call chain through `handoff -> intake -> artifacts` or one sanitized failure status
- delivery of:
  - project doc
  - agent spec
  - presentation
- provenance linking Telegram conversation, confirmed brief version, handoff record, and generated artifacts

## Rules

- The adapter must not require operator copy-paste once the brief is confirmed.
- The adapter must block delivery attempts when the brief is unconfirmed, reopened, superseded, or otherwise not handoff-ready.
- User-facing status messages must be concise and free of internal repo paths or stack traces.
- Artifact delivery should use Telegram document delivery semantics rather than asking the user to fetch files from the server manually.
- Delivery failures must preserve the downstream provenance so an operator can retry or diagnose them.

## Failure Conditions

- downstream generation starts from an unconfirmed brief
- the user sees a success message but does not receive all required artifacts
- artifact delivery references internal file paths instead of Telegram-accessible output
- provenance between Telegram session, brief version, handoff record, and concept artifacts is lost
- operator intervention is required for normal successful delivery
