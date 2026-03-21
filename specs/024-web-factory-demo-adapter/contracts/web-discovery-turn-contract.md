# Contract: Web Discovery Turn

## Purpose

Define how one browser turn becomes a discovery-runtime turn and returns one user-facing next step.

## Required Inputs

- active `WebDemoSession`
- one `WebConversationEnvelope`
- current discovery snapshot or raw start-project idea

## Required Behavior

- normalize the browser action into one discovery-runtime request
- route it into the existing `022` discovery runtime
- return one user-facing `WebReplyCard` or grouped reply set
- update the safe status snapshot for the current project
- preserve pending-question continuity so the next turn answers the active topic instead of spawning unrelated questions
- close `input_examples` topic when the first valid user-provided example (text or attachment) is accepted
- expose one deterministic next action (`ask`, `clarify`, `await_confirm`, `handoff_ready`, `blocked`) for each processed turn

## Rules

- The web adapter must not reimplement discovery topic logic.
- The user-facing response must stay business-readable and Russian-first by default.
- The core flow must work over ordinary HTTPS request/response, even if richer transport is added later.
- Raw discovery JSON must not be rendered directly to the user.
- A topic already accepted in the current draft must not be re-asked unless reopened or contradicted.
- Duplicate submit events while one request is in-flight must coalesce into one logical turn.
- Clarification retries must be explicit and finite; silent loops are not allowed.
- In this prototype, user-provided examples are treated as anonymized by default; do not request separate anonymization proofs unless runtime raises a high-confidence unsafe-content signal.

## Failure Conditions

- browser turn bypasses the discovery runtime and mutates brief state directly
- adapter returns no next step after a valid user turn
- discovery response leaks internal JSON or repo paths
- the browser flow depends on websocket-only transport to continue
- accepted user-provided example still causes repeated requests for anonymization proof or the same `input_examples` content
- adapter reports success while no topic transition or explicit blocked-state reason is produced
