# Hosted Clawdiy Control UI Must Use Token Auth (RCA-011)

**Status:** Active  
**Effective date:** 2026-03-12  
**Scope:** Clawdiy/OpenClaw deployments that expose Control UI on `https://clawdiy.ainetic.tech` or another hosted remote URL

## Problem This Rule Prevents

Password auth in OpenClaw can exist correctly in server env and still fail the real hosted operator UX because the browser Control UI does not automatically inherit that server-side password state. This blocks UI-first OAuth and makes the hosted dashboard look broken even when runtime env is healthy.

## Mandatory Protocol

If Clawdiy Control UI is exposed on a hosted remote URL:

1. Use `gateway.auth.mode=token`, not `password`.
2. Render `OPENCLAW_GATEWAY_TOKEN` into the dedicated Clawdiy env/runtime.
3. Treat `CLAWDIY_GATEWAY_TOKEN` as the canonical GitHub secret for hosted Control UI access.
4. Allow `CLAWDIY_PASSWORD` only as a temporary migration fallback, never as the long-term target.
5. Validate the change through:
   - `./scripts/preflight-check.sh --ci --target clawdiy --json`
   - `./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider telegram`
   - `./scripts/clawdiy-smoke.sh --stage auth --json`

## Hard Guardrail

For hosted Clawdiy UI, do **not**:

- treat password auth as the preferred steady-state mode
- stop analysis at “the secret exists in `/opt/moltinger/clawdiy/.env`”
- start UI-first OAuth work before hosted gateway auth is operator-usable

## Expected Behavior

- Hosted Clawdiy UI authenticates via token-based Control UI flow.
- Legacy password fallback is visible as temporary compatibility only.
- Operator docs, deploy workflow, runtime config, and tests all describe the same token-based model.
