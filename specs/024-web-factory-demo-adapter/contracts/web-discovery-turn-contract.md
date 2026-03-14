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

## Rules

- The web adapter must not reimplement discovery topic logic.
- The user-facing response must stay business-readable and Russian-first by default.
- The core flow must work over ordinary HTTPS request/response, even if richer transport is added later.
- Raw discovery JSON must not be rendered directly to the user.

## Failure Conditions

- browser turn bypasses the discovery runtime and mutates brief state directly
- adapter returns no next step after a valid user turn
- discovery response leaks internal JSON or repo paths
- the browser flow depends on websocket-only transport to continue
