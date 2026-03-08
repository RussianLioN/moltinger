# AI Instruction Source Instructions

This directory is the source of truth for generated Codex instructions.

## Scope

Primary files:
- `.ai/instructions/shared-core.md`
- `.ai/instructions/codex-adapter.md`

These files generate the repository root `AGENTS.md`.

## Rules

1. Do not edit the generated root `AGENTS.md` directly when the real change belongs here.
2. Keep shared rules in `shared-core.md`.
3. Keep Codex-specific deltas in `codex-adapter.md`.
4. Do not duplicate the same rule in both files unless duplication is intentional.
5. Prefer small, surgical instruction changes over broad rewrites.
6. Keep token pressure under control. Central instruction files are high-frequency reads.

## Validation

After changing anything here, run:

```bash
make instructions-sync
make instructions-check
```

If the generated `AGENTS.md` changed unexpectedly, inspect the diff before continuing.

## Content Strategy

- Put global repository behavior here.
- Do not move narrow directory-specific rules here if a local `AGENTS.md` is more appropriate.
- Prefer linking to durable docs instead of embedding large operational narratives.
