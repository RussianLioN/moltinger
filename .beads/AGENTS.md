# Beads State Instructions

This directory stores Beads tracker state for the repository.

## Rules

1. Prefer the `bd` CLI over hand-editing files in `.beads/`.
2. Do not hand-edit `.beads/issues.jsonl` or `.beads/config.yaml` unless the user explicitly asks or you are doing controlled state recovery.
3. If manual recovery is required, create a backup first and preserve record order, identifiers, and JSONL integrity.
4. Keep issue state aligned with repository reality. After meaningful issue lifecycle changes, run the narrowest relevant `bd` command, usually `bd status` for local inspection.
5. Do not use `.beads/` for notes, drafts, or scratch artifacts.

## Validation

Use the narrowest relevant `bd` command:
- `bd ready`
- `bd show <id>`
- `bd update <id> --status ...`
- `bd close <id>`
- `bd status`

## Escalation

Stop and ask before:
- deleting or rebuilding `.beads/issues.jsonl`
- changing tracker configuration semantics
- bulk-editing issue state outside the `bd` CLI
