# Contract: Telegram Session Routing

## Purpose

Define how the Telegram adapter resolves one inbound user message to the correct factory project, discovery session, or brief state.

## Required Prerequisites

- one active `TelegramAdapterSession` or enough input to create it
- one resolved `TelegramIntent`
- zero or one `ActiveProjectPointer`
- access to the persisted discovery snapshot when the project already exists

## Required Outputs

- one resolved routing decision
- one updated `ActiveProjectPointer`
- one adapter state transition summary
- zero or one delegated call into the discovery runtime

## Rules

- Starting a new project must create a new active project pointer.
- Continuing an existing project must reuse the current pointer unless the user explicitly reopens or switches context.
- `/status` or equivalent intent must return the current project state without mutating discovery content.
- Resume must preserve the pending discovery question or pending clarification instead of generating a new unrelated question.
- Reopening a confirmed brief must supersede the old pointer and create a new active version chain.

## Failure Conditions

- a free-form Telegram answer is routed to the wrong project
- the adapter opens a second active pointer for the same user without explicit reason
- resume causes the user to lose the pending question or clarification
- a status request accidentally changes discovery or brief state
