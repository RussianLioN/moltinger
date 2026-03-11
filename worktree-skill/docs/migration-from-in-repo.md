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
3. Materialize a standalone `worktree-skill` repository and treat it as the future source of truth.
4. Install the standalone `core/` into a staging branch.
5. Add one adapter at a time.
6. Run `install/verify.sh`.
7. Keep host-project governance files in the host repo and downgrade any vendored copy to reference-only status.

## Do Not Migrate

- deploy workflows
- secrets docs
- product runtime configs
- host-only session automation
- historical branch or worktree snapshots
