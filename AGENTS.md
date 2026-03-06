# Agent Instructions

> GENERATED FILE. DO NOT EDIT DIRECTLY.
> Source: `.ai/instructions/shared-core.md` + `.ai/instructions/codex-adapter.md`
> Regenerate with: `./scripts/sync-agent-instructions.sh --write`

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Auto-RCA (Mandatory)

If the agent makes a mistake, RCA must start automatically before normal work continues.

Triggers:
- Any command/tool error (`exit code != 0`)
- User reports misunderstanding/wrong action
- Branch/worktree/context drift

Protocol:
1. Stop implementation immediately
2. Run short 5-whys self-reflection
3. Create/update RCA artifact in `docs/rca/`
4. Update lessons index
5. Apply preventive instruction update
6. Resume only after RCA is completed

Rule reference: `docs/rules/auto-rca-self-reflection.md`
Runtime wrapper: `scripts/auto-rca-wrapper.sh`

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
## Speckit Artifact Guard

If work is driven by a Speckit package (`specs/<feature>/`):

1. Before changing runtime code, reconcile spec artifacts:
   - `git status --short specs/<feature>/`
   - ensure `spec.md`, `plan.md`, `tasks.md` are tracked and present in branch
2. Update `specs/<feature>/tasks.md` checkboxes as tasks are completed.
3. Before push, verify implementation and spec artifacts are synchronized (no hidden untracked Speckit files).

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
