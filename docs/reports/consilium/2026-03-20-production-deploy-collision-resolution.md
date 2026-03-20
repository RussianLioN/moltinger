# Consilium: Production Deploy Collision Resolution

**Date:** 2026-03-20  
**Topic:** Prevent collisions from parallel production deploy runs across workflows and branches.

## Inputs

Analyzed:

- `.github/workflows/deploy.yml`
- `.github/workflows/uat-gate.yml`
- `.github/workflows/deploy-clawdiy.yml`
- `scripts/deploy.sh`

## Expert Findings (Synthesis)

1. Current lock boundaries were not shared by target.
2. `deploy.yml`/`deploy-clawdiy.yml` used ref-scoped groups, allowing cross-ref overlap.
3. `uat-gate.yml` deploy mutation path had no lock.
4. Additional fail-safe is needed at runtime in case of out-of-band/manual deploy invocation.

## Options Considered

1. Full dispatcher refactor (`workflow_call` central mutator)
2. Shared lock group on mutation workflows/jobs (minimal viable hardening)
3. Runtime-only mutex in deploy script
4. Combined pipeline lock + runtime mutex

## Decision

Choose **Option 4 (combined)**:

1. Shared production lock group in workflows to serialize GitHub Actions mutations.
2. Runtime mutex in `scripts/deploy.sh` as defense-in-depth.
3. Static test to enforce the lock-group contract.

Rationale:

- Fast to deploy safely in current branch.
- Fixes root cause at pipeline boundary.
- Prevents recurrence through test enforcement.
- Covers manual/out-of-band script use.

## Implemented Changes

1. Workflow lock harmonization:
   - `deploy.yml`: `concurrency.group = prod-remote-ainetic-tech-opt-moltinger`
   - `deploy-clawdiy.yml`: same shared group
   - `uat-gate.yml` deploy job: same shared group
2. `scripts/deploy.sh`:
   - Added mutating-command deploy mutex with `flock` + `mkdir` fallback and TTL.
3. `tests/static/test_config_validation.sh`:
   - Added `static_production_workflows_share_remote_lock_group`.

## Follow-up

1. Optional phase-2: introduce reusable dispatcher workflow for cleaner long-term orchestration.
2. Optional phase-2: expose lock owner/age via a small status script for operational diagnostics.
