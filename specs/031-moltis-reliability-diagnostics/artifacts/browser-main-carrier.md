# Browser Main Carrier: Runtime-Only Fix For Production Browser Timeouts

**Purpose**: capture the exact browser-runtime carrier that must move from `031-moltis-reliability-diagnostics` into `main` before the canonical production deploy can fix the current browser timeout incident.

## Decision

Consilium consensus for the current browser recurrence:

- production currently runs the stock browser contract from `main`
- `031` already contains the audited browser-runtime fix path
- incident closure requires a narrow browser-runtime carrier to `main`, not a full merge of `031`

## Current Live Root Cause

Production Moltis still runs:

- `sandbox_image = "browserless/chrome"`
- no tracked `profile_dir`
- no tracked `persist_profile`

This is enough for the official baseline, but not enough for this deployment's audited runtime contract.

Live proof collected on 2026-03-27:

- remote RPC `browser` canary timed out after starting the `browser` tool
- live Moltis logs showed `browser container failed readiness check`
- stock `browserless/chrome` on the same host failed with `SingletonLock: Permission denied` when the browser profile bind was root-owned
- the same stock image succeeded on the same host once the bound profile dir was writable

## Source Deltas

The carrier should be sourced from these already-audited branch deltas:

- `5f904e3`
  - restore browser sandbox Docker access
- `d943194`
  - stabilize browser deploy env wiring
- `2b384e0`
  - pin writable browser profile dir
- `eca3d5e`
  - warm tracked browser sandbox image
- `865fc27`
  - disable persistent browser profiles in Docker mode
- `0c8abc3`
  - stabilize sibling browser profile path
- isolated host reproduction on 2026-03-27
  - prove that the stock image remains sufficient once the profile bind is writable

## Must-Have Files And Hunks

### 1. `config/moltis.toml`

Carry only the browser-specific `[tools.browser]` hunks:

- keep `sandbox_image = "browserless/chrome"` as the official-first default
- add `profile_dir = "/tmp/moltis-browser-profile/shared"`
- add `persist_profile = false`
- keep the Docker-in-Docker `container_host = "host.docker.internal"` contract

Do not drag Tavily, Telegram, prompt, or memory-only hunks into this carrier.

### 2. `docker-compose.prod.yml`

Carry only browser-runtime surface required by the tracked contract:

- mount `/tmp/moltis-browser-profile:/tmp/moltis-browser-profile`

Keep existing Docker socket and `host.docker.internal` wiring intact.

Do not drag unrelated env or provider-surface changes unless they are already present in `main`.

### 3. `scripts/deploy.sh`

Carry only browser-runtime preparation and proof wiring:

- tracked browser profile path constants
- `prepare_moltis_browser_profile_dir()`
- `prepull_moltis_browser_sandbox_image()`
- deploy-time hook to prepare the profile dir before Moltis recreate
- keep image preparation as stock-image pre-pull only

Do not drag unrelated memory, auth, or lessons tooling hunks into this carrier.

### 4. Minimal Blocking Tests

Carry only the tests that prove the browser contract:

- `tests/static/test_config_validation.sh`
- `tests/unit/test_deploy_workflow_guards.sh`

Minimum assertions:

- tracked browser image remains the official stock image
- tracked browser profile dir and `persist_profile = false` stay present
- deploy script prepares the browser profile dir
- deploy script pre-pulls the tracked browser sandbox image
- host-visible browser profile mount stays in compose

## Explicit Excludes

Leave these out of the runtime-only browser carrier:

- RCA / consilium / rules / runbook / lessons files
- Speckit wording changes that are not needed for the live runtime fix
- Telegram UAT and activity-leak changes
- Tavily and memory-only changes
- Beads/worktree governance changes

## Pre-Merge Proof

The browser carrier is not ready for `main` without:

```bash
bash tests/static/test_config_validation.sh
bash tests/unit/test_deploy_workflow_guards.sh
```

And at least one same-host proof of the stock-image boundary:

- stock `browserless/chrome` fails with a root-owned bind mount on the target host
- stock `browserless/chrome` succeeds on the same host once the bound profile path is writable

## Post-Deploy Live Proof From `main`

After the browser carrier lands in `main`, canonical deploy must prove all of the following:

1. production runtime `moltis.toml` includes the tracked browser contract
2. browser profile path is mounted and writable on the host-visible path
3. remote RPC browser canary succeeds:
   - `Используй browser, открой https://docs.moltis.org/ и ответь только заголовком страницы.`
4. authoritative Telegram/browser path is rechecked after stale invalid chat output is reconciled

## Operational Note

This artifact is the planning/landing contract only.

Actual incident closure still requires:

1. landing the carrier to `main`
2. canonical production deploy from `main`
3. live remote browser proof
4. only then closing the remaining browser backlog items
