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

For Moltis skill/agent authoring or migrations from Claude Code, Codex, or OpenCode into Moltis-native capabilities, read:

```bash
docs/moltis-skill-agent-authoring.md
```

When working inside scoped directories such as `config/`, `.github/`, `scripts/`, `specs/`, `tests/`, `docs/`, `.ai/`, `.claude/`, `knowledge/`, `.beads/`, or `.specify/`, follow the nearest local `AGENTS.md` in addition to the root file.

## Codex Governance Check

If you change Codex operating-model docs, source instructions, local `AGENTS.md` files, the skill bridge, or Codex launcher/check scripts, run:

```bash
make codex-check
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
- In Codex CLI, bridged Claude commands are usually invoked via `command-*` skills, not native slash commands.
- Example: use `command-worktree` and `command-session-summary` in Codex; do not assume `/worktree` or `/session-summary` are registered as CLI slash commands.
- If the user refers to the "worktree skill" in plain language, map that intent to `command-worktree`.
- If a UAT worktree unexpectedly carries local changes to `docs/GIT-TOPOLOGY-REGISTRY.md`, inspect them as drift rather than treating them as authoritative branch-local evidence; see `docs/rules/uat-registry-snapshot-preservation.md`.
