# Beads Common Workflows

Repo note for Moltinger: use `./scripts/bd-local.sh` for repo-local tracker commands so each worktree keeps its own Beads ownership.

## Daily Session

```bash
# === START ===
./scripts/bd-local.sh prime                    # Restore context
./scripts/bd-local.sh ready                    # What's available?

# === WORK ===
./scripts/bd-local.sh update PREFIX-xxx --status in_progress
# ... implement ...
./scripts/bd-local.sh close PREFIX-xxx --reason "Implemented feature"
/push patch

# === END (MANDATORY!) ===
git status
git add <files>
./scripts/bd-local.sh sync
git commit -m "feat: description (PREFIX-xxx)"
./scripts/bd-local.sh sync
git push
```

## Emergent Work

Found something while working?

```bash
# 1. Create linked issue
./scripts/bd-local.sh create "Found: memory leak in Parser" -t bug --deps discovered-from:PREFIX-current

# 2. Continue current work or switch
./scripts/bd-local.sh ready  # Will show new issue when available
```

## Big Feature (>1 day)

```bash
# 1. Specification
/speckit.specify

# 2. Design
/speckit.plan

# 3. Task breakdown
/speckit.tasks

# 4. Import to Beads
/speckit.tobeads

# 5. Work through tasks
./scripts/bd-local.sh ready
./scripts/bd-local.sh update PREFIX-xxx --status in_progress
# ... implement ...
./scripts/bd-local.sh close PREFIX-xxx --reason "Done"
/push patch
# Repeat until epic is complete
```

## Code Review

```bash
# Start review patrol
bd patrol run code-review --vars "scope=src/components,topic=refactor"

# Or manually
bd mol wisp codereview --vars "scope=src/,topic=audit"
```

## Health Check

```bash
# Full check
bd patrol run health-check

# Or with scope
bd mol wisp healthcheck --vars "scope=packages/web"
```

## Hotfix (Emergency)

```bash
# Start hotfix workflow
bd mol wisp hotfix --vars "issue_description=Login failing,affected_area=auth"

# This guides through:
# 1. Identify issue
# 2. Minimal fix
# 3. Test
# 4. Deploy
# 5. Follow-up tasks
```

## Research / Exploration

```bash
# Start exploration
bd mol wisp exploration --vars "question=Should we use Redis for caching?"

# After research, decide:
bd mol squash WISP_ID  # Save findings
# OR
bd mol burn WISP_ID    # Discard if dead end
```

## Multi-Terminal Work

```bash
# Terminal 1: Working on PREFIX-abc
./scripts/bd-local.sh update PREFIX-abc --status in_progress  # Acquires lock

# Terminal 2: Find other work
./scripts/bd-local.sh list --unlocked
./scripts/bd-local.sh update PREFIX-def --status in_progress  # Different issue

# Both can work in parallel without conflicts
```

## Release

```bash
# Patch release
bd mol wisp release --vars "bump_type=patch"

# Minor release
bd mol wisp release --vars "bump_type=minor,message=New feature X"

# Major release
bd mol wisp release --vars "bump_type=major,message=Breaking change Y"
```
