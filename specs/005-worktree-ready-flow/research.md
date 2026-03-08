# Research: Worktree Ready UX

## Decision 1: Keep `bd worktree create` as the creation primitive

- **Decision**: Reuse `bd worktree create` and `bd worktree list` instead of replacing them with raw `git worktree` calls.
- **Rationale**: `bd` already handles project-specific beads integration and aligns with the existing workflow contract in [`worktree.md`](/Users/rl/coding/moltinger/.claude/commands/worktree.md).
- **Alternatives considered**:
  - Raw `git worktree add`: rejected because it would duplicate project-specific setup behavior and bypass beads integration.
  - Full custom wrapper around `git worktree`: rejected because it increases maintenance without adding user value.
- **Library**: No external library required.

## Decision 2: Introduce a single helper script for readiness logic

- **Decision**: Add one helper script, `scripts/worktree-ready.sh`, as the single source of truth for path normalization, readiness classification, doctor output, next-step rendering, and optional handoff.
- **Rationale**: The existing command artifact is strong at routing and intent, but weak at deterministic state evaluation. Centralizing shell behavior makes the workflow testable and consistent.
- **Alternatives considered**:
  - Keep all logic in `worktree.md`: rejected because repeated shell branching becomes brittle and difficult to validate.
  - Split into multiple small scripts: rejected for MVP because the logic is tightly related and would scatter the state model.
- **Library**: No external library required.

## Decision 3: Reuse `git-session-guard` for readiness checks

- **Decision**: Use [`scripts/git-session-guard.sh`](/Users/rl/coding/moltinger/scripts/git-session-guard.sh) as the authoritative signal for branch/worktree drift in doctor/readiness flows.
- **Rationale**: The repository already has a guard contract with `--refresh` and `--status`, so a new readiness system should build on top of that instead of shadowing it.
- **Alternatives considered**:
  - New ad hoc branch/path checks: rejected because they would duplicate logic and risk drift.
  - Git-hook-only validation: rejected because user-facing doctor output also needs explicit reporting, not just hook failures.
- **Library**: No external library required.

## Decision 4: Surface environment approval as a state, not a side effect

- **Decision**: Expose environment readiness as a user-visible status and recommend `direnv allow` when needed, but do not auto-approve by default.
- **Rationale**: The real workflow showed that environment approval is part of the journey. Automating it silently would violate the trust boundary around local environment changes.
- **Alternatives considered**:
  - Auto-run `direnv allow`: rejected for safety and predictability reasons.
  - Ignore `.envrc` entirely: rejected because it causes a misleading "created" result followed by a user-visible failure.
- **Evidence**:
  - `.envrc` exists in the repository and loads external environment values.
  - `direnv status` is available, but non-interactive shells do not reliably indicate whether a target worktree is fully loaded into the active shell session.
- **Library**: No external library required.

## Decision 5: Make existing-branch worktree creation a first-class command flow

- **Decision**: Extend the command contract with an explicit existing-branch path such as `attach` or `start --existing`.
- **Rationale**: The current workflow optimizes for "create new branch from main", while the observed friction came from "I already have the branch, just give me a worktree".
- **Alternatives considered**:
  - Preserve only low-level `bd worktree create`: rejected because it forces users to remember implementation details.
  - Overload the current `start` flow without explicit language: rejected because ambiguity remains high for both the user and the command interpreter.
- **Library**: No external library required.

## Decision 6: Keep terminal/Codex handoff opt-in and platform-aware

- **Decision**: Support terminal/Codex handoff only when explicitly requested, with macOS-first automation and manual fallback everywhere else.
- **Rationale**: Automatic window/tab control is high-value in repeated use, but inherently environment-specific. Opt-in behavior avoids surprising side effects and lets the system degrade cleanly.
- **Alternatives considered**:
  - Always open a terminal session: rejected because many users prefer manual control.
  - Defer handoff entirely to documentation: rejected because explicit opt-in automation is a clear UX win for frequent users.
- **Library**: No external library required; system automation can use native shell/AppleScript where available.
