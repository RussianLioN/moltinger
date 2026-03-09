# Fleet Handoff Incident Runbook

**Status**: Draft operator runbook for feature `001-clawdiy-agent-platform`  
**Scope**: Moltinger ↔ Clawdiy handoff failures and escalations

## Purpose

Diagnose and escalate cross-agent handoff failures without relying on chat transcripts alone.

## Common Incident Types

- recipient unknown or quarantined
- service auth rejected
- acknowledgement missing before deadline
- duplicate or stale completion
- user-visible completion without internal terminal acknowledgement

## First Checks

1. Identify the `correlation_id`.
2. Check whether the target agent exists in `config/fleet/agents-registry.json`.
3. Check whether the route is allowed in `config/fleet/policy.json`.
4. Review the latest handoff evidence:
   ```bash
   ./scripts/clawdiy-smoke.sh --stage handoff
   ```

## Triage Questions

- Was the handoff rejected immediately or did it time out?
- Did the sender have the right `X-Agent-Id` and bearer token?
- Did the recipient emit delivery/accept/start/terminal acknowledgements?
- Was a human-facing Telegram message sent without a machine-facing terminal state?

## Required Evidence

- `correlation_id`
- sender and recipient `agent_id`
- handoff request timestamp
- latest acknowledgement type and timestamp
- logs or audit artifact path tied to the handoff

## Escalation Rules

- Missing delivery acknowledgement within target SLA: escalate as undelivered
- Missing terminal state after start/progress silence threshold: escalate as stuck execution
- Auth rejection or unknown recipient: stop retries until registry/policy mismatch is fixed
- Duplicate completion: preserve both records and resolve by idempotency key, not by deleting evidence

## Operator Outcome

Every incident should end in one of these states:

- completed after retry
- rejected with explicit reason
- failed with explicit reason
- timed out and escalated
- cancelled by operator
