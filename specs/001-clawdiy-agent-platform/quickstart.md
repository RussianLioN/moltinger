# Quickstart: Clawdiy Agent Platform

**Feature**: 001-clawdiy-agent-platform  
**Date**: 2026-03-09

This quickstart is the operator path expected after implementation. It is intentionally staged so the platform can stop safely after each gate.

## Prerequisites

- Current Moltinger production runtime is healthy on `moltis.ainetic.tech`
- DNS prepared for `clawdiy.ainetic.tech`
- Dedicated Telegram bot created for Clawdiy
- GitHub Secrets populated for Clawdiy human auth, service auth, Telegram bot, and optional provider auth
- Existing Traefik shared network and monitoring baseline remain healthy

## Stage 1: Prepare Registry and Runtime Config

```bash
# Validate the new fleet registry and Clawdiy runtime config exist
test -f config/fleet/agents-registry.json
test -f config/fleet/policy.json
test -f config/clawdiy/openclaw.json
test -f docker-compose.clawdiy.yml
```

Expected outcome:
- Clawdiy has its own canonical `agent_id`
- Clawdiy domain and Telegram bot identity are unique
- service auth and human auth secret refs are distinct from Moltinger

## Stage 2: Preflight Validation

```bash
./scripts/preflight-check.sh --target clawdiy
docker compose -f docker-compose.clawdiy.yml config --quiet
```

Expected outcome:
- no duplicate identity/domain/bot collisions
- all required Clawdiy secrets present
- compose config renders successfully

## Stage 3: Deploy Same-Host Clawdiy Stack

```bash
./scripts/deploy.sh clawdiy deploy
./scripts/clawdiy-smoke.sh --stage same-host
```

Expected outcome:
- Clawdiy is reachable on `https://clawdiy.ainetic.tech`
- Moltinger remains healthy on `https://moltis.ainetic.tech`
- per-agent health endpoints and metrics are distinguishable

## Stage 4: Verify Authoritative Inter-Agent Handoff

```bash
./scripts/clawdiy-smoke.sh --stage handoff
```

Expected outcome:
- submit -> accept -> start -> terminal flow works for a sample handoff
- correlation id and audit events are created
- reject and timeout paths are observable and non-silent

## Stage 5: Enable Telegram Human Ingress

```bash
./scripts/clawdiy-smoke.sh --stage telegram-polling
```

Expected outcome:
- Clawdiy bot receives messages in polling mode
- Telegram events remain human-facing only
- machine-to-machine handoff still uses the private internal path

## Stage 6: Gate OpenAI Codex OAuth Separately

```bash
./scripts/clawdiy-auth-check.sh --provider openai-codex
```

Expected outcome:
- provider auth is explicitly validated after login
- missing scopes or bad auth fail closed
- Clawdiy platform health does not depend on successful Codex OAuth

## Stage 7: Rollback

```bash
./scripts/deploy.sh clawdiy rollback
```

Expected outcome:
- Clawdiy returns to last-known-good state or is disabled cleanly
- Moltinger remains unaffected
- rollback evidence is preserved in audit/log artifacts

## Stage 8: Future-Node Readiness Check

```bash
./scripts/clawdiy-smoke.sh --stage extraction-readiness
```

Expected outcome:
- canonical `agent_id`, registry shape, and handoff envelope remain unchanged
- only endpoint placement and private routing details differ from same-host stage

## Operator Notes

- If a planning-stage scope blocker emerges, use a narrow `speckit.clarify` only for that blocker.
- Do not promote webhook mode or Codex-backed coding role until same-host baseline and rollback drill are green.
