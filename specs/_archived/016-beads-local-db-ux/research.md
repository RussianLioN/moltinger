# Research: UX-Safe Beads Local Ownership

## Decision 1: Use explicit `bd --db` dispatch as the safe execution primitive

- **Decision**: Route safe local execution through explicit `bd --db <worktree-local-db>` instead of relying on implicit auto-discovery or on `BEADS_DB` as the only runtime mechanism.
- **Rationale**: In the current worktree, `bd info` resolves the canonical root database, while `bd --db .beads/beads.db info` correctly resolves the local worktree database. This proves the local target is valid and the unsafe part is discovery, not the local DB itself.
- **Alternatives considered**:
  - Keep `BEADS_DB` as the only mechanism: rejected because `direnv` is not guaranteed in Codex/App sessions.
  - Wait for upstream `bd` behavior changes: rejected because the repo needs a local fail-closed guard now.
- **Library**: No external library required.

## Decision 2: Treat local `.beads/` foundation as the ownership contract

- **Decision**: Use the current worktree’s `.beads/config.yaml`, `.beads/issues.jsonl`, `.beads/beads.db`, and the absence of legacy redirect residue as the source of truth for local ownership.
- **Rationale**: These files already represent real worktree-local state. Reusing them avoids inventing another ownership database and keeps the contract inspectable, repo-local, and aligned with actual Beads storage.
- **Alternatives considered**:
  - Add a second metadata file just to point at the DB: rejected because it would duplicate information already present in `.beads/`.
  - Keep ownership implicit and infer it from git worktree discovery alone: rejected because that is exactly what currently fails.
- **Library**: No external library required.

## Decision 3: Replace wrapper choice with a plain-`bd` shim plus bootstrap

- **Decision**: Preserve plain `bd` as the user-facing command by introducing a repo-local shim under the same command name and ensuring managed sessions place it first on `PATH`.
- **Rationale**: The UX problem is not that a safe local command is impossible; it is that the user must remember a second command name. A repo-local shim removes that memory burden while keeping the safety logic explicit and testable.
- **Alternatives considered**:
  - Keep `scripts/bd-local.sh` as the normal path: rejected because it preserves the wrapper-choice burden.
  - Document “always type `bd --db .beads/beads.db`”: rejected because it is even worse UX and easy to get wrong.
- **Library**: No external library required.

## Decision 4: Deliver bootstrap through both `.envrc` and managed launchers

- **Decision**: Use `.envrc` as a convenience path when available, but also update managed launch/handoff surfaces so plain `bd` remains safe even when `direnv` is absent or not approved.
- **Rationale**: The problem statement explicitly says `direnv` is not guaranteed in Codex/App sessions. Therefore, bootstrap must be multi-channel rather than env-only.
- **Alternatives considered**:
  - Depend only on `.envrc`: rejected because it leaves the original failure mode intact.
  - Ignore `.envrc` entirely: rejected because it is still a useful fast path in normal developer shells.
- **Library**: No external library required.

## Decision 5: Keep compatibility migration separate from steady-state ownership

- **Decision**: Design a dedicated compatibility/localization path for already-open worktrees instead of overloading steady-state plain-`bd` dispatch with hidden migration behavior.
- **Rationale**: Users need one predictable daily command path and one explicit repair path. Mixing them increases ambiguity and makes failure modes harder to explain.
- **Alternatives considered**:
  - Auto-repair every unsafe state opportunistically inside plain `bd`: rejected because it risks partial mutation and obscures what changed.
  - Leave migration fully manual: rejected because the task explicitly requires low-pain migration for existing worktrees.
- **Library**: No external library required.

## Decision 6: Never revive shared redirect ownership

- **Decision**: Legacy redirected/shared ownership is compatibility-only input and must never be reintroduced as a new steady-state output.
- **Rationale**: The task explicitly forbids returning to shared redirect leakage. New behavior must converge to local ownership or a blocked state, not another redirect layer.
- **Alternatives considered**:
  - Reintroduce redirect metadata with stricter docs: rejected because it reopens the same class of safety problem.
  - Allow redirect for read-only flows: rejected for MVP because it blurs the primary ownership model.
- **Library**: No external library required.

## Decision 7: Keep residual root cleanup as a separate operational stream

- **Decision**: Ownership-safe UX fix may report residual root cleanup, but it must not silently perform it and must not require root repair to validate dedicated-worktree safety.
- **Rationale**: The task forbids manual root `main` repair and requires clear separation between migration and cleanup. Treating cleanup as separate reduces risk and keeps the feature bounded.
- **Alternatives considered**:
  - Fold root cleanup into migration: rejected because it couples unrelated risk domains.
  - Ignore root residue entirely: rejected because users still need clear guidance when it is observed.
- **Library**: No external library required.

## Decision 8: Preserve deliberate troubleshooting fallbacks as non-default tools

- **Decision**: Explicit manual `bd --db ...` and explicit read-only `--no-db` troubleshooting remain allowed for diagnostics, but they are not the normal repo-local UX and must not become silent fallback behavior.
- **Rationale**: Existing workflows already rely on explicit troubleshooting escapes. The safe fix should preserve those tools while removing accidental mutating fallback.
- **Alternatives considered**:
  - Ban all explicit fallbacks: rejected because operators still need recovery tools.
  - Allow the system to pick explicit fallbacks automatically: rejected because that recreates silent behavior.
- **Library**: No external library required.
