# Consilium Report

## Question
How should we remediate PR #76 so GPT-5.4 OAuth rollout remains intact, while pipeline/script contracts stay green and stable?

## Execution Mode
Mode B (tool-parallel evidence + expert matrix)

## Evidence
- `gh pr view 76` showed `mergeable=CONFLICTING`, `mergeStateStatus=DIRTY`, and failing checks (`codex-policy`, `Gate`).
- `make codex-check-ci` failed on `openai-codex`/`gpt-5.*` references being flagged as deprecated.
- `./tests/run.sh --lane pr --json` failed with contract errors tied to `backup/preflight/uat-gate/rollback/handoff/web-monitor`.
- After restoring those contract files to `origin/main` baseline and re-running lanes, `static`, `component`, `integration_local`, and full `pr` lane passed.

## Expert Opinions

### Architect
- Opinion: branch carried stale infra contracts; keep only minimal GPT-5.4/OAuth intent above a stable baseline.
- Key points: reduce blast radius, preserve canonical contracts, avoid accidental rollback of unrelated subsystems.

### SRE
- Opinion: failing gate was signal of contract regression, not flaky runtime.
- Key points: trust gate; restore known-good control-plane scripts before changing provider order.

### DevOps
- Opinion: policy and deployment contracts must be versioned together.
- Key points: eliminate contradictory policy rules; ensure CI checks align with active provider strategy.

### Security
- Opinion: fail-closed behavior should remain in preflight/backup/handoff controls.
- Key points: restoring mainline guardrails is preferable to relaxing checks.

### QA
- Opinion: enforce lane progression (`static` -> `component` -> `integration_local` -> `pr`) after rebase conflicts.
- Key points: root-cause remediation validated by green `summary.status=passed`.

### Domain Specialist (Moltis/OpenAI OAuth)
- Opinion: OpenAI OAuth provider naming is now canonical for this rollout.
- Key points: do not deprecate `openai-codex` and `gpt-5.*`; keep fallback chain explicit.

### Delivery/GitOps
- Opinion: post-rebase drift must be normalized in git, not patched ad hoc on server.
- Key points: baseline restoration + minimal feature delta is the safest delivery pattern.

## Root Cause Analysis
- Primary root cause: stale branch payload overwrote current infra contract files after rebase.
- Contributing factors: deprecation policy drift in `codex-check` contradictory to actual GPT-5.4 OAuth migration.
- Confidence: High.

## Solution Options (>=5)
1. Keep stale branch as-is and patch tests only — fast, but institutionalizes drift and weakens contracts.
2. Full reset branch to `main` and redo feature from scratch — clean, but high effort and slow.
3. Restore only failing files to `main`, then re-apply minimal GPT-5.4/OAuth intent — balanced, low risk, fast.
4. Relax Gate requirements temporarily — unblocks merge, but hides real regressions.
5. Add one-off test skips for failing suites — avoids immediate failures, but increases long-term fragility.

## Recommended Plan
1. Restore contract-critical files to `origin/main` baseline (backup/preflight/uat/rollback/handoff monitor).
2. Re-apply only GPT-5.4/OAuth model-chain changes in `config/moltis.toml`.
3. Update `scripts/codex-check.sh` so OpenAI/GPT-5.* references are not deprecated by policy.
4. Validate with `make codex-check-ci` and full `./tests/run.sh --lane pr --json`.
5. Commit and push with clear RCA/consilium artifacts.

## Rollback Plan
- Revert the remediation commit(s) and rerun `make codex-check-ci` + `./tests/run.sh --lane pr --json` to confirm prior state.
- If needed, hard reset branch pointer to pre-remediation commit hash in controlled branch-repair procedure.

## Verification Checklist
- [x] `make codex-check-ci` passes
- [x] `./tests/run.sh --lane pr --json` reports `status=passed`
- [x] GPT-5.4 OAuth chain remains configured as primary -> ollama -> glm-5
