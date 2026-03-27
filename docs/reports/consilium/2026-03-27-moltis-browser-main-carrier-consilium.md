# Consilium: Moltis Browser Runtime Recurrence And Main Carrier Decision

**Date**: 2026-03-27  
**Scope**: browser timeout recurrence on production Moltis, official-doc baseline, and minimal landing path to `main`

## Evidence Considered

- Official Moltis browser automation docs say that in sandbox mode the browser runs in a Docker container, the image is pulled on first use, and Moltis-in-Docker needs `container_host` to reach the sibling browser container.
- Live production runtime satisfies that baseline:
  - Docker socket mounted
  - `host.docker.internal:host-gateway`
  - `container_host = "host.docker.internal"`
- Live production runtime still uses the stock browser contract:
  - `sandbox_image = "browserless/chrome"`
  - no tracked `profile_dir`
  - no tracked `persist_profile`
- Remote RPC browser canary on production timed out after starting the `browser` tool.
- Live logs show repeated:
  - `browser container failed readiness check, cleaning up`
- Isolated host test of stock `browserless/chrome` with a root-owned bind mount reproduced:
  - `SingletonLock: Permission denied`
- The same stock image with a writable `/tmp/...` bind succeeded on the same host through a real websocket/browser job.

## Expert Verdicts

### Moltis/OpenClaw Docs Expert

- Current production is broadly official-compliant at the baseline level.
- Official docs do not fail-close repo-specific gaps like host-visible browser profile strategy or websocket-endpoint normalization.
- Therefore current production can be official-baseline compliant and still operationally fragile.

### Docker/Browserless Expert

- The current strongest live signal is not image-pull permission failure.
- Manual `docker pull browserless/chrome` succeeds now.
- The stronger active signal is browser profile storage semantics during the first real browser job under the stock image.
- Mixed evidence is best explained by:
  - earlier stale leaked Telegram activity showing an older failure fragment
  - current live runtime actually failing on readiness/CDP compatibility

### SRE Expert

- This is a production drift problem, not a local test failure.
- The fix path must be canonical:
  - minimal carrier to `main`
  - standard deploy from `main`
  - live re-proof after deploy

### GitOps Expert

- Do not redeploy `031` directly to production.
- The right artifact is a narrow browser-runtime carrier for `main`, not a full merge of the branch.

## Consolidated Decision

The browser incident should be treated as:

1. **official baseline present**
2. **repo-specific browser contract missing from production**
3. **mainline drift is the current operational blocker**

### Recommendation

Prepare and land a **minimal browser-runtime carrier** to `main` containing only:

- browser-specific `[tools.browser]` hunks in `config/moltis.toml`
- browser-profile mount and browser env/runtime wiring in `docker-compose.prod.yml`
- browser-profile preparation and tracked browser image pull in `scripts/deploy.sh`
- blocking tests that assert the browser contract

Leave mutable RCA/rules/runbook/lessons content out of the production-critical carrier if a second docs pass is easier to review separately.

## Merge Readiness Verdict

`merge with carrier discipline`

Meaning:

- **yes** to landing the browser fix path to `main`
- **no** to merging all of `031`
- **yes** to a runtime-only carrier plus blocking proof

## Practical Next Step

Materialize the browser-main carrier artifact from `031`, validate it against clean `origin/main`, and then use it as the basis for canonical landing from `main`.
