# Contract: Inventory And Readiness

## Purpose

Define what the migration inventory must detect and how readiness is computed.

## Required Coverage

- repo-local wrappers
- hook rewrite surfaces
- docs and AGENTS guidance
- skills/resources prescribing legacy behavior
- tracked artifacts related to legacy sync reasoning
- tests and bootstrap flows
- current backend/runtime and worktree coupling observations

## Required Verdicts

- `ready`
- `warning`
- `blocked`

## Readiness Rules

- Any unresolved critical legacy surface keeps the repo or worktree out of `pilot` readiness.
- Repeated report-only runs on unchanged inputs must return the same verdict.
- Inventory must be reviewable by humans and agents.
