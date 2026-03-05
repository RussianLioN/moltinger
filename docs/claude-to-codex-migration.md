# Claude Code -> Codex Migration

This repository uses a shared core plus adapters to keep Claude and Codex aligned without breaking existing Claude setup.

## Layout

- Shared core: `.ai/instructions/shared-core.md`
- Codex adapter: `.ai/instructions/codex-adapter.md`
- Generated Codex file: `AGENTS.md`
- Claude file: `CLAUDE.md` (imports shared core via `@.ai/instructions/shared-core.md`)

## Commands

Regenerate `AGENTS.md` after changing shared/adapter files:

```bash
./scripts/sync-agent-instructions.sh --write
```

Verify `AGENTS.md` is up to date:

```bash
./scripts/sync-agent-instructions.sh --check
```

Sync Claude project skills into Codex global skills:

```bash
./scripts/sync-claude-skills-to-codex.sh --install
```

Verify skill sync:

```bash
./scripts/sync-claude-skills-to-codex.sh --check
```

After skill sync, restart Codex so it reloads the available skills list.

## Scope of Imported Assets

- Imported automatically: `.claude/skills/*`
- Kept as in-repo references: `.claude/commands/*`, `.claude/agents/*`

If you want command-level parity in Codex, migrate legacy command files into skill directories over time.
