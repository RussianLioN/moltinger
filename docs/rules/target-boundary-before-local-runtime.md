# Target Boundary Before Local Runtime (RCA-009)

**Status:** Active
**Effective date:** 2026-03-08
**Scope:** All AI sessions and maintainers

## Problem This Rule Prevents

Launching a local stack, port-forward, or local service clone when the task is actually scoped to a documented remote environment wastes time and creates unintended side effects.

## Mandatory Protocol

Before running any local runtime action, explicitly determine the target:

1. `MEMORY.md`
2. `SESSION_SUMMARY.md`
3. Relevant deploy/runtime docs in `docs/`
4. Existing session context from the user

Decide one of two modes before acting:

- `remote-target`: the source of truth is a server, remote environment, or documented production/staging service
- `local-target`: the source of truth is a local fixture stack, hermetic test compose, or local development runtime

## Hard Guardrail

If the target is `remote-target`, do **not**:

- run `docker compose up` for a replacement local app stack
- create local port-forwards to mimic the target service
- validate browser/API behavior against a local clone

unless the user explicitly asked for a local reproduction.

## Expected Behavior

- First: state which target is authoritative for the current task.
- Second: use that target for validation.
- Third: if a local reproduction is useful, ask or justify it explicitly before starting side-effectful local runtime actions.
