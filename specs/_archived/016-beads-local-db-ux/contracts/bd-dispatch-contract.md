# Contract: Plain `bd` Dispatch

## Purpose

Define the required runtime behavior for plain `bd` inside this repository so dedicated worktrees use local ownership safely and fail closed otherwise.

## Inputs

- Current working directory
- Active `bd` executable path in the session
- Current worktree’s local `.beads/` foundation state
- Requested `bd` subcommand and whether it can mutate state

## Required Guarantees

1. Plain `bd` is the only documented default command for ordinary repo-local Beads work.
2. Dedicated-worktree mutating commands may execute only after local ownership resolves to the current worktree’s `.beads/beads.db`.
3. If safe local ownership cannot be proven, mutating commands must block before writing.
4. Blocked states must emit one actionable error and one exact recovery path.
5. Silent fallback to canonical root is forbidden.
6. The canonical root must be read-mostly by default; mutating plain `bd` commands there require an explicit intentional override.
7. Explicit troubleshooting paths remain separate from default dispatch.

## Decision States

| State | Meaning | Command Result |
|---|---|---|
| `execute_local` | The session is safely routed to the current worktree’s local DB | Execute the system `bd` against the resolved local DB |
| `pass_through_root_readonly` | The session is in the canonical root, but the requested command is read-only or explicitly `--readonly` | Allow the read-only command to use the system `bd` without rewriting its target |
| `block_missing_foundation` | Required local `.beads` files are absent | Fail closed with missing-foundation recovery guidance |
| `block_legacy_redirect` | Legacy redirect/shared ownership residue is present | Fail closed and route to managed localization |
| `block_unresolved_ownership` | The session cannot safely prove local ownership | Fail closed and route to safe bootstrap or migration |
| `block_root_fallback` | The active path would hit the canonical root tracker | Fail closed and explain that root fallback is forbidden |
| `block_root_mutation` | The session is in the canonical root and a mutating plain `bd` command was requested without an explicit target | Fail closed and require an intentional canonical-root override such as explicit `--db` |
| `allow_explicit_troubleshooting` | The user deliberately requested an explicit diagnostic path | Allow the explicit troubleshooting flow only |

## Non-Goals

- The dispatch contract does not repair canonical root state.
- The dispatch contract does not normalize legacy worktrees silently during daily command execution.
- The dispatch contract does not make raw `bd worktree create` a user-facing fallback.
