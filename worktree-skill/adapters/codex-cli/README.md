# Codex CLI Adapter

## Purpose

Expose the portable core through Codex skill discovery without importing unrelated host project assets.

## Install

1. Install `core/` into the host project.
2. Copy this adapter into the host project.
3. Run:

```bash
./install/register.sh --target /path/to/host-project --adapter codex-cli
```

## Notes

- This adapter should bridge only the worktree-skill assets.
- It should not bulk-import unrelated Claude commands or agents from the host repository.
