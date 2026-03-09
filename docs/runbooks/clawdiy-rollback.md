# Clawdiy Rollback Runbook

**Status**: Draft operator runbook for feature `001-clawdiy-agent-platform`  
**Scope**: Disable or revert Clawdiy without regressing Moltinger

## Purpose

Return Clawdiy to a last-known-good state or disable it entirely while preserving audit evidence.

## Rollback Triggers

- Clawdiy deployment regresses health or routing
- auth rotation leaves Clawdiy fail-open or unstable
- inter-agent protocol change causes stuck or silent handoffs
- same-host rollout creates risk for Moltinger

## Target Rollback Flow

1. Capture evidence before changing runtime:
   - failing smoke output
   - Clawdiy container logs
   - Traefik logs for Clawdiy router/service
   - latest audit artifacts under Clawdiy state root
2. Trigger rollback:
   ```bash
   ./scripts/deploy.sh clawdiy rollback
   ```
3. Verify rollback result:
   ```bash
   ./scripts/clawdiy-smoke.sh --stage same-host
   ```
4. Confirm Moltinger remains healthy.

## Rollback Modes

- **Last-known-good Clawdiy**: preferred when a valid previous deploy exists
- **Clawdiy disabled**: acceptable when preserving Moltinger availability is the priority

## Non-Negotiable Rules

- Do not delete audit artifacts just to make rollback easier
- Do not restore Moltinger files as part of a Clawdiy-only rollback
- Do not leave half-applied registry or policy state in git after rollback decision

## Evidence Checklist

- rollback trigger reason
- pre-rollback health state
- backup/snapshot reference used
- post-rollback health state
- whether Codex/GPT-5.4 capability remained disabled or was reverted
