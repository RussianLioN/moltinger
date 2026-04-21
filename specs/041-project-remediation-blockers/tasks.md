# Tasks: Project Remediation Blockers

**Input**: Design documents from `/specs/041-project-remediation-blockers/`  
**Prerequisites**: `spec.md`, `plan.md`

## Phase 0: Baseline

- [x] T001 Consolidate current blocking findings for Telegram-safe leakage, provider drift, and preflight/workflow drift
- [x] T002 Create the Speckit package for the blocking remediation wave

## Phase 1: Provider And Runtime Contract

- [x] T010 Remove active GLM/Z.ai contract drift from deploy/test/runtime surfaces
- [x] T011 Reconcile primary/fallback provider contract to GPT-5.4 OAuth primary + Ollama-only fallback
- [x] T012 Extend provider verification so it attests both primary and fallback contracts

## Phase 2: Telegram-safe Containment

- [x] T020 Reconcile Telegram-safe guard, config, and tests for maintenance/debug leak containment
- [x] T021 Harden authoritative Telegram UAT expectations for deterministic safe-text delivery

## Phase 3: Preflight And Workflow Reliability

- [x] T030 Replace brittle cross-platform TOML parsing in `scripts/preflight-check.sh`
- [x] T031 Remove or neutralize bad-log/stale-contract workflow noise from active GitHub surfaces

## Phase 4: Verification

- [x] T040 Run targeted Telegram/component/static regression checks
- [x] T041 Run `scripts/preflight-check.sh --ci --json` and verify corrected Ollama evidence
- [x] T042 Run targeted provider/live or workflow-contract verification where relevant

## Phase 5: Closeout

- [x] T050 Update `tasks.md` status based on actual implementation and verification
