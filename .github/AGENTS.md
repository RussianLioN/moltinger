# GitHub Workflow Instructions

This directory controls CI/CD and GitOps-adjacent automation. Treat workflow edits as production-adjacent changes.

## Read First

Before changing workflows, read:

- `MEMORY.md`
- `SESSION_SUMMARY.md`
- `docs/LESSONS-LEARNED.md`

If the workflow touches deploy, rollback, drift detection, metrics, Telegram rollout, or UAT, inspect the related scripts first.

## Rules

1. Workflows must match repository reality.
   Before editing a workflow, verify referenced:
   - scripts
   - file paths
   - secrets
   - Make targets
   - branch names
   - artifact names
2. Prefer full-source-of-truth GitOps behavior.
   Do not introduce partial config mutation patterns that can create drift.
3. Keep permissions minimal.
   If a workflow needs broader permissions, justify them in the diff and handoff.
4. Do not hide operational risk in shell one-liners.
   If a step becomes complex, move logic into `scripts/`.
5. Keep workflow and script contracts aligned.
   If a script changes, update workflow assumptions.
   If a workflow changes, check the downstream script interface.
6. Be conservative with deploy and rollback logic.
   Small-looking workflow edits can have large production impact.
7. Inspect GitHub Actions logs for workflow, deploy, and CI work.
   Do not treat local validation as sufficient when GitHub runs exist or can be triggered.
   Before closing out workflow-related work:
   - inspect relevant GitHub Actions run logs
   - use those logs to analyze failures
   - fix log-confirmed issues when feasible in the same session
   - if no run exists yet, say so explicitly and create/trigger the narrowest useful run when appropriate

## Validation

After changing workflows, do as many of these as applicable:

- YAML sanity review
- verify referenced files exist
- inspect affected script syntax
- inspect related docs
- run targeted tests if workflow behavior implies runtime change
- inspect relevant GitHub Actions logs for the changed workflow or explicitly note that no run/log exists yet

If local execution is not possible, say so explicitly.

## High-Risk Workflows

Treat these as extra sensitive:
- `deploy.yml`
- `gitops-drift-detection.yml`
- `gitops-metrics.yml`
- `rollback-drill.yml`
- `uat-gate.yml`
- Telegram rollout workflows
