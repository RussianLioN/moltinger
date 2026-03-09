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
  - `fleet-internal`

## Target Deploy Flow

1. Validate config and secret presence:
   ```bash
   ./scripts/preflight-check.sh --target clawdiy
   env CLAWDIY_IMAGE=ghcr.io/openclaw/openclaw:latest docker compose -f docker-compose.clawdiy.yml config --quiet
   ```
2. Sync repo-managed artifacts through CI/CD or GitOps deploy flow.
3. Deploy Clawdiy:
   ```bash
   ./scripts/deploy.sh clawdiy deploy
   ```
4. Run same-host smoke verification:
   ```bash
   ./scripts/clawdiy-smoke.sh --stage same-host
   ```

## Success Criteria

- `https://clawdiy.ainetic.tech` responds through Traefik
- Moltinger remains healthy on `https://moltis.ainetic.tech`
- Clawdiy uses separate config, state, and audit roots
- Clawdiy can restart without mutating Moltinger runtime state

## Immediate Failure Gates

Stop rollout if any of the following happens:

- duplicate `agent_id`, domain, or Telegram bot identity detected
- Clawdiy deploy path tries to reuse Moltinger state or password material
- Traefik routes Clawdiy through the wrong network
- Moltinger health regresses during Clawdiy deploy

## Evidence To Capture

- `docker compose -f docker-compose.clawdiy.yml config --quiet`
- preflight output
- Clawdiy smoke output
- Traefik router/service labels for Clawdiy
- health status for both agents

## Escalation

- If Clawdiy deploy fails but Moltinger is healthy, stop and move to `clawdiy-rollback.md`
- If Moltinger health regresses, treat as production incident and prioritize Moltinger recovery before continuing Clawdiy work
