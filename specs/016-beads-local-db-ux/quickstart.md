# Quickstart: UX-Safe Beads Local Ownership

## Scenario 1: Dedicated worktree, plain `bd`, direnv available

1. Enter a dedicated worktree where `.envrc` was approved.
2. Run `bd info`.
3. Expect:
   - the active `bd` entrypoint is the repo-local safe path
   - the resolved database is the current worktree’s `.beads/beads.db`
   - no wrapper choice is required

## Scenario 2: Dedicated worktree, plain `bd`, direnv unavailable

1. Start a session through the managed worktree/Codex handoff without relying on `direnv`.
2. Run `bd ready`.
3. Expect:
   - plain `bd` still resolves to the safe repo-local path
   - local worktree ownership is used
   - no `bd-local` command is required

## Scenario 3: Unbootstrapped session blocks before mutation

1. Enter the dedicated worktree in a session where plain `bd` still points to the unsafe system path.
2. Run a mutating command such as `bd update <ID> --status in_progress`.
3. Expect:
   - the command stops before mutation
   - the error explains that the session is not safely bootstrapped for local ownership
   - the recovery hint points to the managed bootstrap path instead of a wrapper choice

## Scenario 4: Legacy redirected worktree migrates in place

1. Prepare a worktree with legacy redirect residue but otherwise recoverable local state.
2. Run the managed compatibility/localization flow.
3. Expect:
   - the system classifies the worktree as migratable legacy state
   - localization happens in place without changing branch or worktree identity
   - plain `bd` works safely afterward

## Scenario 5: Damaged legacy worktree fails closed

1. Prepare a worktree with missing or conflicting `.beads` foundation files.
2. Run the managed compatibility/localization flow.
3. Expect:
   - the system blocks the workflow with a clear explanation
   - no silent fallback to root occurs
   - the user receives one exact repair path

## Scenario 6: Residual root cleanup is reported but not mixed in

1. Simulate a dedicated worktree that is locally safe while the canonical root still has cleanup residue.
2. Run plain `bd` from the dedicated worktree.
3. Expect:
   - local ownership remains valid and usable
   - any root residue is reported only as a separate notice or follow-up
   - the workflow does not attempt manual root repair

## Scenario 7: Docs and guidance use one default command path

1. Review the repo’s high-traffic Beads quickstart and workflow guidance.
2. Expect:
   - ordinary repo-local usage is documented as plain `bd`
   - the docs do not require a `bd` vs `bd-local` choice
   - the docs do not route users back to raw `bd worktree create`

## Scenario 8: Explicit troubleshooting stays explicit

1. Run deliberate diagnostic flows such as `bd --db .beads/beads.db info` or an explicit read-only fallback.
2. Expect:
   - these flows still work as operator tools
   - they are clearly documented as troubleshooting paths
   - they are not silently chosen by normal mutating plain `bd` usage
