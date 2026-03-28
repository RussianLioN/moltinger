# RCA: Moltis browser canary still failed because a local shared-profile contract drifted beyond the official Docker browser guidance

Date: 2026-03-28
Severity: high
Scope: production Moltis browser automation, Telegram user chat, browser canary, Tavily-assisted research flows
Status: fixed in git, pending canonical merge and deploy from `main`

## Summary

After the earlier `docker.sock` / `host.docker.internal` browser repair was already merged,
production Moltis still failed browser requests. The failure changed shape:

- no more `permission denied while trying to connect to the docker API`;
- browser launches now reached the sibling browser container startup phase;
- then the browser container failed readiness and the run timed out;
- Telegram users saw `Timed out` plus leaked internal activity/tool output.

The decisive live evidence was not another Docker socket problem. The sibling browser
container itself logged:

- `Failed to create /data/browser-profile/SingletonLock: Permission denied (13)`
- `Failed to create a ProcessSingleton for your profile directory. Aborting now to avoid profile corruption.`

Root cause: the tracked browser contract had grown a non-official assumption that a
single shared host profile directory could safely back multiple non-persistent browser
instances. That assumption was wrong for the live `browserless/chrome` runtime and was
not required by official Moltis Docker/browser docs.

## Evidence

- Live production config before the fix kept:
  - `[tools.browser] max_instances = 3`
  - `profile_dir = "/tmp/moltis-browser-profile/shared"`
  - `persist_profile = false`
- Live browser tool errors changed from Docker API denial to readiness failure:
  - `browser container failed to become ready within 60s`
  - `tool execution failed tool=browser error=operation timed out after 60000ms`
- Manual `docker run browserless/chrome` on the host became healthy, proving the image
  itself was not broken.
- Manual inspection of the transient `moltis-browser-*` sibling container showed:
  - host port publish existed;
  - HTTP probes initially hit `connection reset` / `empty reply`;
  - the container log ended with `SingletonLock` permission failure.
- Host inspection of `/tmp/moltis-browser-profile/shared` showed stale restrictive
  contents owned by a different UID/GID than the `browserless/chrome` runtime user.
- `browserless/chrome` image user is `uid=999 gid=999`.
- Official Moltis docs confirm only the following browser-in-Docker requirements:
  - sibling browser containers use the host container runtime;
  - Dockerized Moltis must set `tools.browser.container_host`;
  - Linux Dockerized Moltis must expose `host.docker.internal:host-gateway`;
  - sandbox mode follows the session sandbox contract.
- Official docs do **not** require a shared persistent Chrome profile directory for
  Docker browser automation.

## 5 Whys

### 1. Why did browser requests still fail after the Docker socket fix?

Because the browser tool reached browser container startup, but the browser container
 could not initialize its Chrome profile directory and never became ready.

### 2. Why could the browser container not initialize its profile?

Because Chrome could not create or lock `SingletonLock` inside the configured
 host-visible browser profile directory.

### 3. Why was the profile directory not safe to use?

Because the tracked contract reused a single shared path while also allowing multiple
 instances and non-persistent cleanup semantics, so stale host-owned files and lock
 state could survive between runs.

### 4. Why did we have that shared profile contract in the first place?

Because the initial repair correctly followed the official sibling-container guidance,
 then extrapolated an additional local profile-dir strategy that was not actually
 required by the official Moltis docs and was never proven end-to-end against the live
 browser runtime.

### 5. Why was this not caught before production traffic hit Telegram again?

Because the deploy/runtime guardrails only proved mount presence and coarse root-dir
 writability, but did not yet prove:

- dedicated non-root-safe browser profile path strategy;
- non-persistent profile concurrency invariants;
- a real browser canary with a clean profile contract.

## Root Cause

Primary root cause:

- the tracked browser profile contract was locally invented beyond the official
  Moltis Docker/browser guidance and allowed a shared Chrome user-data-dir to be reused
  across non-persistent browser launches.

Contributing root causes:

- `max_instances = 3` contradicted the single-user-data-dir Chrome locking model;
- deploy prepared only the mount root and never reset the configured profile dir;
- runtime attestation did not reject non-persistent multi-instance browser profiles;
- the first repair wave stopped after fixing sibling-container connectivity.

## Fix

1. Change tracked browser config to a dedicated child profile dir:
   - `profile_dir = "/tmp/moltis-browser-profile/browserless"`
2. Pin browser concurrency to the safe contract for non-persistent profiles:
   - `max_instances = 1`
3. Keep `persist_profile = false`.
4. On deploy, purge and recreate the configured browser profile dir so stale host-owned
   profile contents cannot poison future browser launches.
5. Fail closed in deploy verification and runtime attestation when:
   - `profile_dir` is the mounted root itself;
   - `persist_profile = false` but `max_instances != 1`;
   - browser profile root or configured dir is not writable for arbitrary non-root users.
6. Extend browser canary defaults to the real browser run budget so canary evidence
   stays authoritative after browser startup is repaired.

## Verification

- `bash -n scripts/deploy.sh`
- `bash -n scripts/moltis-runtime-attestation.sh`
- `bash -n scripts/moltis-browser-canary.sh`
- `bash tests/static/test_config_validation.sh`
- `bash tests/unit/test_deploy_workflow_guards.sh`
- `bash tests/component/test_moltis_runtime_attestation.sh`
- `bash tests/component/test_moltis_browser_canary.sh`

## Prevention

- Do not invent a shared Chrome profile strategy just because the official docs require
  sibling browser containers.
- Treat browser `profile_dir` as a first-class runtime contract, not a generic writable
  scratch directory.
- For Dockerized Moltis with `persist_profile = false`, keep a dedicated child
  `profile_dir` and force `max_instances = 1` unless the upstream browser runtime
  proves a safe concurrent strategy.
- Consider a browser repair incomplete until:
  - sibling-container routing is correct;
  - browser profile ownership/cleanup strategy is correct;
  - an exercised browser canary succeeds on the live target.
