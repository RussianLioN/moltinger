# Tasks: Clawdiy Remote OAuth Runtime Lifecycle

**Input**: Design documents from `/specs/017-clawdiy-remote-oauth-lifecycle/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Mandatory. This feature requires static config validation, auth-boundary checks, live smoke, and post-auth canary evidence because metadata-only success is not acceptable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when file ownership does not overlap
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`)

---

## Phase 0: Planning (Executor Assignment) ✅ COMPLETE

- [x] P001 Audit the current Clawdiy metadata gate, runbooks, and live-runtime OAuth gaps for `specs/017-clawdiy-remote-oauth-lifecycle/spec.md`
- [x] P002 Record official/community evidence in `docs/research/clawdiy-openclaw-remote-oauth-runtime-2026-03-12.md` and `specs/017-clawdiy-remote-oauth-lifecycle/research.md`
- [x] P003 Define runtime auth store, provider activation, and canary boundaries in `specs/017-clawdiy-remote-oauth-lifecycle/contracts/`
- [x] P004 Break the implementation into ordered phases in `specs/017-clawdiy-remote-oauth-lifecycle/tasks.md`

---

## Phase 1: Setup

- [x] T001 Create runtime auth lifecycle design notes and evidence inventory in `specs/017-clawdiy-remote-oauth-lifecycle/validation.md`
- [x] T002 [P] Add cross-links from Clawdiy docs to the new runtime OAuth lifecycle package in `docs/runbooks/clawdiy-repeat-auth.md`, `docs/SECRETS-MANAGEMENT.md`, and `docs/deployment-strategy.md`
- [ ] T003 [P] Extend config/static validation expectations for runtime auth store semantics in `tests/static/test_config_validation.sh`

---

## Phase 2: Foundational

- [ ] T004 Define the authoritative runtime auth-store path and ownership contract in `config/clawdiy/openclaw.json`
- [ ] T005 Define explicit `openai-codex` provider activation semantics in `config/clawdiy/openclaw.json`
- [ ] T006 Extend `deploy-clawdiy.yml` to render metadata flags that clearly distinguish metadata gate from runtime auth store state
- [ ] T007 Extend `scripts/clawdiy-auth-check.sh` to report metadata-only vs runtime-ready vs canary-promoted states
- [ ] T008 Extend `scripts/clawdiy-smoke.sh` with runtime auth-store and provider-activation stages

**Checkpoint**: Repo surfaces can describe and validate the difference between metadata gate and runtime-ready provider state.

---

## Phase 3: User Story 1 - Real Runtime OAuth Store (Priority: P1)

### Tests

- [ ] T009 [P] [US1] Add auth-boundary coverage for missing runtime auth store, unreadable store, and wrong-locality store in `tests/security_api/test_clawdiy_auth_boundaries.sh`
- [ ] T010 [P] [US1] Add live validation coverage for runtime auth-store presence/absence in `tests/live_external/test_clawdiy_deploy_smoke.sh`

### Implementation

- [ ] T011 [US1] Implement runtime auth-store detection and reporting in `scripts/clawdiy-auth-check.sh`
- [ ] T012 [US1] Implement runtime auth-store smoke in `scripts/clawdiy-smoke.sh`
- [ ] T013 [US1] Update deploy/runbook docs to describe runtime auth-store persistence and restart behavior in `docs/runbooks/clawdiy-repeat-auth.md` and `docs/INFRASTRUCTURE.md`

**Checkpoint**: Clawdiy can prove whether runtime auth exists independently from metadata.

---

## Phase 4: User Story 2 - Repeat-Auth Without Rediscovery (Priority: P1)

### Tests

- [ ] T014 [P] [US2] Add validation for documented repeat-auth evidence and fail-closed partial bootstrap handling in `tests/security_api/test_clawdiy_auth_boundaries.sh`
- [x] T015 [P] [US2] Add quickstart verification steps and evidence recording in `specs/017-clawdiy-remote-oauth-lifecycle/quickstart.md` and `specs/017-clawdiy-remote-oauth-lifecycle/validation.md`

### Implementation

- [x] T016 [US2] Rewrite `docs/runbooks/clawdiy-repeat-auth.md` to describe the practical-now target-runtime bootstrap method
- [ ] T017 [US2] Update `docs/SECRETS-MANAGEMENT.md` to separate metadata secret handling from runtime auth artifact handling
- [ ] T018 [US2] Extend `deploy-clawdiy.yml` and `scripts/clawdiy-auth-check.sh` so repeat-auth evidence is preserved and surfaced

**Checkpoint**: Operators have one documented repeat-auth path that targets the correct runtime store.

---

## Phase 5: User Story 3 - Post-Auth Canary Promotion (Priority: P2)

### Tests

- [ ] T019 [P] [US3] Add canary gating coverage for scope mismatch, inactive provider, and canary failure in `tests/security_api/test_clawdiy_auth_boundaries.sh`
- [ ] T020 [P] [US3] Add live canary result collection to `tests/live_external/test_clawdiy_deploy_smoke.sh`

### Implementation

- [ ] T021 [US3] Implement explicit provider activation checks in `scripts/clawdiy-auth-check.sh` and `config/clawdiy/openclaw.json`
- [ ] T022 [US3] Implement post-auth canary flow and evidence recording in `scripts/clawdiy-smoke.sh`
- [ ] T023 [US3] Update docs so promotion of `gpt-5.4` requires canary success in `docs/runbooks/clawdiy-repeat-auth.md` and `docs/deployment-strategy.md`

**Checkpoint**: `gpt-5.4` promotion is evidence-based, not metadata-based.

---

## Phase 6: Polish

- [ ] T024 Reconcile artifact references and status across `specs/017-clawdiy-remote-oauth-lifecycle/`
- [ ] T025 Update `SESSION_SUMMARY.md` with the new durable research track and Speckit package handoff
- [ ] T026 Run targeted validation from `specs/017-clawdiy-remote-oauth-lifecycle/quickstart.md` and record results in `specs/017-clawdiy-remote-oauth-lifecycle/validation.md`

---

## Implementation Strategy

### MVP First

1. Finish foundational distinction between metadata and runtime auth.
2. Land runtime auth-store reporting and provider activation checks.
3. Rewrite repeat-auth docs around the correct runtime store.
4. Add canary gating and evidence.

### Target-State Follow-On

1. Add managed delivery/import flow for artifactized runtime auth store.
2. Support version-matched workstation bootstrap as a cleaner operator path.
