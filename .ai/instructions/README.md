# Shared AI Instructions

This folder stores reusable instruction layers for both Claude Code and Codex.

## Files

- `shared-core.md` - common policy used by both agents
- `codex-adapter.md` - Codex-only additions merged into `AGENTS.md`

## Update Workflow

1. Edit one of the source files in this folder.
2. Regenerate `AGENTS.md`:

   ```bash
   ./scripts/sync-agent-instructions.sh --write
   ```

3. Verify generation:

   ```bash
   ./scripts/sync-agent-instructions.sh --check
   ```

`CLAUDE.md` imports `shared-core.md` directly via `@.ai/instructions/shared-core.md`.
