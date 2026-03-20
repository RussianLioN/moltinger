# Contract: Rollout And Rollback

## Purpose

Define how migration proceeds after pilot and how rollback is handled safely.

## Rollout Stages

1. `report-only`
2. `pilot`
3. `controlled cutover`
4. `verification`

## Rollout Rules

- Only ready worktrees may enter cutover.
- Blocked worktrees remain blocked and visible.
- Docs/AGENTS/skills alignment is part of rollout, not post-hoc cleanup.

## Rollback Rules

- Rollback is a separate, explicit operator path.
- Rollback preserves evidence and snapshots.
- Rollback restores a coherent operator workflow.
- Rollback does not silently recreate mixed mode.
