# Tasks: Moltis Live Codex Update Telegram Runtime Gap

**Input**: Design documents from `/specs/035-moltis-live-codex-update-telegram-runtime-gap/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `quickstart.md`

## Phase 0: Evidence And Scope

- [x] T001 Confirm `035` as a fresh post-`034` slice and attach a tracker issue for the residual live gap
- [x] T002 Re-read authoritative repo evidence for `codex-update` false-negative, host-path leakage, and `Activity log` leakage
- [x] T003 Re-check existing rules, RCA, skill/docs carrier, and current remote UAT semantics before planning changes

## Phase 1: Spec And Contract Baseline

- [x] T010 Create the Speckit package for `035-moltis-live-codex-update-telegram-runtime-gap`
- [x] T011 Record the mandatory surface split: remote advisory-only vs trusted operator/local runtime
- [x] T012 Define repo-owned vs upstream-owned closure boundaries for the residual runtime gap

## Phase 2: Repo-Owned Carrier

- [x] T020 Update `skills/codex-update/SKILL.md` so remote user-facing surfaces are advisory/notification-only and operator/local execution remains explicitly surface-scoped
- [x] T021 Update durable docs in `docs/moltis-codex-update-skill.md` and `docs/telegram-e2e-on-demand.md` to reflect the same split contract
- [x] T022 Update contract carrier guidance in `config/moltis.toml` only if the current soul text still leaves room for remote execution ambiguity
- [x] T023 Extend `scripts/telegram-e2e-on-demand.sh` to fail closed on remote `codex-update` execution-contract violations
- [x] T024 Update targeted coverage in `tests/component/test_telegram_remote_uat_contract.sh` and `tests/static/test_config_validation.sh`

## Phase 3: Verification And Handoff

- [x] T030 Run targeted regression checks for the repo-owned carrier
- [x] T031 Re-run authoritative live Telegram UAT for `codex-update` when the carrier changes are ready
- [x] T032 Reconcile `tasks.md`, record remaining upstream-owned gaps, and prepare concise handoff notes
