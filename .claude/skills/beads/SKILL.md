---
description: Beads issue tracking workflow for claiming, updating, and closing tasks with the bd CLI.
argument-hint: ""
---

# Beads Issue Tracking Skill

> **Attribution**: [Beads](https://github.com/steveyegge/beads) by [Steve Yegge](https://github.com/steveyegge)

## Description

Beads is a git-backed, AI-native issue tracking system. This skill helps AI agents work with Beads effectively.

Repo note for Moltinger: use `./scripts/bd-local.sh` for repo-local tracker commands so the current worktree keeps ownership even when `direnv` is not active.

## When to Use

- Starting a new work session (`./scripts/bd-local.sh prime` → `./scripts/bd-local.sh ready`)
- Creating, updating, or closing issues
- Managing task dependencies
- Running workflow formulas
- Coordinating multi-session work

## Quick Reference

### Session Workflow

```bash
# START
./scripts/bd-local.sh prime                    # Inject context
./scripts/bd-local.sh ready                    # Find available work

# WORK
./scripts/bd-local.sh update ID --status in_progress  # Take task
# ... implement ...
./scripts/bd-local.sh close ID --reason "Done"        # Complete task
/push patch                        # Commit

# END (MANDATORY!)
./scripts/bd-local.sh sync
git push
```

### Issue Creation

```bash
# Basic
./scripts/bd-local.sh create "Title" -t type -p priority

# With files (auto-labels)
./scripts/bd-local.sh create "Fix button" --files src/components/Button.tsx

# Emergent work
./scripts/bd-local.sh create "Found bug" -t bug --deps discovered-from:current-id
```

### Types & Priorities

| Type | When |
|------|------|
| feature | New functionality |
| bug | Bug fix |
| chore | Tech debt, config |
| docs | Documentation |
| test | Tests |
| epic | Group of tasks |

| Priority | Meaning |
|----------|---------|
| 0 | Critical (blocks release) |
| 1 | Critical |
| 2 | High |
| 3 | Medium (default) |
| 4 | Low / backlog |

### Formulas (Workflows)

```bash
bd formula list                                    # List all
bd mol wisp exploration --vars "question=How?"    # Ephemeral
bd mol pour bigfeature --vars "feature_name=auth" # Persistent
bd mol squash WISP_ID                             # Save result
bd mol burn WISP_ID                               # Discard
```

## Resources

See `resources/` for detailed guides:
- COMMANDS_QUICKREF.md - Command cheat sheet
- DECISION_MATRIX.md - When to use what
- WORKFLOWS.md - Common workflows
- SPECKIT_BRIDGE.md - Integration with Spec-kit

## Integration with Spec-kit

For large features (>1 day):
1. `/speckit.specify` → requirements
2. `/speckit.plan` → design
3. `/speckit.tasks` → task breakdown
4. `/speckit.tobeads` → import to Beads
5. `./scripts/bd-local.sh ready` → work with Beads

## Links

- [Beads GitHub](https://github.com/steveyegge/beads)
- [CLI Reference](https://github.com/steveyegge/beads/blob/main/docs/CLI_REFERENCE.md)
