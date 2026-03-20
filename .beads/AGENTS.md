# Beads State Instructions

This directory stores Beads tracker state for the repository.

## Rules

1. Prefer the `bd` CLI over hand-editing files in `.beads/`.
2. Do not hand-edit `.beads/issues.jsonl` or `.beads/config.yaml` unless the user explicitly asks or you are doing controlled state recovery.
3. If manual recovery is required, create a backup first and preserve record order, identifiers, and JSONL integrity.
4. Keep issue state aligned with repository reality. After meaningful issue lifecycle changes, run `bd sync`.
5. Do not use `.beads/` for notes, drafts, or scratch artifacts.

## Pilot Mode

If `.beads/pilot-mode.json` exists in the current worktree:

1. Do not use `bd sync` as the normal operator path.
2. Use `./scripts/beads-dolt-pilot.sh review` for the documented pilot review surface.
3. Do not stage `.beads/issues.jsonl` as part of pilot review reasoning.

## Validation

Use the narrowest relevant `bd` command:
- `bd ready`
- `bd show <id>`
- `bd update <id> --status ...`
- `bd close <id>`
- `bd sync`

## Escalation

Stop and ask before:
- deleting or rebuilding `.beads/issues.jsonl`
- changing tracker configuration semantics
- bulk-editing issue state outside the `bd` CLI
