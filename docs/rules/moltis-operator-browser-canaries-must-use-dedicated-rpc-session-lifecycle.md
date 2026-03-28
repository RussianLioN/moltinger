# Rule: Moltis operator browser canaries must use a dedicated RPC session lifecycle in one WS connection

## Scope

Applies to operator-side browser smoke checks, deploy verification, runtime attestation follow-up
canaries, and any other repo-owned script that drives Moltis browser automation against a shared
remote environment.

## Rule

If an operator/browser canary needs to run on shared Moltis, all of the following must hold:

1. The canary must not reuse the default `main` chat session.
2. The canary must create or switch to a dedicated operator session key.
3. Session switch, chat clear, chat send, and session cleanup must run in the same WS RPC
   connection.
4. The dedicated session must be cleaned up after the run.
5. Telegram/browser verification must fail closed if the operator path falls back to the default
   session or if cleanup is missing.

## Why

- Official Moltis browser docs describe browser session reuse inside the current chat session.
- A `sessions.switch` performed in one WS connection does not prove isolation for a later
  `chat.send` opened on a different connection.
- Shared production browser capacity is limited; fake session isolation can contaminate operator
  and user traffic.

## Required Behavior

- Prefer a single RPC sequence for:
  - `sessions.switch`
  - `chat.clear`
  - `chat.send`
  - `sessions.delete`
- Do not claim cleanup success based only on a session-switch response.
- Do not guess a global `browser-*` slot from Docker logs as the primary cleanup mechanism.
- Re-pair Telegram Web only when the authoritative state is actually missing or the helper
  explicitly reports login/pairing drift.

## Minimum Verification

- `scripts/test-moltis-api.sh` runs the chat workflow through one WS RPC sequence.
- `scripts/moltis-browser-canary.sh` passes a dedicated operator session key and requests cleanup.
- component tests cover:
  - dedicated session switch/delete lifecycle
  - Telegram Web outgoing probe attribution when preview text is appended
- live proof on the authoritative target shows:
  - final `chat` event carries the dedicated operator session key
  - the dedicated session is absent from `sessions.list` after cleanup
