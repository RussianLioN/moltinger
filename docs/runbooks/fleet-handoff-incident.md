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
5. Confirm baseline runtime health:
   ```bash
   ./scripts/clawdiy-smoke.sh --stage same-host
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

## Immediate Containment

- Stop retries if the route, recipient identity, or service auth is wrong.
- Preserve the latest JSONL audit artifact under `data/clawdiy/audit` before editing runtime or policy.
- Keep Moltinger user-facing communication separate from machine-facing handoff recovery; a Telegram reply is not closure.

## Response By Incident Type

### Rejected

Use when the handoff fails closed with an explicit rejection.

1. Check whether the requested capability is present in `config/fleet/agents-registry.json`.
2. Check whether the caller is allowlisted in `config/fleet/policy.json`.
3. If the rejection is correct, hand the task back to the operator/coordinator with explicit reason.
4. If the rejection is incorrect, fix registry/policy drift in git, redeploy, and re-run:
   ```bash
   ./scripts/clawdiy-smoke.sh --stage handoff
   ```

### Timed Out

Use when delivery or terminal acknowledgement is missing before policy deadlines.

1. Compare the last known state with `delivery_ack_deadline_seconds`, `start_ack_deadline_seconds`, and `terminal_timeout_seconds`.
2. Verify Clawdiy and Moltinger health independently.
3. If auth is degraded, rotate or repeat-auth first; do not replay blindly.
4. Replay only when idempotency is known and prior side effects are either absent or explicitly safe.

### Duplicate

Use when the same `Idempotency-Key` or duplicated channel delivery appears more than once.

1. Treat the first accepted record as authoritative.
2. Do not delete later duplicate evidence.
3. Resolve by `idempotency_key` and `correlation_id`, not by timestamp alone.
4. If duplicate delivery came from Telegram or another human-facing path, keep the notification anomaly separate from the authoritative machine handoff.

### Late Completion

Use when completion arrives after the handoff has already been marked `timed_out`.

1. Preserve both timeout and late-completion records.
2. Do not silently convert `timed_out` to `completed`.
3. Record whether downstream side effects actually happened.
4. Escalate to operator review to decide between replay, manual closure, or rollback.

## Escalation Rules

- Missing delivery acknowledgement within target SLA: escalate as undelivered
- Missing terminal state after start/progress silence threshold: escalate as stuck execution
- Auth rejection or unknown recipient: stop retries until registry/policy mismatch is fixed
- Duplicate completion: preserve both records and resolve by idempotency key, not by deleting evidence
- Late completion after timeout: escalate as state-conflict, not as silent success

## Recovery Gates

- Do not replay until identity, route, and auth checks are green.
- Do not mark the incident closed until a fresh handoff smoke passes or the task is explicitly cancelled/rejected.
- Do not roll back Clawdiy without copying the latest handoff artifact path into the incident notes.

## Operator Outcome

Every incident should end in one of these states:

- completed after retry
- rejected with explicit reason
- failed with explicit reason
- timed out and escalated
- cancelled by operator
