# PR2 Main Docs Carrier

## Purpose

This artifact defines the only safe `PR2` scope after `PR1` has already landed in `main`, the canonical production deploy has succeeded, and live verification has confirmed the embedding/Ollama fix.

`PR2` is not allowed to reuse the full `031-moltis-reliability-diagnostics` branch as a direct merge source because the remaining branch delta is mixed-scope and much wider than the deferred documentation/process intent.

## Carrier Rule

Build `PR2` from verified `main`, not directly from `031-moltis-reliability-diagnostics`.

The materialized carrier patch must target the real `main` base and include any new docs explicitly; see [main-carriers-must-target-real-base.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rules/main-carriers-must-target-real-base.md).

Only the following artifact classes belong in the docs-only carrier:

- RCA reports
- consilium reports
- durable rules derived from the incident
- runbook / lessons / knowledge updates
- Speckit reconciliation for `spec.md`, `plan.md`, and `tasks.md`

## Suggested Allowlist

The materialized patch should include only the subset of these paths that still differ from verified `main`; paths already present on `main` naturally drop out of the final carrier.

- `docs/LESSONS-LEARNED.md`
- `docs/knowledge/LLM-REMOTE-MOLTIS-DOCKER-RUNBOOK.md`
- `docs/rca/2026-03-21-moltis-openai-oauth-runtime-drift.md`
- `docs/rca/2026-03-21-moltis-telegram-session-context-drift.md`
- `docs/rca/2026-03-22-moltis-auth-runtime-state-ownership-split-brain.md`
- `docs/rca/2026-03-22-moltis-browser-sandbox-profile-and-smoke-session-drift.md`
- `docs/rca/2026-03-22-moltis-runtime-cleanup-hidden-perl-dependency.md`
- `docs/rca/2026-03-22-telegram-uat-status-semantic-gap.md`
- `docs/rca/2026-03-24-beads-half-initialized-dolt-runtime-misclassified-as-healthy.md`
- `docs/rca/2026-03-24-moltis-embedding-runtime-config-and-ollama-env-drift.md`
- `docs/rca/2026-03-26-pr1-main-carrier-applicator-anchor-drift.md`
- `docs/rca/2026-03-26-pr2-carrier-target-base-and-untracked-doc-drift.md`
- `docs/rca/INDEX.md`
- `docs/reports/consilium/2026-03-22-moltis-config-durability-hardening.md`
- `docs/reports/consilium/2026-03-22-moltis-runtime-provenance-attestation-consilium.md`
- `docs/reports/consilium/2026-03-22-tavily-memory-reliability-consilium.md`
- `docs/reports/consilium/2026-03-24-moltis-embedding-runtime-contract-consilium.md`
- `docs/reports/consilium/2026-03-26-pr2-docs-carrier-scope-consilium.md`
- `docs/rules/beads-dolt-runtime-shell-is-not-a-healthy-runtime.md`
- `docs/rules/context-discovery-before-questions.md`
- `docs/rules/main-carriers-must-target-real-base.md`
- `docs/rules/moltis-runtime-memory-contract-and-ollama-cloud-env.md`
- `docs/rules/production-deploy-single-writer.md`
- `knowledge/references/moltis-runtime-contract.md`
- `knowledge/troubleshooting/moltis-memory-and-search-recovery.md`
- `specs/031-moltis-reliability-diagnostics/plan.md`
- `specs/031-moltis-reliability-diagnostics/spec.md`
- `specs/031-moltis-reliability-diagnostics/tasks.md`

## Explicit Exclusions

The docs-only carrier must exclude:

- `scripts/**`
- `tests/**`
- `.github/**`
- `docker-compose*.yml`
- `config/**`
- `.ai/**`
- `AGENTS.md`
- any generated `PR1` carrier machinery such as:
  - `specs/031-moltis-reliability-diagnostics/artifacts/apply_pr1_main_carrier.py`
  - `specs/031-moltis-reliability-diagnostics/artifacts/pr1-main-carrier.patch`
  - `specs/031-moltis-reliability-diagnostics/artifacts/pr1-main-carrier.md`
  - `specs/031-moltis-reliability-diagnostics/artifacts/pr1-main-carrier-validation.md`

## Verification

- base branch must be verified `main`
- diff must stay docs/process only
- no runtime-affecting path may enter the carrier
- `T056` must remain complete before `T057` is marked done

For the current materialized patch and dry-run proof, see [pr2-main-docs-carrier-validation.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/specs/031-moltis-reliability-diagnostics/artifacts/pr2-main-docs-carrier-validation.md).
