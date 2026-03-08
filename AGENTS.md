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

Use it when branch/worktree context matters or before cleanup actions.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Speckit Artifact Guard

If work is driven by a Speckit package (`specs/<feature>/`):

1. Before changing runtime code, reconcile spec artifacts:
   - `git status --short specs/<feature>/`
   - ensure `spec.md`, `plan.md`, and `tasks.md` are tracked and present in the branch
2. Update `specs/<feature>/tasks.md` checkboxes as tasks are completed.
3. Before push, verify implementation and spec artifacts are synchronized (no hidden untracked Speckit files).

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

## Codex Operating Model

Repo-specific Codex profiles, worktree naming, and local instruction split are documented in:

```bash
docs/CODEX-OPERATING-MODEL.md
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

- `.claude/skills/*` are imported as Codex skills.
- `.claude/commands/*` and `.claude/agents/*` stay in-repo as reference workflows.
- When both a command and a skill describe the same workflow, prefer the skill.
