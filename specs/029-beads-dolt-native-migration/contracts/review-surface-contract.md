# Contract: Review Surface

## Purpose

Define what replaces JSONL-first review reasoning after migration.

## Required Properties

- Human-readable
- Agent-readable
- Deterministic
- Documented
- Does not require legacy tracked `.beads/issues.jsonl` as the primary truth surface

## Minimum Coverage

- Inspect current issue-state
- Inspect pending or recent changes relevant to operator workflows
- Support pilot verification and post-cutover review

## Current Pilot Surface

For the isolated pilot worktree, the documented review surface is:

```bash
./scripts/beads-dolt-pilot.sh review
```

This command must expose:

- inventory verdict and pilot gate
- current runtime/backend summary
- read-only Beads review commands needed by operators and agents
