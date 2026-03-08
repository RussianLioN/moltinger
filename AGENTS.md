# Agent Instructions

> GENERATED FILE. DO NOT EDIT DIRECTLY.
> Source: `.ai/instructions/shared-core.md` + `.ai/instructions/codex-adapter.md`
> Regenerate with: `./scripts/sync-agent-instructions.sh --write`

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Git Topology Reference

Current branch/worktree registry lives in:

```bash
docs/GIT-TOPOLOGY-REGISTRY.md
```

It is generated from live git topology plus reviewed intent sidecar.

```bash
scripts/git-topology-registry.sh check
scripts/git-topology-registry.sh refresh --write-doc
scripts/git-topology-registry.sh status
```

Use `check` when branch/worktree context matters or before cleanup actions. Use `refresh --write-doc` after topology mutations.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

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
