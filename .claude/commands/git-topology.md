---
description: Inspect and reconcile the generated git topology registry
argument-hint: "[status|check|refresh|doctor] [--write-doc] [--prune]"
---

# Git Topology Command

Thin wrapper around `scripts/git-topology-registry.sh`.

## Codex Note

- In Claude-style clients, examples below use `/git-topology`.
- In Codex CLI, prefer calling `scripts/git-topology-registry.sh` directly.
- Do not assume `/git-topology` is registered as a native Codex slash command.

## Quick Usage

```bash
/git-topology
/git-topology status
/git-topology check
/git-topology refresh
/git-topology doctor
```

## Defaults

- Empty input (`/git-topology`) means `status`.
- `refresh` always maps to `scripts/git-topology-registry.sh refresh --write-doc`.
- `doctor` defaults to `scripts/git-topology-registry.sh doctor --prune`.
- `doctor --write-doc` maps to `scripts/git-topology-registry.sh doctor --prune --write-doc`.

## Workflow

1. Verify the repo root and `scripts/git-topology-registry.sh` exist.
2. Route the request directly to the owner script without hand-editing `docs/GIT-TOPOLOGY-REGISTRY.md`.
3. Return the script output verbatim unless the user asked for explanation.
4. If `check` or `doctor` reports stale state, recommend `/session-summary` or `scripts/git-topology-registry.sh refresh --write-doc`.
5. If `refresh` or `doctor --write-doc` changed the registry, say so explicitly in the final status and note that a tracked diff in `docs/GIT-TOPOLOGY-REGISTRY.md` is expected after real topology drift.

## Safety Rules

- Never hand-edit `docs/GIT-TOPOLOGY-REGISTRY.md`.
- Prefer `doctor --prune` before cleanup work when state may be stale.
- Use `status` or `check` for read-only inspection.
- Use `refresh --write-doc` only when the command is meant to reconcile committed state.
