## Codex Adapter

This file is Codex-specific and is merged into `AGENTS.md` by:

```bash
./scripts/sync-agent-instructions.sh --write
```

## Codex Operating Model

Repo-specific Codex profiles, worktree naming, and local instruction split are documented in:

```bash
docs/CODEX-OPERATING-MODEL.md
```

When working inside scoped directories such as `config/`, `.github/`, `scripts/`, `specs/`, `tests/`, `docs/`, `.ai/`, `.claude/`, or `knowledge/`, follow the nearest local `AGENTS.md` in addition to the root file.

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
