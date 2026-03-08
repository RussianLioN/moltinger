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
scripts/git-topology-registry.sh doctor --prune
```

Use this first when branches or worktrees were changed manually outside managed workflows and you want a recovery draft without mutating the committed registry.

Recovery draft path:

```bash
.git/topology-registry/registry.draft.md
```

Then reconcile for real:

```bash
scripts/git-topology-registry.sh doctor --prune --write-doc
```

This writes the committed registry and preserves the previous committed version under:

```bash
.git/topology-registry/backups/
```

Expected result after a real topology mutation:

- `doctor --prune` is read-only for tracked files and only writes the draft under `.git/topology-registry/`
- `doctor --prune --write-doc` updates `docs/GIT-TOPOLOGY-REGISTRY.md`
- seeing `M docs/GIT-TOPOLOGY-REGISTRY.md` in `git status` after `--write-doc` is expected whenever the committed snapshot had to catch up with live git state

## Expected Workflow Integration

- `/worktree start` should refresh the registry after successful creation.
- `/worktree cleanup` should refresh the registry after successful removal/deletion.
- `/session-summary` should check the registry at handoff time and refresh when stale.
- `pre-push` should validate freshness for topology-sensitive operations.

## Sidecar Intent Editing

Reviewed intent belongs in the sidecar file, not in the generated registry markdown.

- Edit `docs/GIT-TOPOLOGY-INTENT.yaml`
- Keep records sorted by `subject_type`, then `subject_key`
- If a reviewed record no longer matches live topology, the generated registry will surface it under `Reviewed Intent Awaiting Reconciliation`
- Missing or invalid `intent` values fall back to `needs-decision`

## Manual Reconciliation Flow

1. Edit `docs/GIT-TOPOLOGY-INTENT.yaml` when you have reviewed branch/worktree meaning to preserve.
2. If topology changed through raw `git` commands, run `scripts/git-topology-registry.sh doctor --prune`.
3. Inspect `.git/topology-registry/registry.draft.md`.
4. If the draft is correct, run `scripts/git-topology-registry.sh doctor --prune --write-doc`.
5. If needed, compare the regenerated registry against the backup in `.git/topology-registry/backups/`.

## Merge-Ready Handoff

Primary files to review before merge:

- `scripts/git-topology-registry.sh`
- `docs/GIT-TOPOLOGY-INTENT.yaml`
- `docs/GIT-TOPOLOGY-REGISTRY.md`
- `.claude/commands/worktree.md`
- `.claude/commands/session-summary.md`
- `.claude/commands/git-topology.md`
- `.githooks/pre-push`
- `tests/integration/test_git_topology_registry.sh`
- `tests/e2e/test_git_topology_registry_workflow.sh`

Recommended validation sequence:

```bash
./tests/unit/test_git_topology_registry.sh
./tests/integration/test_git_topology_registry.sh
./tests/e2e/test_git_topology_registry_workflow.sh
./scripts/setup-git-hooks.sh
./scripts/git-topology-registry.sh refresh --write-doc
./scripts/git-topology-registry.sh check
```
