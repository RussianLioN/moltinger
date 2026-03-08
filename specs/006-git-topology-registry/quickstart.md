# Quickstart: Auto-Maintained Git Topology Registry

## Refresh the Registry

```bash
scripts/git-topology-registry.sh refresh --write-doc
```

Use after a topology mutation when you want the committed registry brought back in sync with live git state.

## Check Whether the Registry Is Stale

```bash
scripts/git-topology-registry.sh check
```

Use before cleanup, branch deletion, or session handoff.

## Inspect Current Health

```bash
scripts/git-topology-registry.sh status
```

Use when you need to know whether the registry is current without writing files.

## Recover After Manual Drift

```bash
scripts/git-topology-registry.sh doctor --prune --write-doc
```

Use when branches or worktrees were changed manually outside managed workflows.

## Expected Workflow Integration

- `/worktree start` should refresh the registry after successful creation.
- `/worktree cleanup` should refresh the registry after successful removal/deletion.
- `/session-summary` should check the registry at handoff time and refresh when stale.
- `pre-push` should validate freshness for topology-sensitive operations.

## Sidecar Intent Editing

Reviewed intent belongs in the sidecar file, not in the generated registry markdown.
