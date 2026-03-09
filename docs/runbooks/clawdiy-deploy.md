# Clawdiy Deploy Runbook

**Status**: Draft operator runbook for feature `001-clawdiy-agent-platform`  
**Scope**: Same-host phase-1 deployment of Clawdiy beside Moltinger

## Purpose

Deploy Clawdiy as a separate long-lived OpenClaw runtime without regressing Moltinger.

## Preconditions

- `docker-compose.clawdiy.yml` exists and renders with `docker compose config --quiet`
- `config/clawdiy/openclaw.json`, `config/fleet/agents-registry.json`, and `config/fleet/policy.json` are present
- DNS for `clawdiy.ainetic.tech` exists
- Clawdiy GitHub Secrets exist and are distinct from Moltinger secrets
- Shared host networks required for phase 1 are healthy:
  - `traefik-net`
  - `moltinger_monitoring`
- `fleet-internal` may be absent before the very first rollout; it is bootstrap-capable and should be created by `deploy-clawdiy.yml` or `./scripts/deploy.sh`, not by ad-hoc manual SSH changes

## Target Deploy Flow

1. Validate config and secret presence:
   ```bash
   ./scripts/preflight-check.sh --target clawdiy
   env CLAWDIY_IMAGE=ghcr.io/openclaw/openclaw:latest docker compose -f docker-compose.clawdiy.yml config --quiet
   ```
   Expected note: `network_bootstrap` may warn that `fleet-internal` will be created during the Clawdiy deploy flow.
2. Sync repo-managed artifacts through CI/CD or GitOps deploy flow.
   For the GitHub Actions path, the remote SSH deploy command must propagate `GITHUB_ACTIONS=true` and `GITHUB_RUN_ID` so `scripts/deploy.sh` is treated as CI, not as an ad-hoc manual SSH rollout.
3. Deploy Clawdiy:
   ```bash
   ./scripts/deploy.sh clawdiy deploy
   ```
4. Run same-host smoke verification:
   ```bash
   ./scripts/clawdiy-smoke.sh --stage same-host
   ./scripts/clawdiy-smoke.sh --stage restart-isolation
   ```

## Success Criteria

- `https://clawdiy.ainetic.tech` responds through Traefik
- Moltinger remains healthy on `https://moltis.ainetic.tech`
- Clawdiy uses separate config, registry, state, and audit roots
- Clawdiy can restart without mutating Moltinger runtime state

## Ownership Boundary

- Git-managed control-plane config:
  - `config/clawdiy/openclaw.json`
  - `config/fleet/agents-registry.json`
  - `config/fleet/policy.json`
- Distinct persistent host paths:
  - `data/clawdiy/state`
  - `data/clawdiy/audit`
- Shared same-host networks with separate ownership labels:
  - `traefik-net`
  - `fleet-internal`
  - `moltinger_monitoring`
- Local service bind remains host-local:
  - `127.0.0.1:18789`

## Immediate Failure Gates

Stop rollout if any of the following happens:

- duplicate `agent_id`, domain, or Telegram bot identity detected
- Clawdiy deploy path tries to reuse Moltinger state or password material
- Traefik routes Clawdiy through the wrong network
- Clawdiy is missing `moltinger_monitoring`, or `fleet-internal` is still absent after the deploy flow had a chance to bootstrap it
- Moltinger health regresses during Clawdiy deploy

## Evidence To Capture

- `docker compose -f docker-compose.clawdiy.yml config --quiet`
- preflight output
- remote `/tmp/clawdiy-deploy-result.json` rendered by `deploy-clawdiy.yml` even when deploy exits non-zero
- `./scripts/clawdiy-smoke.sh --stage same-host --json`
- `./scripts/clawdiy-smoke.sh --stage restart-isolation --json`
- Traefik router/service labels for Clawdiy
- health status for both agents

## Disable Procedure

1. Stop Clawdiy runtime without touching Moltinger:
   ```bash
   ./scripts/deploy.sh clawdiy stop
   ```
2. Confirm Clawdiy is no longer running:
   ```bash
   ./scripts/deploy.sh --json clawdiy status | jq .
   ```
3. Confirm Moltinger is still healthy:
   ```bash
   curl -fsS http://127.0.0.1:13131/health
   ```

## Escalation

- If Clawdiy deploy fails but Moltinger is healthy, stop and move to `clawdiy-rollback.md`
- If Moltinger health regresses, treat as production incident and prioritize Moltinger recovery before continuing Clawdiy work
