# Quickstart: Clawdiy Agent Platform

- **Feature**: `001-clawdiy-agent-platform`
- **Date**: 2026-03-09

This is the operator validation path after implementation. Each stage is a stop/go gate.

## Prerequisites

- Moltinger production runtime is healthy on `https://moltis.ainetic.tech`
- DNS exists for `clawdiy.ainetic.tech`
- dedicated Telegram bot exists for Clawdiy
- GitHub Secrets exist for Clawdiy human auth, service auth, Telegram, and optional provider auth
- shared host networks remain healthy: `traefik-net`, `fleet-internal`, `moltinger_monitoring`

## Stage 1: Validate Config And Registry

```bash
test -f config/clawdiy/openclaw.json
test -f config/fleet/agents-registry.json
test -f config/fleet/policy.json
test -f docker-compose.clawdiy.yml
```

Expected outcome:

- Clawdiy has a unique `agent_id`
- Clawdiy has a unique subdomain and Telegram identity
- service auth is distinct from Moltinger auth

## Stage 2: Preflight

```bash
./scripts/preflight-check.sh --ci --target clawdiy --json
docker compose -f docker-compose.clawdiy.yml config --quiet
```

Expected outcome:

- no identity collisions
- no missing Clawdiy baseline secrets
- compose renders cleanly

## Stage 3: Deploy Same-Host Runtime

```bash
./scripts/deploy.sh --json clawdiy deploy
./scripts/clawdiy-smoke.sh --json --stage same-host
```

Expected outcome:

- this is the first live OpenClaw launch for Clawdiy
- Clawdiy responds on `https://clawdiy.ainetic.tech`
- Moltinger remains healthy
- Clawdiy config/state/audit roots stay isolated

## Stage 4: Verify Inter-Agent Handoff

```bash
./scripts/clawdiy-smoke.sh --json --stage handoff
```

Expected outcome:

- accepted, rejected, duplicate, timeout, and late-completion evidence is visible
- authoritative handoff path is still private HTTP JSON

## Stage 5: Verify Telegram And Baseline Auth

```bash
./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider telegram --json
./scripts/clawdiy-smoke.sh --json --stage auth
```

Expected outcome:

- Telegram polling credentials validate cleanly
- Telegram remains in long-polling mode for phase 1
- missing/invalid auth fails closed
- baseline Clawdiy runtime health does not depend on provider OAuth

## Stage 6: Verify Codex OAuth Gate

```bash
./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider codex-oauth --json
```

Expected outcome:

- provider profile is JSON
- required scopes include `api.responses.write`
- allowed models include `gpt-5.4`
- if the check fails, Clawdiy remains healthy and Codex-backed capability stays disabled

## Stage 7: Verify Recovery Path

```bash
./scripts/deploy.sh --json clawdiy rollback
./scripts/clawdiy-smoke.sh --json --stage rollback-evidence
```

Expected outcome:

- Clawdiy returns to last-known-good state or disables cleanly
- Moltinger remains unaffected
- rollback evidence references a real backup archive

## Stage 8: Verify Future-Node Readiness

```bash
./scripts/clawdiy-smoke.sh --json --stage extraction-readiness
```

Expected outcome:

- `agent_id`, logical address, and handoff paths remain unchanged
- only endpoint placement changes between `same_host` and `remote_node`
- future permanent roles can reuse the same registry/policy model

## Operator Notes

- same-host deployment is the first production target
- remote-node extraction is a later placement change, not a topology rewrite
- Telegram is not the authoritative machine transport and stays on polling in phase 1
- webhook mode is a later rollout, not part of this baseline quickstart
- Codex OAuth and `gpt-5.4` are explicit rollout gates, not MVP blockers
