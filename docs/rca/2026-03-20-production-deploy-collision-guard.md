# RCA: Parallel production deploy collisions across workflows

**Date:** 2026-03-20  
**Status:** Resolved  
**Impact:** Parallel runs from different workflows/refs could mutate the same production target (`ainetic.tech:/opt/moltinger`) concurrently, creating nondeterministic deploy state and rollback ambiguity.

## Error

Pipeline concurrency protection was scoped by workflow/ref instead of by shared production target.

As a result, independent workflows (`deploy.yml`, `deploy-clawdiy.yml`, `uat-gate.yml`) could overlap while mutating the same remote host/path.

## 5 Whys

| Level | Question | Answer |
| --- | --- | --- |
| 1 | Why could deploy collisions happen? | Workflows touching the same server did not share one lock domain. |
| 2 | Why not? | `deploy.yml` and `deploy-clawdiy.yml` used ref-scoped groups (`deploy-${{ github.ref }}` patterns) that do not serialize different refs/workflows. |
| 3 | Why did `uat-gate.yml` still collide? | Its deploy job had no concurrency lock. |
| 4 | Why was this missed? | Static validation asserted deploy safety contracts, but had no invariant for a shared remote lock group across mutation workflows. |
| 5 | Why did this become visible now? | Increased parallel operational activity across multiple deployment branches/workflows exposed the missing serialization boundary. |

## Root Cause

Missing **target-scoped serialization contract** for production remote mutations.  
Existing guards were workflow-local, not remote-target-global.

## Corrective Actions

1. Unified production lock group to `prod-remote-ainetic-tech-opt-moltinger`:
   - `.github/workflows/deploy.yml` (workflow-level concurrency)
   - `.github/workflows/deploy-clawdiy.yml` (workflow-level concurrency)
   - `.github/workflows/uat-gate.yml` deploy job (job-level concurrency, narrow lock scope)
2. Added runtime second-layer mutex in `scripts/deploy.sh` for mutating commands (`deploy|rollback|start|stop|restart`) with:
   - `flock` path when available
   - `mkdir` + TTL fallback when `flock` is unavailable
3. Added static regression test:
   - `static_production_workflows_share_remote_lock_group`
   - verifies all production-mutating workflows keep the same remote lock group.

## Prevention

1. Keep one canonical lock group for any workflow mutating `/opt/moltinger` on `ainetic.tech`.
2. Treat serialization as a tested contract (not convention) via static test coverage.
3. Keep server-side mutex in deploy tooling to protect manual or out-of-band invocations.

## Lessons

1. Workflow-local concurrency is insufficient when multiple workflows mutate a shared remote target.
2. Serialization must be defined by resource identity (host/path/service), not by git ref.
3. Root-cause fixes require both pipeline guardrails and runtime fail-safe locking.
