# Remote Rollout Diagnosis Starts With Traefik And Lessons (RCA-010)

**Status:** Active  
**Effective date:** 2026-03-09  
**Scope:** All remote deploy, rollout, and incident-diagnosis sessions for `ainetic.tech`

## Problem This Rule Prevents

When a remote rollout surfaces a new failing prerequisite, it is easy to treat that nearest failing check as the main diagnosis and skip already documented production lessons about Traefik routing, Host rules, and Docker DNS selection.

## Mandatory Protocol

If the task is a remote deploy, remote rollout, or production-like diagnosis and a blocker appears, restart the diagnostic context in this order:

1. `MEMORY.md`
2. `docs/LESSONS-LEARNED.md`
3. `docs/INFRASTRUCTURE.md`
4. relevant rollout/runbook docs
5. relevant `SESSION_SUMMARY.md` entries

Then validate the live baseline in this order:

1. current service health
2. `traefik-net` membership
3. `traefik.docker.network` labels
4. `Host(...)` rule / domain defaults
5. Traefik-selected backend IP / logs / DNS behavior
6. only after that: non-ingress private networks such as `fleet-internal`

## Hard Guardrail

For remote rollout diagnosis, do **not**:

- treat a newly missing internal network as the primary production diagnosis before checking the Traefik invariants above
- change deployment automation based only on the first failing preflight check
- assume a feature-specific network requirement outweighs historical ingress lessons without evidence

## Expected Behavior

- State which historical lesson set applies before proposing a rollout fix.
- Cite the operator artifacts used for the diagnosis.
- Explain whether the blocker is ingress-related, deploy-automation-related, or a truly new prerequisite.
