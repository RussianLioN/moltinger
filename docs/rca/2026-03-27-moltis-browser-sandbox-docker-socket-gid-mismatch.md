# RCA: Moltis Browser Sandbox Failed in Docker Due to Numeric `docker.sock` GID Mismatch

Date: 2026-03-27
Severity: high
Scope: production Moltis browser automation, Telegram user chat, Tavily-assisted research flows
Status: fixed

## Summary

Telegram user requests that required browser automation started failing with:

- `browser launch failed: failed to ensure browser image`
- `failed to pull browser image`
- `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock`

The live agent then continued with `memory_search` and Tavily, consumed the remaining
30-second agent budget, and the timeout path published a Telegram reply that included
an internal `Activity log` suffix.

This was not a Tavily outage and not a random runtime drift. The tracked Docker
contract for containerized Moltis was incomplete:

1. the Moltis container mounted `/var/run/docker.sock`, but did not align its
   supplementary groups to the socket's numeric GID;
2. the browser config did not explicitly model the documented
   `Moltis Inside Docker (Sibling Containers)` routing requirement.

## Evidence

- Production logs showed:
  - browser tool entered sandbox mode;
  - Moltis attempted to pull `browserless/chrome`;
  - Docker API access failed with `permission denied`;
  - the run then timed out at 30 seconds;
  - Telegram outbound used `text+suffix`, matching the leaked `Activity log`.
- Live container inspection showed:
  - Moltis runs as non-root user `moltis`;
  - `/var/run/docker.sock` is mounted read-only;
  - inside the container the process groups were `1001 1000`;
  - the mounted socket had `gid=999 mode=660`.
- Official Moltis documentation confirms:
  - browser sandbox follows session sandbox mode;
  - when Moltis runs inside Docker, the browser launches as a sibling container
    through the host Docker socket;
  - `container_host` must be set for containerized Moltis so it does not try to
    reach the sibling browser via `127.0.0.1`;
  - many generic cloud platforms do not support Docker-in-Docker at all, so this
    contract must be explicit and verified.

## RCA "5 Why"

### 1. Why did the Telegram request fail?

Because the browser tool could not launch its sandbox container and the run later hit
the global 30-second timeout.

### 2. Why could the browser sandbox container not launch?

Because Moltis could not talk to Docker through `/var/run/docker.sock`.

### 3. Why was Docker access denied even though the socket was mounted?

Because the mounted socket kept the host numeric GID (`999`), while the Moltis
process inside the container only had supplementary group `1000`.

### 4. Why did that reach the user as a noisy Telegram reply?

Because the timeout path still emitted a `text+suffix` response containing internal
activity telemetry after the actual browser failure had already consumed part of the
run budget.

### 5. Why was this not blocked before production?

Because the tracked deploy/runtime guardrails verified workspace and config
provenance, but did not yet verify the browser sandbox Docker contract:
numeric socket-group access plus host-gateway routing for sibling browser containers.

## Root Cause

The production compose and runtime attestation contract modeled Docker socket
presence, but not Docker socket usability from the live Moltis process.

The missing invariants were:

- the live Moltis process groups must contain the mounted socket's numeric GID;
- containerized Moltis must not leave browser sibling routing on the default
  loopback path.

## Fix

1. Add `group_add: "${DOCKER_SOCKET_GID:-999}"` to the Moltis Docker services.
2. Detect `DOCKER_SOCKET_GID` at deploy time from `stat -c %g /var/run/docker.sock`
   and pass it into `docker compose`.
3. Add `extra_hosts: "host.docker.internal:host-gateway"` for containerized Moltis.
4. Set `tools.browser.container_host = "host.docker.internal"` in tracked
   `config/moltis.toml`.
5. Extend deploy verification and runtime attestation so they fail closed when:
   - `docker.sock` is mounted but its GID is not present in the live Moltis process
     groups;
   - `host.docker.internal` is not mapped for the sibling browser path.

## Verification

- `bash -n scripts/deploy.sh`
- `bash -n scripts/moltis-runtime-attestation.sh`
- `bash tests/component/test_moltis_runtime_attestation.sh`
- `bash tests/unit/test_deploy_workflow_guards.sh`
- `bash tests/static/test_config_validation.sh`
- production log check:
  - no more `permission denied while trying to connect to the docker API`
  - browser tool can launch sandbox container successfully
  - Telegram repro no longer times out on this path

## Prevention

- Treat mounted Docker socket access as a numeric-ID contract, not as a boolean
  “socket exists” contract.
- Keep browser-sandbox checks in deploy verification and runtime attestation.
- Follow the official Moltis Docker guidance for sibling browser containers instead
  of relying on implicit loopback behavior.
- Continue treating Telegram `Activity log` output as a failure signal in UAT, even
  when the primary incident is infrastructure-related.
