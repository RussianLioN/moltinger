# Beads Commands Quick Reference

In this repository, these commands assume the repo-local plain `bd` shim is active through `.envrc` or the managed worktree/Codex bootstrap path.

If `.beads/pilot-mode.json` exists in the current worktree, use `./scripts/beads-dolt-pilot.sh review` for pilot review instead of the ordinary non-migration review path.
If `.beads/cutover-mode.json` exists in the current worktree, use `./scripts/beads-dolt-rollout.sh verify --worktree .` for cutover verification instead of the ordinary non-migration review path.

## View Issues

```bash
bd ready                    # Available work (no blockers)
bd list                     # All open issues
bd list --all               # Include closed
bd list -t bug              # Filter by type
bd list -p 1                # Filter by priority
bd list --status in_progress # Filter by status
bd list --unlocked          # Multi-terminal safe
bd blocked                  # Show blocked issues

bd show ID                  # Issue details
bd show ID --tree           # With hierarchy
```

## Create Issues

```bash
bd create "Title" -t type -p priority
bd create "Title" -t type -p priority -d "Description"
bd create "Title" --files path/to/file.tsx    # Auto-labels

# With dependencies
bd create "Title" --deps blocks:OTHER_ID
bd create "Title" --deps blocked-by:OTHER_ID
bd create "Title" --deps discovered-from:OTHER_ID
bd create "Title" --deps parent:EPIC_ID
```

## Update Issues

```bash
bd update ID --status in_progress
bd update ID --status blocked
bd update ID --status open
bd update ID --priority 1
bd update ID --add-label security
```

## Close Issues

```bash
bd close ID --reason "Description"
bd close ID1 ID2 ID3 --reason "Batch done"
bd close ID --reason "Won't fix" --wontfix
```

## Dependencies

```bash
bd dep add CHILD PARENT     # CHILD depends on PARENT
bd dep remove CHILD PARENT
```

## Labels

```bash
bd label add ID label-name
bd label remove ID label-name
```

## Review & Diagnostics

```bash
bd status                   # Review current Beads state
bd bootstrap                # Safe setup / repair for a clone or broken local DB
bd info                     # Project status
bd doctor                   # Health check
bd dolt push                # Publish Dolt history when a remote is configured
bd prime                    # Context injection
bd prime --full             # Full context
```

## Migration Review Surfaces

```bash
./scripts/beads-dolt-migration-inventory.sh              # Readiness and blocker inventory
./scripts/beads-dolt-pilot.sh status                     # Pilot gate and local marker state
./scripts/beads-dolt-pilot.sh enable                     # Enable isolated pilot mode
./scripts/beads-dolt-pilot.sh review                     # Pilot review surface
./scripts/beads-dolt-rollout.sh report-only --format json  # Rollout staging report
./scripts/beads-dolt-rollout.sh cutover --worktree .       # Staged cutover for ready worktree
./scripts/beads-dolt-rollout.sh verify --worktree .        # Cutover verification surface
./scripts/beads-dolt-rollout.sh rollback --package-id <id> --worktree .  # Explicit rollback
```

## Daemon

```bash
bd daemon status
bd daemon start
bd daemon stop
bd daemon restart
```

## Formulas (Workflows)

```bash
bd formula list             # List templates

# Ephemeral (wisp)
bd mol wisp NAME --vars "key=value"

# Persistent
bd mol pour NAME --vars "key=value"

# Manage
bd mol progress WISP_ID
bd mol current
bd mol squash WISP_ID       # Save
bd mol burn WISP_ID         # Discard
```

## Patrols

```bash
bd patrol list
bd patrol run NAME --vars "key=value"
```
