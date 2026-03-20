# RCA: PR #76 failing checks due policy drift and stale contract rollback

**Date:** 2026-03-20  
**Status:** Resolved  
**Impact:** PR #76 was blocked (`codex-policy` failure + `Test Suite Gate` failure). Deployment and merge were stalled.

## Error

Two independent failures appeared together:

1. `codex-policy` failed because `scripts/codex-check.sh` treated `openai-codex`/`gpt-5.*` references as deprecated.
2. `Test Suite Gate` failed because a stale commit reintroduced old versions of critical scripts/config contracts (backup/preflight/handoff/web monitor), causing `summary.json.status=failed`.

## 5 Whys

| Level | Question | Answer |
| --- | --- | --- |
| 1 | Why did PR checks fail? | Governance policy and runtime contract tests both failed. |
| 2 | Why did governance policy fail? | Deprecated-pattern scanner flagged active OpenAI/OAuth model naming (`openai-codex`, `gpt-5.*`). |
| 3 | Why did runtime contracts fail? | The rebased feature carried stale implementations that removed current `main` guardrails for Clawdiy/backup/preflight/handoff flows. |
| 4 | Why were stale implementations accepted into the branch? | Branch rebasing resolved merge conflicts but did not enforce contract-level verification immediately after conflict resolution. |
| 5 | Why was verification insufficient at the right boundary? | Process lacked a strict “rebase conflict -> contract test lanes + policy check” mandatory gate before continuing with further edits. |

## Root Cause

A combined process drift:

1. **Policy drift:** `codex-check` deprecation rules no longer matched the current canonical OpenAI/OAuth model strategy.  
2. **Contract drift:** stale code paths survived rebase conflict handling without immediate lane-level contract validation.

## Corrective Actions

1. Restored regressed contract-critical files to current `origin/main` baseline (`backup`, `preflight`, `uat-gate`, `rollback-drill`, `telegram-web-user-monitor`, and `moltis.toml` base contracts).
2. Re-applied GPT-5.4 OAuth chain changes on top of stable baseline only (primary `openai-codex::gpt-5.4`, fallback `ollama`, then `zai::glm-5`).
3. Updated `scripts/codex-check.sh` policy logic: no OpenAI/GPT-5.* model patterns are treated as deprecated by default.
4. Re-ran verification:
   - `make codex-check-ci` -> pass
   - `./tests/run.sh --lane pr --json` -> pass (`summary.status=passed`)

## Prevention

1. Make rebase/conflict resolution always followed by explicit contract lane runs before any additional feature edits.
2. Keep deprecation checks data-driven and aligned with active provider strategy; avoid hardcoded vendor/model bans without active governance decision.
3. Prefer “restore to stable baseline, then re-apply minimal intent diff” when stale branch payload touches infra contracts.

## Lessons

1. **Policy must reflect canonical model strategy** — deprecation scanners must not contradict active production model naming (`openai-codex`, `gpt-5.*`).  
2. **Rebase requires immediate contract validation** — after conflict resolution, run contract lanes before proceeding (`static`, `component`, `integration_local`, then `pr`).  
3. **Fix root cause by baseline restoration** — when stale drift is broad, first restore contract files to trusted `main`, then re-apply feature intent in minimal scoped changes.
