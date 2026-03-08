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

- `.claude/skills/*` are imported as Codex skills.
- `.claude/commands/*` and `.claude/agents/*` stay in-repo as reference workflows.
- When both a command and a skill describe the same workflow, prefer the skill.
- In Codex CLI, bridged Claude commands are usually invoked via `command-*` skills, not native slash commands.
- Example: use `command-worktree` and `command-session-summary` in Codex; do not assume `/worktree` or `/session-summary` are registered as CLI slash commands.
- If the user refers to the "worktree skill" in plain language, map that intent to `command-worktree`.
