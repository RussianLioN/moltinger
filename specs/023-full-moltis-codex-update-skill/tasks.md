# Tasks: Full Moltis-Native Codex Update Skill

**Input**: Design documents from `/specs/023-full-moltis-codex-update-skill/`  
**Prerequisites**: `plan.md`, `research.md`, `data-model.md`, `quickstart.md`

## Phase 0 - Planning and Re-baseline

- [x] P001 Confirm the corrected product target: full Moltis-native ownership instead of the hybrid repo-producer model
- [x] P002 Create a fresh feature branch/worktree from current `main`
- [x] P003 Create the feature issue and link it to this new Speckit package
- [x] P004 Capture migration assumptions and supporting artifacts in `spec.md`, `plan.md`, and `research.md`

## Phase 1 - Setup

- [x] T001 Create `skills/codex-update/SKILL.md`
- [x] T002 Create operator runbook `docs/moltis-codex-update-skill.md`
- [x] T003 Create fixtures for upstream snapshots and optional project profiles under `tests/fixtures/`
- [x] T004 Create shell test skeletons for `run`, `state`, and `profile` helpers under `tests/component/`

## Phase 2 - Foundational Runtime

- [x] T005 Implement `scripts/moltis-codex-update-run.sh` as the canonical Moltis-native runtime entrypoint
- [x] T006 Implement `scripts/moltis-codex-update-state.sh` for fingerprint and last-delivery state
- [x] T007 Implement `scripts/moltis-codex-update-profile.sh` for optional profile validation/loading
- [x] T008 Register new scripts in `scripts/manifest.json`
- [x] T009 Wire new skill/runtime defaults in `config/moltis.toml`

## Phase 3 - User Story 1: On-Demand Moltis Skill (Priority: P1)

**Goal**: Moltis directly answers "Проверь обновления Codex CLI" without delegating canonical ownership to repo-side watcher scripts.  
**Independent Test**: Ask the skill or run the on-demand helper path and confirm the response is Moltis-native and in Russian.

- [x] T010 Implement upstream fetch and normalization inside `scripts/moltis-codex-update-run.sh`
- [x] T011 Implement Russian verdict rendering for on-demand responses
- [x] T012 Add component coverage for on-demand run decisions in `tests/component/test_moltis_codex_update_run.sh`
- [x] T013 Document plain-language usage in `docs/moltis-codex-update-skill.md`

## Phase 4 - User Story 2: Moltis-Owned Scheduler and Delivery (Priority: P1)

**Goal**: Moltis owns scheduled polling, duplicate suppression, and alert decisions.  
**Independent Test**: Run scheduler mode twice on the same fingerprint and confirm duplicate suppression.

- [ ] T014 Implement scheduler mode and fingerprint suppression in `scripts/moltis-codex-update-run.sh`
- [ ] T015 Implement persistent state transitions in `scripts/moltis-codex-update-state.sh`
- [ ] T016 Integrate Telegram delivery from the Moltis-native skill path
- [ ] T017 Add component coverage for scheduler delivery/state behavior in `tests/component/test_moltis_codex_update_state.sh`
- [ ] T018 Document scheduler ownership and GitOps rollout path in `docs/moltis-codex-update-skill.md`

## Phase 5 - User Story 3: Optional Project Profiles (Priority: P2)

**Goal**: Moltis can adapt recommendations using a stable project profile instead of repo-side runtime ownership.  
**Independent Test**: Run once with a valid profile and once without a profile; confirm both outputs are useful.

- [ ] T019 Define the stable profile contract in `specs/023-full-moltis-codex-update-skill/contracts/project-profile.schema.json`
- [ ] T020 Implement profile loading and validation in `scripts/moltis-codex-update-profile.sh`
- [ ] T021 Implement project-specific recommendation mapping in `scripts/moltis-codex-update-run.sh`
- [ ] T022 Add component coverage for profile validation and recommendation shaping in `tests/component/test_moltis_codex_update_profile.sh`
- [ ] T023 Document profile usage and fallback semantics in `docs/moltis-codex-update-skill.md`

## Phase 6 - Observability, Rollout, and Retirement

- [ ] T024 Implement machine-readable audit records for manual and scheduler runs
- [ ] T025 Add hermetic end-to-end proof for `on-demand -> scheduler -> delivery/profile`
- [ ] T026 Document rollback and migration-off of the old hybrid path
- [ ] T027 Refresh topology/docs references after branch and runtime changes
- [ ] T028 Run `make codex-check` and the narrow component lane for the new skill

## Dependencies

- Phase 1 -> Phase 2 -> Phase 3/4 -> Phase 5 -> Phase 6
- US1 depends on foundational runtime
- US2 depends on state helper
- US3 depends on profile contract and base skill runtime

## Parallel Example

- T001, T002, T003, and T004 can run in parallel
- T005, T006, and T007 can be split by file ownership once contracts are stable
- T012, T017, and T022 can run in parallel after runtime code exists
