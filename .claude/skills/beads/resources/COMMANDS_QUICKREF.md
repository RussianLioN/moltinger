# Beads Commands Quick Reference

Repo note for Moltinger: use `./scripts/bd-local.sh` for repo-local tracker commands such as `ready`, `list`, `show`, `create`, `update`, `close`, `sync`, `info`, `doctor`, and `prime`.

## View Issues

```bash
./scripts/bd-local.sh ready                    # Available work (no blockers)
./scripts/bd-local.sh list                     # All open issues
./scripts/bd-local.sh list --all               # Include closed
./scripts/bd-local.sh list -t bug              # Filter by type
./scripts/bd-local.sh list -p 1                # Filter by priority
./scripts/bd-local.sh list --status in_progress # Filter by status
./scripts/bd-local.sh list --unlocked          # Multi-terminal safe
./scripts/bd-local.sh blocked                  # Show blocked issues

./scripts/bd-local.sh show ID                  # Issue details
./scripts/bd-local.sh show ID --tree           # With hierarchy
```

## Create Issues

```bash
./scripts/bd-local.sh create "Title" -t type -p priority
./scripts/bd-local.sh create "Title" -t type -p priority -d "Description"
./scripts/bd-local.sh create "Title" --files path/to/file.tsx    # Auto-labels

# With dependencies
./scripts/bd-local.sh create "Title" --deps blocks:OTHER_ID
./scripts/bd-local.sh create "Title" --deps blocked-by:OTHER_ID
./scripts/bd-local.sh create "Title" --deps discovered-from:OTHER_ID
./scripts/bd-local.sh create "Title" --deps parent:EPIC_ID
```

## Update Issues

```bash
./scripts/bd-local.sh update ID --status in_progress
./scripts/bd-local.sh update ID --status blocked
./scripts/bd-local.sh update ID --status open
./scripts/bd-local.sh update ID --priority 1
./scripts/bd-local.sh update ID --add-label security
```

## Close Issues

```bash
./scripts/bd-local.sh close ID --reason "Description"
./scripts/bd-local.sh close ID1 ID2 ID3 --reason "Batch done"
./scripts/bd-local.sh close ID --reason "Won't fix" --wontfix
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

## Sync & Diagnostics

```bash
./scripts/bd-local.sh sync                     # Sync DB ↔ JSONL ↔ Git
./scripts/bd-local.sh sync --force             # Force from JSONL
./scripts/bd-local.sh info                     # Project status
./scripts/bd-local.sh doctor                   # Health check
./scripts/bd-local.sh prime                    # Context injection
./scripts/bd-local.sh prime --full             # Full context
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
