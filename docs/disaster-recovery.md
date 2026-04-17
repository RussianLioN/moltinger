# Disaster Recovery Runbook

**Version**: 1.1
**Last Updated**: 2026-03-09
**Related Features**: `001-fallback-llm-ollama`, `001-clawdiy-agent-platform`

## Overview

This runbook covers two separate recovery tracks:

- **Moltis LLM failover**: keep Moltinger available when the primary provider fails.
- **Clawdiy single-agent recovery**: restore, roll back, or disable Clawdiy without taking Moltinger down.

The main rule is unchanged: protect Moltinger first. Clawdiy is allowed to degrade, roll back, or disable if that is what keeps the primary platform healthy and preserves evidence.

## Recovery Boundaries

| Surface | Primary runtime | Recovery target | Must stay isolated from |
|---------|-----------------|-----------------|-------------------------|
| Moltinger chat/runtime | `moltis` | `docker-compose.prod.yml` | Clawdiy state, Clawdiy auth |
| Moltis LLM failover | GLM/Ollama/Gemini | provider chain + circuit state | Clawdiy runtime rollback |
| Clawdiy runtime | `clawdiy` | `docker-compose.clawdiy.yml` | Moltinger state and secrets |
| Clawdiy evidence | `data/clawdiy/audit` | backup + rollback manifests | repo root temp files |
| Clawdiy workspace | `data/clawdiy/workspace` | runtime work directory for OpenClaw execution | ad-hoc root-owned files |

## Clawdiy Single-Agent Recovery

### Incident Signals

Treat Clawdiy as degraded when any of the following is true:

- `./scripts/health-monitor.sh --once --json` reports `clawdiy` as `unhealthy` or `degraded`
- `./scripts/clawdiy-smoke.sh --stage same-host --json` fails
- `./scripts/clawdiy-smoke.sh --stage handoff --json` fails and Moltinger is otherwise healthy
- `./scripts/clawdiy-smoke.sh --stage auth --json` fails after auth rotation
- deploy or rollback completes without a fresh rollback evidence manifest

### Evidence Sources

Capture these before changing runtime:

- `./scripts/deploy.sh --json clawdiy status | jq .`
- `./scripts/health-monitor.sh --once --json | jq .`
- `./scripts/clawdiy-smoke.sh --json --stage same-host | jq .`
- latest files under `data/clawdiy/audit/`
- latest files under `data/clawdiy/audit/rollback-evidence/`
- latest backup reference from `data/clawdiy/.last-backup`, with fallback to `/var/backups/moltis/pre_deploy_*.tar.gz*` and then legacy `/var/backups/moltis/{daily,weekly,monthly}/`

### Decision Table

| Situation | Preferred action | Why |
|-----------|------------------|-----|
| Clawdiy deploy regressed, previous image exists | `./scripts/deploy.sh --json clawdiy rollback` | Fastest path back to last-known-good |
| Clawdiy deploy regressed, no previous image | `./scripts/deploy.sh --json clawdiy rollback` | Same command fail-closes into disabled mode |
| Backup payload missing `config/clawdiy`, `data/clawdiy/state`, `data/clawdiy/audit`, or `clawdiy-evidence-manifest.json` | Stop and rebuild backup inventory | Partial restore is blocked by default |
| Auth-only regression | repeat-auth first | Do not burn a healthy runtime for a credential issue |
| Handoff contract drift with healthy runtime | fix registry/policy drift, then redeploy | Preserve runtime and evidence before rollback |

### Quick Recovery Commands

Assess current state:

```bash
./scripts/deploy.sh --json clawdiy status | jq .
./scripts/health-monitor.sh --once --json | jq .
./scripts/clawdiy-smoke.sh --json --stage same-host | jq .
```

Roll back Clawdiy:

```bash
./scripts/deploy.sh --json clawdiy rollback | jq .
./scripts/clawdiy-smoke.sh --json --stage rollback-evidence | jq .
./scripts/clawdiy-smoke.sh --json --stage same-host | jq .
curl -fsS http://127.0.0.1:13131/health
```

Verify restore readiness of the latest backup:

```bash
LATEST=$(ls -t /var/backups/moltis/daily/moltis_* /var/backups/moltis/weekly/moltis_* /var/backups/moltis/monthly/moltis_* 2>/dev/null | head -1)
./scripts/backup-moltis-enhanced.sh verify "$LATEST"
```

Run an explicit restore only when rollback is insufficient:

```bash
./scripts/backup-moltis-enhanced.sh restore "$LATEST" /tmp/clawdiy-restore-drill
./scripts/clawdiy-smoke.sh --json --stage same-host | jq .
```

### Non-Negotiable Rules

- Do not restore a backup that lacks Clawdiy config, state, audit, and evidence manifest inventory.
- Do not delete `data/clawdiy/audit` or `data/clawdiy/audit/rollback-evidence` to “clean up” before rollback.
- Do not treat a Telegram response as proof that inter-agent recovery succeeded.
- Do not restore Moltinger files as part of a Clawdiy-only recovery unless Moltinger is also part of the incident.

### Closeout Checklist

An incident is not closed until all of the following are true:

- Moltinger health endpoint returns `200`
- Clawdiy is either healthy again or explicitly disabled by operator choice
- latest rollback evidence manifest has `status="completed"`
- latest backup archive passes `backup-moltis-enhanced.sh verify`
- operator notes include the backup reference and rollback reason

## Moltis LLM Failover Recovery

### Failover Chain

```text
OpenAI Codex (`gpt-5.4`) -> Ollama Gemini -> Claude Sonnet -> GLM-5.1 (official BigModel)
```

### Circuit States

| State | Meaning | Active provider |
|-------|---------|-----------------|
| `CLOSED` | normal operation | OpenAI Codex (`gpt-5.4`) |
| `OPEN` | failover active | Ollama |
| `HALF-OPEN` | testing primary recovery | OpenAI Codex auth probe |

### Primary Checks

```bash
cat /tmp/moltis-llm-state.json | jq .
./scripts/health-monitor.sh --once --json | jq .
./scripts/ollama-health.sh --json
```

### Manual Actions

Force failover:

```bash
echo '{"state":"open","failure_count":3,"success_count":0,"last_failure_time":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","last_state_change":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","active_provider":"ollama","fallback_provider":"ollama"}' > /tmp/moltis-llm-state.json
```

Force recovery to OpenAI Codex:

```bash
echo '{"state":"closed","failure_count":0,"success_count":0,"last_failure_time":null,"last_state_change":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","active_provider":"openai-codex","fallback_provider":"ollama"}' > /tmp/moltis-llm-state.json
```

Restart Ollama:

```bash
docker compose restart ollama
sleep 60
./scripts/ollama-health.sh --json
```

### Escalation

Escalate immediately when:

- all LLM providers are unavailable
- failover does not recover after 15 minutes
- Ollama repeatedly crashes
- circuit breaker state is corrupted or inconsistent with live health checks

## Post-Incident

After either kind of incident:

1. Record the timeline and triggering symptom in `docs/LESSONS-LEARNED.md`.
2. Preserve the evidence path, especially Clawdiy backup and rollback manifest references.
3. Update the relevant runbook if the operator had to improvise.
4. Re-run the smallest relevant smoke:
   - `./scripts/clawdiy-smoke.sh --json --stage same-host`
   - `./scripts/clawdiy-smoke.sh --json --stage handoff`
   - `./scripts/clawdiy-smoke.sh --json --stage auth`
   - `./scripts/ollama-health.sh --json`

## References

- [SESSION_SUMMARY.md](/Users/rl/coding/moltinger-openclaw-control-plane/SESSION_SUMMARY.md)
- [clawdiy-rollback.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-rollback.md)
- [clawdiy-repeat-auth.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-repeat-auth.md)
- [fleet-handoff-incident.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/fleet-handoff-incident.md)
