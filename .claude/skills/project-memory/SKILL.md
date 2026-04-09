---
name: project-memory
description: Search Moltinger project memory through MEMORY.md, SESSION_SUMMARY.md, docs, knowledge, and spec artifacts using the repo MemPalace wrapper. Use when the user says "память проекта", "project memory", "найди в памяти проекта", or asks to recall past decisions, RCA, plans, and historical documentation context without manually remembering shell commands.
allowed-tools: Bash, Read, Grep
---

# Project Memory

Use this skill for historical project recall in Moltinger.

Typical triggers:
- "память проекта: почему мы меняли deploy flow?"
- "найди в памяти проекта RCA про gitops"
- "use project-memory to recall past decisions"

## Workflow

1. Read `MEMORY.md` and `SESSION_SUMMARY.md` first.
2. If the request needs broader historical recall, run:

```bash
./scripts/mempalace-search.sh "<query>"
```

3. Summarize the relevant hits and reference the underlying docs.
4. Treat MemPalace results as search hints, not as the source of truth.
5. For critical claims, verify against the underlying documents before stating conclusions.

## Fallbacks

- If MemPalace is not bootstrapped yet, run:

```bash
./scripts/mempalace-bootstrap.sh
```

- If the index is missing or stale, run:

```bash
./scripts/mempalace-refresh.sh
```

- If the wrapper is unavailable, fall back to direct document search in `docs/`, `knowledge/`, `MEMORY.md`, and `SESSION_SUMMARY.md`.

## Do Not Use For

- current runtime truth
- current topology truth
- current deploy truth
- secrets or credentials
