# Claude Code Adapter

## Purpose

Expose the portable core through Claude-style command and skill surfaces.

## Install

1. Install `core/` into the host project.
2. Copy this adapter into host project locations compatible with Claude Code.
3. Verify that `/worktree`, `/session-summary`, and `/git-topology` map to the portable core assets.

## Notes

- This adapter should not add host-only governance rules.
- If the host project already has `.claude/` assets, install into a staging branch first.
