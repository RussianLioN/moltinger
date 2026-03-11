# Contract: Install and Verification Flow

## Purpose

Define the supported install models and the required verification behavior for the standalone repo.

## Supported Install Models

### `copy-only`

- User clones `worktree-skill`
- User copies `core/`
- User optionally copies one adapter and `bridge/speckit/`
- User runs documented verification

### `copy-bootstrap`

- User clones `worktree-skill`
- User runs `install/bootstrap.sh`
- Script copies or materializes the same layout as `copy-only`
- User runs verification

### `copy-register`

- User installs `core/`
- User installs adapter
- User runs adapter-specific register step
- User runs verification

## Verification Requirements

Verification must confirm:

- core files are present
- selected adapter is present and discoverable
- invocation surface exists
- missing optional layers produce actionable feedback
- no mandatory secret, production host, or Moltinger runtime dependency is implied

## Failure Handling

- Missing adapter must produce a clear registration or install action.
- Missing optional bridge layer must not break baseline core usage.
- Conflicting host files must be surfaced before overwrite in guided install flows.
- Verification output must clearly separate `core installed`, `adapter installed`, and `bridge installed`.
