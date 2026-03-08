# Claude Asset Instructions

This directory contains the source assets that are bridged into Codex skills and related workflows.

## Scope

Important areas:
- `.claude/skills/`
- `.claude/commands/`
- `.claude/agents/`
- `.claude/hooks/`
- `.claude/schemas/`
- `.claude/scripts/`
- `.claude/settings*.json`

## Rules

1. Treat `.claude/skills/*` as the primary reusable workflow layer.
2. Treat `.claude/commands/*` and `.claude/agents/*` as reference assets unless intentionally migrating them into skills.
3. Do not break hook or schema contracts casually.
4. Keep command, skill, and agent boundaries clear.
5. Prefer updating the real source asset instead of patching generated or copied outputs elsewhere.

## Skill Sync

If you change anything under `.claude/skills/`, verify Codex bridge behavior:

```bash
make skills-sync
make skills-check
```

Restart Codex after sync if discovery behavior matters.

## Settings

Be careful with:
- `.claude/settings.json`
- `.claude/settings.local.json`
- any permission, sandbox, or hook-related settings

These files can change runtime behavior significantly.

## Validation

After substantial changes, check:
- referenced files still exist
- schemas still match expected structure
- hooks still point to valid scripts
- skills remain concise and reusable
- command docs do not drift from current repo reality
