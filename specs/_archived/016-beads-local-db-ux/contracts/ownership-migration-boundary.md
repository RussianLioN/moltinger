# Contract: Ownership Migration Boundary

## Purpose

Define the allowed behavior for migrating existing worktrees while keeping residual root cleanup separate.

## Required Guarantees

1. Existing worktrees may be classified as `current`, `migratable_legacy`, `partial_foundation`, or `damaged_blocked`.
2. Safe in-place localization is allowed only for states that can be repaired without changing branch or worktree identity.
3. If a worktree cannot be localized safely, the flow must stop and report one exact repair path.
4. Residual root cleanup is a separate stream and must not be silently performed as part of compatibility migration.
5. A successful migration converges to local ownership; it never converges back to shared redirect ownership.

## Migration Outcomes

| State | Meaning | Allowed Outcome |
|---|---|---|
| `current` | Worktree already satisfies local ownership contract | No migration needed |
| `migratable_legacy` | Legacy redirect/shared residue exists but local ownership can be materialized safely | Localize in place |
| `partial_foundation` | Local ownership files are incomplete but rebuildable without ambiguity | Rebuild local foundation in place |
| `damaged_blocked` | State is ambiguous, conflicting, or unsafe to repair automatically | Stop and report |

## Root Cleanup Boundary

- Root cleanup may be observed and reported.
- Root cleanup may produce a separate follow-up task or issue.
- Root cleanup must not be a hidden side effect of compatibility migration.
- Dedicated-worktree safety must be testable independently from root cleanup completion.
