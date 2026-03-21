# Research: Safe Batch Recovery of Leaked Beads Issues

## Decision 1: Build a Thin Batch Orchestrator Around Existing Helpers

- **Decision**: Implement one batch owner script that delegates per-worktree localization to `scripts/beads-worktree-localize.sh` and per-issue recovery to `scripts/beads-recover-issue.sh`.
- **Rationale**: The repository already has safe single-purpose primitives for the dangerous parts. Reusing them keeps the new logic narrow and easier to test.
- **Alternatives considered**:
  - Rewrite recovery and localization in one new script: rejected because it duplicates already verified safety checks.
  - Use `bd` batch commands directly: rejected because current repo state still has prefix-mismatch behavior that must remain fail-closed.

## Decision 2: Use JSON Artifacts as the Contract Between Audit and Apply

- **Decision**: Audit writes a deterministic JSON plan, and apply consumes only that plan.
- **Rationale**: A plan artifact creates a review boundary, prevents re-deriving ownership during apply, and makes reruns and testing deterministic.
- **Alternatives considered**:
  - Parse freeform stdout: rejected because it is brittle and not machine-safe.
  - Derive ownership again during apply: rejected because live topology may drift between runs.

## Decision 3: Require Explicit Ownership Overrides for Ambiguous Cases

- **Decision**: Add a committed ownership override file for cases where branch naming or live topology cannot prove a safe owner.
- **Rationale**: The repo already contains cases like `molt-2` where the issue ID does not map directly to a branch name. Safe automation needs a durable override source.
- **Alternatives considered**:
  - Guess owner by fuzzy branch matching: rejected because it can write tracker state into the wrong worktree.
  - Require manual per-run CLI flags: rejected because it is not durable and increases operator toil.

## Decision 4: Keep Canonical Root Cleanup Out of the Same Command

- **Decision**: The batch command may audit and recover, but it must never delete or rewrite canonical root tracker records in the same run.
- **Rationale**: Recovery and cleanup are different risk classes. Combining them makes rollback, review, and blame isolation much harder.
- **Alternatives considered**:
  - One-shot recover-and-clean: rejected because a partial failure could strand state without clear evidence.
  - Immediate root deduplication after each recovered issue: rejected because unresolved blockers would still exist.

## Decision 5: Preserve JSONL-Level Recovery When DB Import Is Unsafe

- **Decision**: When local database import is blocked by prefix mismatch or similar safety constraints, preserve JSONL recovery and journal that reduced safety level explicitly.
- **Rationale**: The current repo already demonstrates that DB import can be unsafe while JSONL ownership recovery remains useful and reviewable.
- **Alternatives considered**:
  - Fail the whole batch on first DB mismatch: rejected because it blocks safe ownership repair that does not require DB writes.
  - Force `--rename-on-import`: rejected because it changes tracker semantics and is outside this feature's scope.

## Decision 6: Use Repo-Tracked Docs for Overrides, Run-Local Paths for Artifacts

- **Decision**: Store ownership overrides in tracked docs, but store generated plan/journal artifacts in an explicit output path chosen for each run.
- **Rationale**: Overrides are durable shared knowledge; plan/journal files are run evidence and may be numerous or temporary.
- **Alternatives considered**:
  - Track every journal in git: rejected because it would create high churn.
  - Keep ownership overrides local-only: rejected because the mapping must survive sessions and be visible to all worktrees.
