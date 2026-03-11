# Contract: Adapter Surface Compatibility

## Purpose

Define how Claude Code, Codex CLI, and OpenCode adapters integrate with the same portable core behavior.

## Shared Core Semantics

All supported adapters must preserve:

- worktree planning semantics
- branch/worktree contract
- handoff boundary
- post-install verification semantics
- safe default behavior

## Adapter Responsibilities

### Claude Code

- Provide the Claude-specific discovery and registration surface
- Map invocation to the shared core artifacts
- Document any manual registration fallback

### Codex CLI

- Provide the Codex bridge or skill registration surface
- Avoid bundling unrelated repo commands or agents
- Keep invocation wording aligned with shared core behavior

### OpenCode

- Provide the OpenCode-specific activation surface
- Document supported, partial, or manual-only capabilities explicitly
- Offer a fallback path when full auto-registration is unavailable

## Forbidden Adapter Behaviors

- Re-implementing core logic independently
- Introducing mandatory Moltinger-specific dependencies
- Changing branch/worktree semantics per IDE
- Hiding install prerequisites inside one adapter

## Verification Contract

Each adapter must define:

- required files or registration step
- expected discovery signal
- first invocation surface
- failure mode when adapter is missing
- correction path
