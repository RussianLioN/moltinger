# Beads — Quick Reference

> **Attribution**: [Beads](https://github.com/steveyegge/beads) methodology by [Steve Yegge](https://github.com/steveyegge)

> **Moltinger repo note**: for repo-local Beads commands, use `./scripts/bd-local.sh` so the current worktree does not fall back to the canonical root tracker.

---

## SESSION CLOSE PROTOCOL (MANDATORY!)

**NEVER say "done" without completing these steps:**

```bash
git status              # 1. What changed?
git add <files>         # 2. Stage code
./scripts/bd-local.sh sync  # 3. Sync beads
git commit -m "... (PREFIX-xxx)"  # 4. Commit with issue ID
./scripts/bd-local.sh sync  # 5. Sync new changes
git push                # 6. Push to remote
```

**Work is NOT done until pushed!**

---

## When to Use What

| Scenario | Tool | Command |
|----------|------|---------|
| Big feature (>1 day) | Spec-kit → Beads | `/speckit.specify` → `/speckit.tobeads` |
| Small feature (<1 day) | Beads | `./scripts/bd-local.sh create -t feature` |
| Bug | Beads | `./scripts/bd-local.sh create -t bug` |
| Tech debt | Beads | `./scripts/bd-local.sh create -t chore` |
| Research/spike | Beads formula | `bd mol wisp exploration` |
| Hotfix (urgent!) | Beads formula | `bd mol wisp hotfix` |
| Health check | Workflow | `bd mol wisp healthcheck` |
| Release | Workflow | `bd mol wisp release` |

---

## Work Session

```bash
# === START ===
./scripts/bd-local.sh prime                    # Restore context
./scripts/bd-local.sh ready                    # What's available?

# === WORK ===
./scripts/bd-local.sh update ID --status in_progress   # Take task
# ... do work ...
./scripts/bd-local.sh close ID --reason "Description"  # Complete task
/push patch                         # Commit

# === END (MANDATORY) ===
./scripts/bd-local.sh sync                     # Sync before exit
```

---

## Creating Tasks

### Basic Command
```bash
./scripts/bd-local.sh create "Title" -t type -p priority -d "description"
```

### Types (-t)
| Type | When |
|------|------|
| `feature` | New functionality |
| `bug` | Bug fix |
| `chore` | Tech debt, refactoring |
| `docs` | Documentation |
| `test` | Tests |
| `epic` | Group of related tasks |

### Priorities (-p)
| P | Meaning |
|---|---------|
| 0 | Critical — blocks release |
| 1 | Critical |
| 2 | High |
| 3 | Medium (default) |
| 4 | Low / backlog |

### Examples
```bash
# Simple task
./scripts/bd-local.sh create "Add logout button" -t feature -p 3

# With description
./scripts/bd-local.sh create "DEBT-001: Refactoring" -t chore -p 2 -d "Details..."

# Bug with source link
./scripts/bd-local.sh create "Button not working" -t bug -p 1 --deps discovered-from:PREFIX-abc
```

---

## Dependencies

```bash
# On creation
./scripts/bd-local.sh create "Task" -t feature --deps TYPE:ID

# Add to existing
bd dep add ISSUE DEPENDS_ON
```

| Dependency Type | Meaning |
|-----------------|---------|
| `blocks:X` | This task blocks X |
| `blocked-by:X` | This task is blocked by X |
| `discovered-from:X` | Found while working on X |
| `parent:X` | Child task of epic X |

---

## Epics and Hierarchy

```bash
# Create epic
./scripts/bd-local.sh create "User Authentication" -t epic -p 2

# Add child tasks
./scripts/bd-local.sh create "Login form" -t feature --deps parent:PREFIX-epic-id
./scripts/bd-local.sh create "JWT tokens" -t feature --deps parent:PREFIX-epic-id

# View structure
./scripts/bd-local.sh show PREFIX-epic-id --tree
```

---

## Formulas (Workflows)

### Available Formulas
```bash
bd formula list
```

| Formula | Purpose |
|---------|---------|
| `bigfeature` | Spec-kit → Beads for big features |
| `bugfix` | Standard bug fix process |
| `hotfix` | Emergency fix |
| `techdebt` | Technical debt work |
| `healthcheck` | Codebase health audit |
| `codereview` | Code review with issue creation |
| `release` | Version release process |
| `exploration` | Research/spike |

### Running
```bash
# Ephemeral (wisp)
bd mol wisp exploration --vars "question=How to do X?"

# Persistent (pour)
bd mol pour bigfeature --vars "feature_name=auth"
```

### Completing wisp
```bash
bd mol squash WISP_ID  # Save result
bd mol burn WISP_ID    # Discard
```

---

## Exclusive Lock (multi-session)

```bash
# Terminal 1: acquired lock
./scripts/bd-local.sh update PREFIX-abc --status in_progress

# Terminal 2: find unlocked
./scripts/bd-local.sh list --unlocked
```

---

## Emergent Work

```bash
# Found bug while working
./scripts/bd-local.sh create "Found bug: ..." -t bug --deps discovered-from:PREFIX-current

# Realized need another task
./scripts/bd-local.sh create "Also need to..." -t feature --deps blocks:PREFIX-current
```

---

## Search and Filter

```bash
./scripts/bd-local.sh ready                    # Ready to work
./scripts/bd-local.sh list                     # All open
./scripts/bd-local.sh list --all               # Including closed
./scripts/bd-local.sh list -t bug              # Only bugs
./scripts/bd-local.sh list -p 1                # Only P1
./scripts/bd-local.sh show ID                  # Task details
./scripts/bd-local.sh show ID --tree           # With hierarchy
```

---

## Task Management

```bash
# Change status
./scripts/bd-local.sh update ID --status in_progress
./scripts/bd-local.sh update ID --status blocked
./scripts/bd-local.sh update ID --status open

# Change priority
./scripts/bd-local.sh update ID --priority 1

# Add label
./scripts/bd-local.sh update ID --add-label security

# Close
./scripts/bd-local.sh close ID --reason "Done"
./scripts/bd-local.sh close ID1 ID2 ID3 --reason "Batch done"
```

---

## Diagnostics

```bash
./scripts/bd-local.sh doctor     # Health check
./scripts/bd-local.sh info       # Project status
./scripts/bd-local.sh prime      # Workflow context
```

---

## Cheat Sheet

```
┌──────────────────────────────────────────────────┐
│ START     ./scripts/bd-local.sh prime / ready    │
│ TAKE      ./scripts/bd-local.sh update ID ...    │
│ CREATE    ./scripts/bd-local.sh create "..."     │
│ CLOSE     ./scripts/bd-local.sh close ID ...     │
├──────────────────────────────────────────────────┤
│ SESSION END (ALL 6 STEPS!)                       │
│   1. git status                                  │
│   2. git add <files>                             │
│   3. ./scripts/bd-local.sh sync                  │
│   4. git commit -m "... (PREFIX-xxx)"            │
│   5. ./scripts/bd-local.sh sync                  │
│   6. git push                                    │
├──────────────────────────────────────────────────┤
│ WORKFLOWS bd formula list                        │
│           bd mol wisp NAME --vars "k=v"          │
│           bd mol squash/burn WISP_ID             │
└──────────────────────────────────────────────────┘
```

---

## Links

- [Beads GitHub](https://github.com/steveyegge/beads)
- [CLI Reference](https://github.com/steveyegge/beads/blob/main/docs/CLI_REFERENCE.md)
- [Molecules Guide](https://github.com/steveyegge/beads/blob/main/docs/MOLECULES.md)

---

*Beads methodology by Steve Yegge. Adapted for Claude Code Orchestrator Kit.*
