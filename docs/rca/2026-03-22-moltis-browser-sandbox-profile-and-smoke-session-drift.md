---
title: "Moltis browser, memory, and Tavily degraded because sibling-browser runtime assumptions drifted, operator smoke reused stale chat state, and Tavily tool args were too permissive"
date: 2026-03-22
status: closed
tags: [moltis, browser, browserless, docker, tavily, memory, smoke, session, rca]
---

# RCA: Moltis browser, memory, and Tavily degraded because sibling-browser runtime assumptions drifted, operator smoke reused stale chat state, and Tavily tool args were too permissive

## Summary

After OpenAI OAuth/runtime recovery, live Moltis on `ainetic.tech` still had three user-visible reliability defects:

- browser runs failed after the `browser` tool started
- operator smoke could misreport stale results because it reused polluted chat state
- Tavily and memory needed fresh post-restart proof, and Tavily search remained brittle when the model filled `country` implicitly

The browser outage was two-layered:

1. The sibling Docker browser container inherited a persistent profile contract that was not valid for the host-visible browser runtime. Chrome failed with:
   - `Failed to create /data/browser-profile/SingletonLock: Permission denied (13)`
2. After bypassing that lock-file failure, Moltis still connected to the sandbox at root websocket `ws://host.docker.internal:<port>`, while the local shim only proxied explicit `/devtools/browser/...` paths. That produced:
   - `browser launch failed: failed to connect to containerized browser at ws://host.docker.internal:<port>: HTTP error: 404 Not Found`

Separately:

- `scripts/test-moltis-api.sh` reused the `main` chat session without clearing it first, so authoritative smoke runs could inherit stale context.
- Tavily search succeeded eventually, but one live run first failed when the model passed `country="Russia"`. The latest guarded run succeeded on the first Tavily tool call after adding a prompt-level constraint around Tavily country usage.

## Error

Moltis looked transport-healthy, but browser automation still failed in real chat runs, memory/search smoke could be contaminated by stale session context, and Tavily search could emit avoidable first-call failures.

## 5 Whys

### 1. Why did browser tasks still fail after Docker socket access was restored?

Because the browser sandbox had deeper runtime contract mismatches beyond socket access.

### 2. Why did the sandbox mismatch matter?

Because Chrome first tried to persist a profile under a bind-mounted host-visible path that was not writable for the transient sibling container.

### 3. Why did browser still fail after that persistence issue was bypassed?

Because Moltis connected to the sandbox over the root websocket URL, but the local CDP shim initially forwarded only the explicit DevTools websocket path.

### 4. Why could memory/search smoke still look wrong even when live tools were healthy?

Because the operator smoke script reused stale `main` session context instead of clearing it before `chat.send`.

### 5. Why did Tavily still show fragility after transport recovery?

Because the model could still fill Tavily's optional `country` argument implicitly, and that caused avoidable tool-call variability until we added an explicit prompt guardrail.

## Root Cause

There were three root causes:

1. **Browser runtime misconfiguration and shim gap**: sibling-browser profile persistence assumed a writable host-visible profile path, and the local browser shim did not initially resolve root websocket upgrades to the active DevTools browser websocket.
2. **Operator smoke drift**: the authoritative smoke script reused stale chat session history.
3. **Tavily tool-call permissiveness**: the prompt contract allowed the model to infer Tavily `country` values when the user had not asked for geographic filtering.

## Evidence

- Live browser container logs showed:
  - `Failed to create /data/browser-profile/SingletonLock: Permission denied (13)`
- Independent host reproduction proved:
  - `browserless/chrome` with bind-mounted `/data/browser-profile` failed
  - Chrome with container-local `/tmp/browser-profile` became healthy
- Live Moltis logs later showed a second browser failure layer:
  - browser readiness on `/json/version` passed
  - Moltis connected to `ws://host.docker.internal:<port>`
  - the sandbox returned `HTTP error: 404 Not Found`
- After the root websocket CDP fix, live Moltis logs showed:
  - `sandboxed browser connected successfully`
  - `created new page with viewport`
  - `navigated to URL`
  - `tool execution succeeded tool=browser`
- Before smoke hardening, operator smoke reused the `main` session.
- After smoke hardening, live logs showed:
  - `chat.clear session=main`
- Memory recovery proof after restart showed:
  - `memory system initialized embeddings=true`
  - `memory: status ... model=nomic-embed-text`
  - `tool execution succeeded tool=memory_search`
  - final response `/server`
- Tavily recovery proof after the final prompt guard showed:
  - `tool execution succeeded tool=mcp__tavily__tavily_search`
  - no preceding Tavily tool failure in the same latest run
  - final response `docs.moltis.org`

## Fix

- Kept sibling-browser mode on the official Docker path, but moved Chrome startup in the tracked local sandbox image to container-local `/tmp/browser-profile` with `PREBOOT_CHROME=false`.
- Added a CDP proxy that:
  - rewrites `/json/version`
  - caches the active browser websocket path
  - resolves root websocket upgrades to the active `/devtools/browser/...` target
- Kept the tracked Docker runtime contract for:
  - `container_host = "host.docker.internal"`
  - live Docker socket GID injection
  - prebuilt local sandbox image pre-pull/build during deploy
- Updated `scripts/test-moltis-api.sh` to run `chat.clear` before `chat.send`.
- Pinned memory embeddings to Ollama root endpoint `http://ollama:11434` and kept repo knowledge sync into Moltis memory.
- Added a prompt-level Tavily guard in `config/moltis.toml`:
  - do not set `country` unless the user explicitly asks for geographic filtering
  - when needed, use Tavily schema-compatible lowercase English country values

## Verification

Repository checks:

- `node --check docker/moltis-browser-sandbox/cdp-proxy.mjs`
- `bash tests/unit/test_deploy_workflow_guards.sh` -> `27/27 PASS`
- `bash tests/static/test_config_validation.sh` -> `101/101 PASS`
- `git diff --check` clean

Live tracked deploys:

- `1f98a41` deployed successfully and restored browser end-to-end
- `bd35a53` deployed successfully and removed the observed first-call Tavily failure in the latest canary

Live authoritative canaries after the final deploy:

- Browser:
  - prompt: `Используй browser, открой https://docs.moltis.org/ и ответь только заголовком страницы.`
  - final reply: `Introduction - Moltis Documentation`
- Memory:
  - prompt: `Используй memory_search. В каком пути внутри runtime Moltis находится checkout репозитория? Ответь только одним путем.`
  - final reply: `/server`
- Tavily:
  - prompt: `Используй Tavily search. Найди официальный сайт документации Moltis и ответь только доменом.`
  - final reply: `docs.moltis.org`
  - final run completed with one Tavily tool call and no intermediate Tavily tool failure

## Уроки

1. **Sibling-browser success needs both profile-path correctness and websocket-path correctness**: fixing filesystem permissions was necessary but not sufficient.
2. **Operator smoke must clear state before proof runs**: a clean runtime still looks broken if the canary reuses polluted chat history.
3. **Tool-call reliability needs guardrails at the tool-usage contract layer**: optional search parameters should not be inferred casually when the user did not ask for them.
4. **Transport-green deploys are not enough**: browser, memory, and Tavily need exercised-surface proof after each runtime repair.
