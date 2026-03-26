---
title: "Moltis lost OpenAI Codex OAuth at runtime because production was still running an old mainline checkout and old compose contract"
date: 2026-03-21
status: closed
tags: [moltis, oauth, openai-codex, gpt-5.4, gitops, deploy, runtime-drift, rca]
---

# RCA: Moltis lost OpenAI Codex OAuth at runtime because production was still running an old mainline checkout and old compose contract

## Summary

Production Moltis on `ainetic.tech` stopped exposing `openai-codex::gpt-5.4`, even though the OAuth token store still existed on disk.

The live failure was not “OAuth expired” and not “OpenAI auth code was removed from git”.
The actual problem was operational drift:

- `/opt/moltinger` on the server was still on old `main` commit `3cf6a5c`
- old `docker-compose.prod.yml` mounted `./config:/home/moltis/.config/moltis:ro`
- the running container therefore did **not** mount `/opt/moltinger-state/config-runtime`
- `oauth_tokens.json` still existed in `/opt/moltinger-state/config-runtime`, but live Moltis was not reading it
- the live runtime config also lacked `openai-codex` in `[providers].offered`

Once the server checkout was moved to tracked branch `031-moltis-reliability-diagnostics`, `MOLTIS_VERSION=latest` was removed from `.env`, and tracked deploy was re-run, Moltis came back with:

- `/server` mounted
- `/home/moltis/.config/moltis` mounted from `/opt/moltinger-state/config-runtime`
- `openai-codex [valid ... remaining]`
- successful live canary on `openai-codex::gpt-5.4`

## Error

OpenAI Codex OAuth appeared “broken” in production Moltis, and chat requests were failing with model-not-found symptoms even though OAuth had worked earlier.

## 5 Whys

### 1. Why did Moltis report that `openai-codex::gpt-5.4` was not available?

Because the live runtime provider surface no longer included `openai-codex`, so chat fell back to a stale or incompatible provider/model view.

### 2. Why did the live runtime provider surface no longer include `openai-codex`?

Because the running container was reading an old `moltis.toml` from `/opt/moltinger/config`, and that config only offered `openai` (Z.ai) rather than the later GitOps `openai-codex -> ollama -> zai` chain.

### 3. Why was the running container reading `/opt/moltinger/config` instead of the runtime config dir?

Because the server was still running an old `docker-compose.prod.yml` that mounted `./config:/home/moltis/.config/moltis:ro` and did not mount `/server` or `${MOLTIS_RUNTIME_CONFIG_DIR}`.

### 4. Why was production still on that old compose contract?

Because the server checkout `/opt/moltinger` had drifted to an old `main` commit (`3cf6a5c`) instead of the tracked branch/commit where the `gpt-5.4` OAuth path and writable runtime config contract were already established.

### 5. Why did that drift survive long enough to look like an auth outage?

Because the live runtime still had a preserved `oauth_tokens.json`, but deploy/runtime verification had not yet forced the container to prove it was actually mounted to the runtime config dir. The token store survived, but the container was disconnected from it.

## Root Cause

Production was not running the tracked GitOps checkout and compose contract that carries the canonical Moltis OAuth path.

The real breakage was:

1. old server checkout on `main`
2. old read-only config mount
3. missing `/server` workspace mount
4. stale runtime config without `openai-codex`

OAuth state itself still existed and became valid again as soon as the runtime was reattached to the correct config mount.

## Evidence

- Server checkout before repair: `/opt/moltinger` on branch `main`, commit `3cf6a5c`
- Old compose on server mounted only:
  - `./config:/home/moltis/.config/moltis:ro`
  - `moltis-data:/home/moltis/.moltis`
  - `/var/run/docker.sock:/var/run/docker.sock:ro`
- Preserved token store found at:
  - `/opt/moltinger-state/config-runtime/oauth_tokens.json`
- Running container after repair mounts:
  - `/opt/moltinger -> /server (ro)`
  - `/opt/moltinger-state/config-runtime -> /home/moltis/.config/moltis (rw)`
- `docker exec moltis moltis auth status` after repair:
  - `openai-codex [valid (... remaining)]`
- Live canary after repair returned final response:
  - provider `openai-codex`
  - model `openai-codex::gpt-5.4`
  - text `OK`

## Corrective Actions

1. Moved the server checkout to tracked branch `031-moltis-reliability-diagnostics` at commit `bb2e04e6f542797671d40b2c4d409f2aaf22cc01`.
2. Removed `MOLTIS_VERSION=latest` override from `/opt/moltinger/.env`.
3. Re-ran tracked deploy, which prepared `/opt/moltinger-state/config-runtime` while preserving `oauth_tokens.json`.
4. Verified:
   - runtime config mount source
   - `/server` mount
   - `openai-codex` auth status
   - live chat canary on `gpt-5.4`

## Preventive Actions

1. Keep tracked deploy/runtime contract verification enabled so a container with healthy `/health` but wrong mounts fails deploy.
2. Do not keep `MOLTIS_VERSION` in `.env`; version must live only in tracked compose files.
3. When Moltis OAuth “disappears”, check mounts and active checkout before starting a fresh OAuth login.
4. Preserve `oauth_tokens.json` only in `${MOLTIS_RUNTIME_CONFIG_DIR}`, never in git-synced `config/`.

## Operator Notes

- This incident looked like an authentication regression but was actually a GitOps/runtime drift incident.
- Re-auth was **not** required for recovery.
- The correct first checks for future incidents are:
  1. `git branch --show-current && git rev-parse HEAD` in `/opt/moltinger`
  2. `docker inspect moltis --format '{{json .Mounts}}'`
  3. `docker exec moltis moltis auth status`
