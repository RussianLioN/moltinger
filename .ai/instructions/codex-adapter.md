## Codex Adapter

This file is Codex-specific and is merged into `AGENTS.md` by:

```bash
./scripts/sync-agent-instructions.sh --write
```

## Claude Skill Bridge

Claude project skills are stored in:

```bash
.claude/skills/
```

Install or update them into Codex global skills:

```bash
./scripts/sync-claude-skills-to-codex.sh --install
```

Verify the bridge is up to date:

```bash
./scripts/sync-claude-skills-to-codex.sh --check
```

After installing or updating skills, restart Codex to refresh skill discovery.

## Scope Notes

- `.claude/skills/*` are imported as native Codex skills.
- `.claude/commands/*` are migrated into generated bridge skills under `$CODEX_HOME/skills/claude-bridge/commands/*`.
- `.claude/agents/*` are migrated into generated bridge skills under `$CODEX_HOME/skills/claude-bridge/agents/*`.
- When both a command and a skill describe the same workflow, prefer the skill.
