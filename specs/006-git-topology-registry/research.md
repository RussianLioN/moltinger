# Research: Auto-Maintained Git Topology Registry

## Decision 1: Use a Script-First Hybrid

- **Decision**: Implement the feature around one deterministic shell script as the single writer of the registry.
- **Rationale**: The problem is primarily deterministic state discovery and rendering, not open-ended reasoning. A script is easier to audit, test, and wire into repo workflows than an agent-first maintainer.
- **Alternatives considered**:
  - Dedicated long-running agent: rejected because it is too opaque and not a stable source of truth.
  - Hook-written markdown only: rejected because hooks are too noisy and brittle as doc mutators.

## Decision 2: Split Generated Facts From Reviewed Intent

- **Decision**: Keep the committed registry generated from live git state, and store manual branch/worktree intent in a separate committed sidecar file.
- **Rationale**: Git can discover topology facts but not operational meaning such as `protected`, `historical`, or `extract-only`. A sidecar preserves human/LLM-reviewed intent without mixing it into parser output.
- **Alternatives considered**:
  - Inline freeform notes in the generated registry: rejected because regeneration would overwrite or leak manual edits.
  - Local-only sidecar: rejected because intent must be shared across sessions and collaborators.

## Decision 3: Sanitize the Committed Registry

- **Decision**: Do not commit absolute workstation paths or volatile per-commit fields such as live `HEAD` for every worktree row.
- **Rationale**: Absolute paths leak unnecessary local details and `HEAD` changes create churn unrelated to topology.
- **Alternatives considered**:
  - Raw git dump: rejected due to privacy and noise.
  - Commit timestamps/SHAs as freshness markers: rejected because topology freshness should be tied to normalized topology, not every commit.

## Decision 4: Use Full Reconcile as the Correctness Path

- **Decision**: The system should reconcile against live git state on refresh/check/doctor rather than trusting cached event history.
- **Rationale**: Users can always run raw git commands outside managed workflows. The only trustworthy recovery path is re-reading current git state.
- **Alternatives considered**:
  - Event-only journal as source of truth: rejected because hooks and workflow wrappers can miss manual topology changes.
  - CI-only validation: rejected because CI cannot see local developer worktrees.

## Decision 5: Use Managed Workflow Integration Points

- **Decision**: Integrate refresh/check into `/worktree` and `/session-summary`, and keep hooks as validation/backstop only.
- **Rationale**: These are the existing lifecycle points where topology changes and session handoff already happen. They provide high-value coverage without mutating docs during every commit.
- **Alternatives considered**:
  - Refresh on every pre-commit/pre-push: rejected due to noisy diffs and workflow friction.
  - Session-start unconditional refresh: rejected due to needless churn when topology is unchanged.

## Decision 6: Use Repo-Shared Lock/State Under `git-common-dir`

- **Decision**: Store registry lock and health state under `$(git rev-parse --git-common-dir)`.
- **Rationale**: Git topology is shared across worktrees, so locking and state must also be repo-shared rather than tied to one worktree.
- **Alternatives considered**:
  - Per-worktree lock/state: rejected because concurrent worktrees would race and drift.
  - Global machine-wide state: rejected because the unit of truth is the repository, not the machine.
