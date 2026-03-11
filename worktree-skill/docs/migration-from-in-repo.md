# Migration From In-Repo Assets

## Source Pattern

The current in-repo layout mixes:

- portable worktree prompts
- topology helpers
- IDE bridge logic
- host-project governance and operational rules

## Migration Goal

Move only the reusable worktree assets into `worktree-skill` and leave the host-specific runtime and governance in the host project.

## Recommended Migration Flow

1. Identify which current files are portable core candidates.
2. Replace host-specific paths and defaults with config.
3. Install the standalone `core/` into a staging branch.
4. Add one adapter at a time.
5. Run `install/verify.sh`.
6. Keep host-project governance files in the host repo.

## Do Not Migrate

- deploy workflows
- secrets docs
- product runtime configs
- host-only session automation
- historical branch or worktree snapshots
