# MemPalace Project Memory

This repository supports MemPalace as an **external, pinned project-memory search layer** for engineering context.

It is intentionally **not**:
- the runtime-memory system for Moltis;
- the source of truth for topology, deploy truth, secrets, or cleanup decisions;
- an auto-learning system that creates skills or agents by itself.

Authoritative project memory stays in:
- `MEMORY.md`
- `SESSION_SUMMARY.md`
- `docs/`
- `knowledge/`
- `specs/**/{spec,plan,tasks}.md`

MemPalace only indexes a curated subset of those artifacts to make historical recall faster.

## Quick Start

1. Bootstrap the pinned install:

```bash
./scripts/mempalace-bootstrap.sh
```

2. Build or refresh the curated index:

```bash
./scripts/mempalace-refresh.sh
```

The wrapper follows the official MemPalace `init -> mine` flow against a curated snapshot. For the pinned `mempalace==3.0.0`, it also auto-accepts the default generated room layout so refresh remains non-interactive.

3. Search project memory manually:

```bash
./scripts/mempalace-search.sh "why did we change deploy flow"
```

If your client reads the repo `.mcp.json`, restart it after bootstrap and refresh so the `mempalace` MCP server becomes available through the wrapper script.

## What Gets Indexed

The curated corpus is defined in `scripts/mempalace-corpus.txt`.

Included by default:
- `MEMORY.md`
- `SESSION_SUMMARY.md`
- `docs/**/*.md`
- `knowledge/**/*.md`
- `specs/**/spec.md`
- `specs/**/plan.md`
- `specs/**/tasks.md`

Excluded by default:
- `docs/GIT-TOPOLOGY-REGISTRY.md`
- all source code
- `.env*`, `secrets/`, provider keys, credentials
- build artifacts and runtime dumps

## Storage Paths

Wrapper-managed state:
- venv: `~/.local/share/moltinger/mempalace/venv`
- palace: `~/.local/share/moltinger/mempalace/palace`
- wrapper home/config: `~/.local/share/moltinger/mempalace/home`

Repo-local temporary staging:
- curated snapshot: `.tmp/mempalace/corpus`

## MCP Usage

The repo MCP entry points to:

```json
"mempalace": {
  "command": "./scripts/mempalace-mcp-server.sh"
}
```

That wrapper:
- enforces the exact supported MemPalace version;
- uses the repo-managed palace path;
- fails closed if bootstrap or refresh has not been completed.

This is a deliberate compatibility wrapper around the official MemPalace MCP entrypoint `python -m mempalace.mcp_server`.

## Update Policy

- No `latest`.
- No auto-update.
- Only exact pin `mempalace==3.0.0`.
- Any pin change must go through a dedicated maintenance lane with smoke validation.

## Default Workflow

Run refresh after meaningful changes to:
- `MEMORY.md`
- `SESSION_SUMMARY.md`
- docs or knowledge notes
- spec artifacts that should become searchable project memory

Use MemPalace for:
- past decision lookup;
- cross-doc historical recall;
- finding related RCA, plans, and knowledge notes.

Do not use MemPalace as proof of:
- current runtime state;
- current topology state;
- current deploy state;
- current secret values.

## Experimental Hooks (Opt-In, Unsupported)

Hooks are intentionally **off by default** in this repository.

If you want an experimental local-only refresh on session stop, keep it in a private local config such as `.claude/settings.local.json`, not in tracked repo settings:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ./scripts/mempalace-refresh.sh >/dev/null 2>&1 || true"
          }
        ]
      }
    ]
  }
}
```

This remains unsupported-by-default because upstream MemPalace hook packaging and CLI contracts are still drifting.

## Troubleshooting

Bootstrap missing or version drift:

```bash
./scripts/mempalace-bootstrap.sh
```

Index missing or stale:

```bash
./scripts/mempalace-refresh.sh
```

Inspect which files would be indexed without rebuilding:

```bash
./scripts/mempalace-refresh.sh --list-only
```

If the wrapper still fails after bootstrap and refresh, treat it as a local tool/runtime problem, not as proof that project memory is absent.
