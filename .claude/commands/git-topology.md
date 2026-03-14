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
- `refresh` is an explicit publish operation and maps to `scripts/git-topology-registry.sh refresh --write-doc`.
- `doctor` defaults to `scripts/git-topology-registry.sh doctor --prune`.
- `doctor --write-doc` maps to `scripts/git-topology-registry.sh doctor --prune --write-doc`.

## Workflow

1. Verify the repo root and `scripts/git-topology-registry.sh` exist.
2. Route the request directly to the owner script without hand-editing `docs/GIT-TOPOLOGY-REGISTRY.md`.
3. Treat `status` and `check` as read-only inspection, and treat `doctor --prune` as ordinary non-publishing maintenance that may rewrite shared draft/cache state without touching the tracked markdown snapshot.
4. Treat `refresh` or `doctor --write-doc` as explicit topology snapshot publication.
5. For publish operations, do not use canonical `main` or an ordinary feature branch; require the dedicated non-main branch `chore/topology-registry-publish` in its own publish worktree.
6. Return the script output verbatim unless the user asked for explanation.
7. If `check` or `doctor` reports stale state, recommend explicit publish from the dedicated topology-publish worktree/branch instead of implying that any current branch should land the snapshot.
8. If `refresh` or `doctor --write-doc` changed the registry, say so explicitly in the final status and note that this was an intentional publish step.

## Safety Rules

- Never hand-edit `docs/GIT-TOPOLOGY-REGISTRY.md`.
- Prefer `doctor --prune` before cleanup work when state may be stale; it is a non-publishing maintenance path, not a tracked-doc write.
- Use `status` or `check` for read-only inspection.
- Use `refresh --write-doc` only for explicit topology snapshot publication from the dedicated non-main branch `chore/topology-registry-publish` in its own publish worktree.
