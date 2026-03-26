---
title: "Moltis Runtime Contract"
category: "reference"
tags: ["moltis", "runtime", "deploy", "oauth", "memory"]
source: "original"
date: "2026-03-22"
confidence: "high"
---

# Moltis Runtime Contract

## Summary

Production Moltis is considered correctly deployed only when the live process is
running against the tracked repository workspace, the writable runtime config
directory, and the intended provider catalog.

## Key Concepts

- **Workspace mount**: The live container must see the active deploy checkout at
  `/server`, not an old image-only filesystem.
- **Writable runtime config**: OAuth tokens and runtime-managed auth files must
  live in `/home/moltis/.config/moltis` backed by a writable host path.
- **Runtime restart**: Changes to `moltis.toml` only take effect after the Moltis
  process is recreated or restarted.
- **Canonical memory path**: The built-in memory backend always supports
  `~/.moltis/MEMORY.md` and `~/.moltis/memory/*.md`; rely on that path for
  durable project knowledge.

## Details

The most important live invariants are:

- `/server` points to the tracked checkout for the active branch or release.
- `/home/moltis/.config/moltis` points to the canonical runtime config directory.
- The runtime config mount is writable so OAuth and provider state survive restarts.
- The live process has actually restarted after tracked config changes.
- `openai-codex::gpt-5.4` remains available after restart.

When any of these invariants drift, the typical user-facing symptoms are:

- OpenAI OAuth appears "lost" even though tokens still exist on disk.
- `memory_search` falls back to the wrong embedding providers.
- Browser or MCP tools disappear from the registered tool surface.
- Deploy looks healthy on `/health`, but the running process still uses stale state.
