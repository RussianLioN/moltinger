# Speckit Bridge

## Purpose

Keep `worktree-skill` compatible with artifact-first Speckit workflows without turning Speckit into a hard dependency.

## Guarantees

- `spec.md`, `plan.md`, and `tasks.md` remain authoritative
- `/speckit.spec`, `/speckit.plan`, and `/speckit.tasks` are not overridden
- branch-spec alignment remains visible and intentional
- dedicated worktree handoff remains compatible with spec-driven feature work

## Install

Copy this directory only if the host project uses Speckit.
