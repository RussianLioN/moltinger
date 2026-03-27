---
title: "Moltis browser timeout recurred because canonical production still ran the stock browser sandbox contract from main"
date: 2026-03-27
severity: P1
category: operational-drift
tags: [moltis, browser, sandbox, browserless, docker, main, drift, telegram, rca]
root_cause: "The earlier browser repair stack existed in branch 031, but canonical production still ran origin/main with the stock browserless contract, so browser launches kept timing out on the live runtime."
---

# RCA: Moltis browser timeout recurred because canonical production still ran the stock browser sandbox contract from main

## Summary

The Telegram timeout on 2026-03-27 was not a new random browser failure.

The live production runtime was still using the stock browser sandbox contract from `origin/main`:

- `sandbox_image = "browserless/chrome"`
- no tracked `profile_dir`
- no tracked `persist_profile`

At the same time, the audited browser repair stack already present in `031` had already proved the missing writable-profile contract:

- `sandbox_image = "browserless/chrome"`
- `profile_dir = "/tmp/moltis-browser-profile/shared"`
- `persist_profile = false`
- explicit host-visible shared browser profile mount and permission prep

This means the incident recurred because canonical production never consumed the already-audited browser contract from `031`.

## Error

User-facing behavior:

- Telegram returned `Timed out: Agent run timed out after 30s`
- Telegram also leaked `Activity log`

Authoritative live reproduction outside Telegram confirmed the same browser failure:

- remote RPC `chat.send` with an explicit `browser` prompt started normally
- no final reply arrived within `CHAT_WAIT_MS=90000`
- event stream ended with:
  - `tool_call_start tool=browser`
  - `error.type = timeout`

Live Moltis logs for the same class of run showed:

- `browser container failed readiness check, cleaning up`
- `browser launch failed: browser container failed to become ready within 60s (120 probe attempts)`

## 5 Whys

| Level | Question | Answer | Evidence |
|-------|----------|--------|----------|
| 1 | Why did browser runs still time out on production? | Because the live runtime still failed browser readiness before the agent timeout window closed. | Live Moltis logs and remote RPC browser canary on 2026-03-27. |
| 2 | Why did readiness still fail? | Because production still ran the stock `browserless/chrome` contract without the audited writable `profile_dir` contract from `031`. | `docker exec moltis grep ... /home/moltis/.config/moltis/moltis.toml` showed `sandbox_image = "browserless/chrome"` and no `profile_dir` / `persist_profile`. |
| 3 | Why is that important if the stock image is the official baseline? | Because on this host the stock image succeeds only when the browser profile bind is writable; without that it aborts on `SingletonLock: Permission denied`. | Same-host isolated repro with `DEFAULT_USER_DATA_DIR=/data/browser-profile` and a root-owned bind reproduced the failure; same stock image with a writable `/tmp/...` bind succeeded. |
| 4 | Why was the recurrence visible first in Telegram? | Because Telegram is the user-facing path that already combined browser timeout with internal activity leakage and stale-chat contamination. | Authoritative Telegram UAT and live chat evidence on 2026-03-27. |
| 5 | Why did this happen again after earlier browser repair work existed? | Because the earlier browser stack lived in `031`, while canonical production still followed `main`, so later deploys kept the stock baseline instead of the audited branch contract. | `origin/main` vs `031` diff on browser files plus live runtime config inspection. |

## Root Cause

The root cause was **mainline browser contract drift**, not simply “Docker is broken again”.

More precisely:

- official Moltis browser/sandbox baseline was only partially sufficient for this deployment;
- the audited writable profile-dir contract existed in `031`;
- canonical production still ran `origin/main`, which did not include that contract;
- therefore browser timeouts recurred whenever the model actually selected the `browser` tool.

## Evidence

### Official baseline still present on production

Live production facts on 2026-03-27:

- Moltis runs inside Docker
- host Docker socket is mounted
- `host.docker.internal:host-gateway` is configured
- runtime config includes `container_host = "host.docker.internal"`

So the official Moltis baseline for sibling browser containers was not wholly absent.

### Stock browser contract still active on production

Live runtime config inside the container showed:

- `[tools.browser]`
- `sandbox_image = "browserless/chrome"`
- no explicit `profile_dir`
- no explicit `persist_profile`

### Stock browserless image behavior on the same host

Two isolated host-side checks established the decisive boundary:

- stock `browserless/chrome` with a root-owned bind mount failed on first browser job with:
  - `Failed to create /data/browser-profile/SingletonLock: Permission denied (13)`
- the same stock image with a writable host bind (`chmod 0777` temp dir under `/tmp`) succeeded through:
  - `/json/version`
  - websocket upgrade on `/`
  - successful browser job cleanup

### Current production failure proof

Remote RPC browser canary:

- prompt: `Используй browser, открой https://docs.moltis.org/ и ответь только заголовком страницы.`
- run id: `921d7913-d6e2-4e08-8adc-5f8a4d3d1849`
- result: no final event within `CHAT_WAIT_MS=90000`
- events: `tool_call_start tool=browser`, then timeout error

Live Moltis logs for that window:

- `agent run timed out ... timeout_secs=30`
- `browser container failed readiness check, cleaning up`

## Fix Recommendation

Do not treat this as a Telegram-only issue and do not attempt another feature-branch-only runtime repair.

Safe remediation path:

1. freeze the audited root cause in tracked RCA/consilium/carrier artifacts
2. prepare a minimal browser-runtime carrier to `main`
3. land that carrier through the canonical `main` path
4. run the standard production deploy from `main`
5. re-prove both:
   - remote RPC browser canary
   - authoritative Telegram/browser path after chat contamination is reconciled

## Lessons

1. **A browser repair that never lands in `main` is not a closed production fix.**
2. **Official-doc compliance can still be operationally insufficient for a specific deployment if writable profile storage is missing.**
3. **For the current host/tag, stock `browserless/chrome` remains viable once the profile bind is writable, so a custom image should not be the default hotfix assumption.**
4. **Telegram noise can obscure the browser root cause, but direct RPC/browser canaries plus isolated host repro remove that ambiguity.**
