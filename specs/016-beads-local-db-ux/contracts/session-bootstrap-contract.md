# Contract: Session Bootstrap For Plain `bd`

## Purpose

Define how a session becomes safe for plain `bd` without forcing the user to choose a wrapper command.

## Required Channels

The repository must provide at least two supported bootstrap channels:

1. `direnv`/`.envrc` for shells where environment approval is available
2. Managed launch/handoff paths for Codex/App or other sessions where `direnv` is unavailable or not approved

## Required Guarantees

1. A safely bootstrapped session resolves plain `bd` to the repo-local dispatch path before the system-wide binary.
2. The bootstrap path does not require the user to remember a second Beads command name.
3. A session that is not safely bootstrapped is detectable and receives one exact remediation step.
4. Managed worktree and Codex launch flows must preserve this bootstrap behavior in their next-step guidance.

## Bootstrap States

| State | Meaning | Expected User Experience |
|---|---|---|
| `ready` | The session resolves plain `bd` through the repo-local safe path | User runs ordinary `bd` commands successfully |
| `not_bootstrapped` | The session still resolves to an unsafe system path | User sees a fail-closed error and one exact bootstrap step |
| `ambiguous` | The session cannot prove which `bd` path is active | User sees a blocking message rather than silent execution |

## Non-Goals

- This contract does not require `direnv` to be installed.
- This contract does not require permanent global shell changes outside the repo.
