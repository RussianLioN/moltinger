# Contract: Ownership Sync

## Purpose

Определить, кто имеет право выполнять mutating rewrite branch-local `.beads/issues.jsonl` и когда операция должна блокироваться до записи.

## Inputs

- current worktree path
- canonical root path
- current branch identity
- resolved `.beads/beads.db` path
- intended `.beads/issues.jsonl` path
- current ownership state (`current`, `legacy`, `partial`, `ambiguous`, `damaged`)
- operation type (`read-only`, `semantic sync`, `migration`, `explicit root operation`)

## Required Invariants

1. Dedicated worktree semantic sync may target only its own tracked `.beads/issues.jsonl`.
2. Canonical root mutation is never implicit; it requires an explicit root-scoped intent.
3. Sibling worktree rewrite is never a valid incidental side effect.
4. Legacy or ambiguous ownership can never auto-upgrade itself by silently writing first.

## Decision Codes

| Code | Meaning | Write Allowed |
|------|---------|---------------|
| `allow_semantic_sync` | Safe dedicated-worktree rewrite to the owned JSONL target | Yes |
| `allow_root_explicit` | Explicit operator-approved root-scoped write | Yes |
| `block_root_leak` | Dedicated worktree would write into canonical root | No |
| `block_sibling_rewrite` | Current context would rewrite another worktree’s JSONL | No |
| `block_ambiguous_owner` | Authority cannot be determined uniquely | No |
| `block_legacy_migration_required` | Legacy/partial state must be migrated first | No |
| `block_noise_only_rewrite` | Change is non-semantic and should not rewrite tracked state | No |

## Outputs

- stable decision code
- allow/deny result
- target path when allowed
- blocking explanation when denied
- recovery hint
- optional root-cleanup notice

## Failure Rules

- If required ownership inputs are missing, default to `block_ambiguous_owner`.
- If current worktree and target JSONL path do not match, default to deny.
- No fallback may auto-promote a blocked path into a write.
