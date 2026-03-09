# Consilium Report: Git Topology Registry Automation

**Date**: 2026-03-08  
**Question**: How should this repo keep `docs/GIT-TOPOLOGY-REGISTRY.md` current when branches/worktrees are created, switched, removed, or cleaned up by either the LLM or the user?

## Expert Opinions

### Prompt / Instructions
- Session-start behavior should be intent-gated, not unconditional.
- Session-end behavior should be mutation-gated and mandatory after topology changes.
- Instructions should stay compact to avoid prompt bloat.

### Security
- The committed registry must be sanitized.
- Absolute workstation paths and freeform notes should not be persisted in tracked docs.
- Hooks must not become destructive or broad doc mutators.

### GitOps
- Live `git` is runtime truth; the registry is a generated governance artifact.
- The registry needs one deterministic owner script.
- `HEAD` and other volatile fields should not drive churn in the committed file.

### DevOps / Workflow
- The right architecture is script-first, not agent-first.
- `/worktree` and `/session-summary` are the cleanest lifecycle integration points.
- Hooks should validate staleness, not rewrite tracked markdown.

### SRE
- Use full reconcile against live git state plus best-effort event hints.
- Keep repo-wide state in `git-common-dir`, not per-worktree only.
- Provide `status` and `doctor` flows for stale-state recovery.

### Testing
- The feature needs explicit discovery, formatting, hook, and workflow contracts.
- Parser/rendering behavior should have shell-based unit and integration coverage.
- Hook installer parity must be tested or simplified.

## Consensus

1. `docs/GIT-TOPOLOGY-REGISTRY.md` should become a generated coordination artifact.
2. The primary maintainer is a deterministic shell script, not a long-running agent.
3. Non-derivable intent must live in a small committed sidecar file.
4. `/worktree` and `/session-summary` should trigger refresh/check flows.
5. Git hooks should remain validation/backstop mechanisms, not silent writers.
6. The committed registry must be sanitized and low-churn.

## Final Recommendation

Implement a hybrid with a clear center of gravity:

- **Primary**: `scripts/git-topology-registry.sh`
- **Companion input**: `docs/GIT-TOPOLOGY-INTENT.yaml` or equivalent
- **Generated output**: `docs/GIT-TOPOLOGY-REGISTRY.md`
- **Workflow wiring**: `.claude/commands/worktree.md`, `.claude/commands/session-summary.md`
- **Validation only**: `.githooks/*`
- **Optional future helper**: a thin `/git-topology` command/skill that wraps the script

## Implementation Reconciliation

The implementation now matches the recommendation with only one deliberate extension: recovery artifacts are persisted in `git-common-dir` so that stale-state reconcile can preserve a draft and backup without touching tracked docs until the operator chooses to write.

Delivered artifacts:

- Owner script: [scripts/git-topology-registry.sh](/Users/rl/coding/moltinger-006-git-topology-registry/scripts/git-topology-registry.sh)
- Reviewed sidecar: [docs/GIT-TOPOLOGY-INTENT.yaml](/Users/rl/coding/moltinger-006-git-topology-registry/docs/GIT-TOPOLOGY-INTENT.yaml)
- Generated registry: [docs/GIT-TOPOLOGY-REGISTRY.md](/Users/rl/coding/moltinger-006-git-topology-registry/docs/GIT-TOPOLOGY-REGISTRY.md)
- Workflow wiring:
  - [worktree.md](/Users/rl/coding/moltinger-006-git-topology-registry/.claude/commands/worktree.md)
  - [session-summary.md](/Users/rl/coding/moltinger-006-git-topology-registry/.claude/commands/session-summary.md)
  - [git-topology.md](/Users/rl/coding/moltinger-006-git-topology-registry/.claude/commands/git-topology.md)
- Validation hooks:
  - [pre-push](/Users/rl/coding/moltinger-006-git-topology-registry/.githooks/pre-push)
  - [post-checkout](/Users/rl/coding/moltinger-006-git-topology-registry/.githooks/post-checkout)
  - [post-merge](/Users/rl/coding/moltinger-006-git-topology-registry/.githooks/post-merge)
  - [post-rewrite](/Users/rl/coding/moltinger-006-git-topology-registry/.githooks/post-rewrite)
- Operator handoff: [quickstart.md](/Users/rl/coding/moltinger-006-git-topology-registry/specs/006-git-topology-registry/quickstart.md)
- Execution log: [tasks.md](/Users/rl/coding/moltinger-006-git-topology-registry/specs/006-git-topology-registry/tasks.md)

Implemented decisions vs proposal:

1. The optional thin wrapper is no longer future work; it exists as `/git-topology`.
2. Hooks stayed validation-only. They never rewrite tracked markdown; they only surface stale state and block `pre-push` when the registry is outdated.
3. `doctor --prune` now writes `.git/topology-registry/registry.draft.md`, and `doctor --prune --write-doc` preserves the last committed registry in `.git/topology-registry/backups/`.

## Proposed Script Contract

- `refresh --write-doc`: reconcile live git topology and render the registry
- `check`: fail when the committed registry is stale
- `status`: show freshness and current topology hash
- `doctor --prune --write-doc`: recover from stale or missed events

## Confidence

- **Confidence**: High
- **Consensus strength**: Strong
