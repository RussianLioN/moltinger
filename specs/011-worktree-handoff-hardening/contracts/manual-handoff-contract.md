# Contract: Manual Handoff Contract

## Purpose

Define how manual handoff preserves both quick-scanning context and rich downstream intent without weakening the Phase A stop boundary.

## Contract Elements

### 1. Core Handoff Status

- Worktree path
- Branch
- Boundary/final-state signal
- Exact next-step commands or equivalent next actions

### 2. Pending Summary

- A concise human-readable summary of deferred downstream work
- Intended for quick scanning by the operator or next session
- Must stay short enough to remain readable in the handoff block

### 3. Rich Phase B Seed Payload

- Optional, but required when the downstream request is structured enough that a one-line summary would lose critical context
- Preserves:
  - exact feature descriptions
  - scope boundaries
  - defaults that were auto-resolved during specify-like setup
  - explicit stop conditions or do-not-do instructions
- Must be clearly separated from the short pending summary so their roles are not confused

## Behavioral Rules

- Manual handoff remains the default.
- A richer Phase B seed payload supplements the pending summary; it does not replace the short summary.
- The originating session must not treat the richer payload as permission to begin Phase B.
- If the originating request contains only simple deferred work, the richer payload may be omitted.
- If the originating request contains structured downstream work, the richer payload must preserve the critical details needed by the follow-up session.

## Trust Boundary

- The handoff contract is the end of Phase A for manual flows.
- Everything inside the contract is preparation for the next session, not execution in the current one.
