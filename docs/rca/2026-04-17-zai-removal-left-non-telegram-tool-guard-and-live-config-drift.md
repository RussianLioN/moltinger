# RCA: Z.ai Removal Left Non-Telegram Tool Guard Gap And Live Config Drift

**Date**: 2026-04-17
**Severity**: P1
**Category**: telegram, ui, configuration, deploy
**Status**: fixed in code, deploy pending merge

## Incident

Two user-visible symptoms were reported at the same time:

1. Web UI showed raw tool-error cards such as `missing 'query' parameter` and `missing 'command' parameter`.
2. Telegram bot still reported `model 'zai::glm-5-turbo' not found. available: []`.

## Lessons Pre-Check

Reviewed relevant prior lessons before changing code:

- `docs/rca/2026-03-20-telegram-uat-false-pass-on-model-not-found.md`
- `docs/rca/2026-04-02-telegram-skill-detail-fell-back-to-tool-error-leak.md`
- `docs/rca/2026-04-05-telegram-skill-detail-general-hardening.md`
- `docs/rca/2026-04-14-telegram-codex-update-hard-override-did-not-terminalize-blocked-tool-followup.md`

Those incidents already established two important patterns:

- Telegram and UI-safe lanes must fail closed before raw tool/runtime errors become user-visible.
- Provider-chain migrations are not complete until the live tracked runtime config is reconciled, not just repo-local code.

## 5 Whys

### Symptom A: Web UI leaked raw tool cards

1. Why did the UI show raw tool cards?
   Because malformed tool calls like `memory_search` without `query` and `exec` without `command` reached user-visible execution paths.
2. Why did malformed tool calls reach execution paths?
   Because `scripts/telegram-safe-llm-guard.sh` only had strict fail-closed suppression for Telegram-safe paths and generic telemetry/planning cases, not an explicit non-Telegram malformed-known-tool branch.
3. Why was there no explicit malformed-known-tool branch outside Telegram?
   Because earlier hardening work focused on Telegram-safe regressions and did not promote “missing required arguments” into a shared contract for all user-facing lanes.
4. Why was that shared contract missing?
   Because the owning hook evolved by incident-specific patches instead of one unified malformed-tool taxonomy.
5. Why did incident-specific patches accumulate?
   Because the migration effort treated raw tool leakage as a Telegram-only problem instead of a general user-surface problem.

### Symptom B: Telegram still referenced `zai::glm-5-turbo`

1. Why did Telegram still reference `zai::glm-5-turbo`?
   Because the live tracked runtime config still advertised `alias = "zai"`, `custom-zai-telegram-safe`, and fallback lists containing `zai::glm-5`.
2. Why was the live tracked runtime config still old?
   Because the provider-removal work had been implemented in the branch but not yet deployed into the running `/server/config/moltis.toml`.
3. Why was deploy drift able to persist?
   Because code-level migration and live-config reconciliation were not validated together as one acceptance boundary.
4. Why was acceptance split across boundaries?
   Because source-of-truth updates, runtime normalization, and live deploy verification were tracked as loosely coupled changes instead of one provider-governance contract.
5. Why was provider-governance incomplete?
   Because Z.ai removal was initially approached as config editing rather than a full “repo source + runtime normalization + live tracked config” migration.

## Root Cause

The same migration class was left incomplete in two different owning layers:

- `scripts/telegram-safe-llm-guard.sh` lacked a fail-closed branch for malformed known-tool calls outside Telegram-safe mode.
- Live tracked Moltis config on the server still carried legacy Z.ai aliases and fallback entries because deploy reconciliation had not yet happened.

## Fix

1. Added malformed-known-tool detection and fail-closed handling in `scripts/telegram-safe-llm-guard.sh` for non-Telegram user-visible lanes.
2. Added regression coverage for:
   - non-Telegram `AfterLLMCall` malformed tool-call suppression
   - non-Telegram `BeforeToolCall` malformed known-tool rewrite to no-op
3. Removed remaining active-spec drift still describing Z.ai in deployment research/tasks artifacts.
4. Kept runtime/provider normalization and attestation aligned to the official BigModel `glm::glm-5.1` fallback contract.

## Validation

Validation is complete when all of the following hold:

- component tests pass for `telegram-safe-llm-guard`
- repo source-of-truth contains no active `api.z.ai` or `zai::` references outside intentional compatibility/history paths
- live `/server/config/moltis.toml` no longer contains `alias = "zai"`, `custom-zai-telegram-safe`, or `zai::glm-*`

## Preventive Actions

1. Treat provider removal as a three-layer migration:
   - repo source config
   - runtime normalization / attestation
   - live tracked deploy config
2. Treat malformed tool calls as a shared user-surface contract, not a Telegram-only safety concern.
3. Keep authoritative probes and deploy verification coupled whenever provider aliases or fallback chains change.
