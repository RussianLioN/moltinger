# Skills Instructions

This directory contains Moltis-native skills that act as reusable workflow layers.

Before creating, migrating, or revising a skill here, read:

- [docs/moltis-skill-agent-authoring.md](../docs/moltis-skill-agent-authoring.md)
- [docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md](../docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md)

## Core Rules

1. Prefer thin `SKILL.md` wrappers over giant prompts.
2. Put durable explanation and migration reasoning in `docs/`, not inside a single skill.
3. Do not assume a repo skill is live until it is installed into the official runtime-discovered path and confirmed through runtime evidence such as `/api/skills`.
4. If a new capability needs different tools, model, or session policy, consider an agent preset instead of bloating one skill.

## Validation

After changing Moltis skill authoring docs, local `AGENTS.md`, or bridge/instruction files, run:

```bash
make codex-check
```
