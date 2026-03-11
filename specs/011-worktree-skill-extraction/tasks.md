# Tasks: Portable Worktree Skill Extraction

**Input**: Design documents from `/specs/011-worktree-skill-extraction/`  
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md  
**Tests**: Validation evidence is required for install, adapter parity, Speckit coexistence, and migration acceptance  
**Organization**: Tasks are grouped by phase to match the extraction program and preserve an incremental first-release path.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no unmet dependency)
- **[Story]**: Which user story the task primarily serves (`[US1]`-`[US5]`)
- Every task includes an exact file path

---

## Phase 0: Planning (Executor Assignment) ✅ COMPLETE

**Purpose**: Complete the Speckit planning workflow before runtime extraction.

- [x] P001 Analyze current worktree, topology, bridge, and Speckit assets across `.claude/commands/`, `scripts/`, `docs/`, and `specs/`
- [x] P002 Record portability boundaries, conflicts, and release assumptions in `specs/011-worktree-skill-extraction/research.md`
- [x] P003 Define the target repo shape, compatibility matrix, validation strategy, and rollout path in `specs/011-worktree-skill-extraction/plan.md`
- [x] P004 Break the extraction program into phased implementation work in `specs/011-worktree-skill-extraction/tasks.md`

---

## Phase 1: Inventory and Classification

**Goal**: Produce a definitive asset inventory for extraction scope control.

- [ ] T001 [US5] Extend the artifact inventory and portability tags in `specs/011-worktree-skill-extraction/research.md`
- [ ] T002 [P] [US5] Capture a source-to-target extraction map for `.claude/commands/worktree.md`, `.claude/commands/session-summary.md`, and `.claude/commands/git-topology.md` in `specs/011-worktree-skill-extraction/research.md`
- [ ] T003 [P] [US5] Capture a source-to-target extraction map for `scripts/worktree-ready.sh`, `scripts/worktree-phase-a.sh`, and `scripts/git-topology-registry.sh` in `specs/011-worktree-skill-extraction/research.md`
- [ ] T004 [US5] Record all Moltinger-only exclusions and conflict artifacts in `specs/011-worktree-skill-extraction/research.md`

---

## Phase 2: Portability Boundary Definition

**Goal**: Lock the line between portable core, adapters, bridge, and host-only assets.

- [ ] T005 [US5] Define portable-core configuration boundaries and host override points in `worktree-skill/core/config/worktree-skill.env.example`
- [ ] T006 [P] [US4] Define the Speckit coexistence rules in `worktree-skill/bridge/speckit/README.md`
- [ ] T007 [P] [US2] Define Codex adapter boundary rules in `worktree-skill/adapters/codex-cli/README.md`
- [ ] T008 [P] [US1] Define Claude adapter boundary rules in `worktree-skill/adapters/claude-code/README.md`
- [ ] T009 [P] [US3] Define OpenCode adapter boundary rules in `worktree-skill/adapters/opencode/README.md`
- [ ] T010 [US5] Publish the overall boundary policy in `worktree-skill/docs/compatibility-matrix.md`

---

## Phase 3: Repository Skeleton

**Goal**: Create the standalone repo skeleton and canonical directory layout.

- [ ] T011 Create the standalone repo root documentation in `worktree-skill/README.md`
- [ ] T012 [P] Create the canonical docs layout in `worktree-skill/docs/quickstart.md`
- [ ] T013 [P] Create the release policy and versioning doc in `worktree-skill/docs/release-policy.md`
- [ ] T014 [P] Create the migration guide scaffold in `worktree-skill/docs/migration-from-in-repo.md`
- [ ] T015 [P] Create the greenfield example scaffold in `worktree-skill/examples/greenfield/README.md`
- [ ] T016 [P] Create the existing-project example scaffold in `worktree-skill/examples/existing-project/README.md`
- [ ] T017 Create the install script placeholders in `worktree-skill/install/bootstrap.sh`, `worktree-skill/install/register.sh`, and `worktree-skill/install/verify.sh`

---

## Phase 4: Core Artifact Extraction

**Goal**: Move and generalize the reusable worktree behavior into portable core.

- [ ] T018 [US1] Extract and generalize the worktree workflow prompt into `worktree-skill/core/.claude/commands/worktree.md`
- [ ] T019 [P] [US1] Extract the portable session-summary or handoff guidance into `worktree-skill/core/.claude/commands/session-summary.md`
- [ ] T020 [P] [US1] Extract the portable topology command surface into `worktree-skill/core/.claude/commands/git-topology.md`
- [ ] T021 [US1] Extract and generalize planning and handoff logic into `worktree-skill/core/scripts/worktree-ready.sh`
- [ ] T022 [P] [US1] Extract deterministic create-from-base logic into `worktree-skill/core/scripts/worktree-phase-a.sh`
- [ ] T023 [US1] Extract and generalize topology registry logic into `worktree-skill/core/scripts/git-topology-registry.sh`
- [ ] T024 [US5] Add portable handoff templates in `worktree-skill/core/templates/handoff/README.md`
- [ ] T025 [US5] Add portable topology template defaults in `worktree-skill/core/templates/topology/README.md`

---

## Phase 5: Adapter Layer for Claude/OpenCode/Codex

**Goal**: Activate the same core behavior across the three IDE surfaces.

- [ ] T026 [US1] Create the Claude Code adapter install and invocation surface in `worktree-skill/adapters/claude-code/README.md`
- [ ] T027 [P] [US1] Add Claude overlay artifacts in `worktree-skill/adapters/claude-code/.claude/commands/README.md`
- [ ] T028 [US2] Create the Codex CLI adapter install and invocation surface in `worktree-skill/adapters/codex-cli/README.md`
- [ ] T029 [P] [US2] Build a scoped Claude-to-Codex bridge installer in `worktree-skill/adapters/codex-cli/install/sync-to-codex.sh`
- [ ] T030 [US3] Create the OpenCode adapter install and invocation surface in `worktree-skill/adapters/opencode/README.md`
- [ ] T031 [P] [US3] Add any OpenCode registration helper or manual registration template in `worktree-skill/adapters/opencode/register-example.md`
- [ ] T032 [US5] Consolidate the cross-IDE compatibility matrix in `worktree-skill/docs/compatibility-matrix.md`

---

## Phase 6: Speckit Compatibility Layer

**Goal**: Preserve artifact-first spec workflows without turning Speckit into a hard dependency.

- [ ] T033 [US4] Document the Speckit compatibility contract in `worktree-skill/bridge/speckit/README.md`
- [ ] T034 [P] [US4] Add branch-spec alignment guidance in `worktree-skill/bridge/speckit/branch-spec-alignment.md`
- [ ] T035 [P] [US4] Add dedicated worktree handoff guidance for spec-driven feature work in `worktree-skill/bridge/speckit/worktree-handoff.md`
- [ ] T036 [US4] Add any needed Speckit-compatible templates in `worktree-skill/bridge/speckit/templates/README.md`

---

## Phase 7: Install and Bootstrap Scripts

**Goal**: Make installation fast, explicit, and verifiable.

- [ ] T037 [US1] Implement copy-or-materialize bootstrap flow in `worktree-skill/install/bootstrap.sh`
- [ ] T038 [P] [US1] Implement adapter registration dispatcher in `worktree-skill/install/register.sh`
- [ ] T039 [P] [US1] Implement post-install verification script in `worktree-skill/install/verify.sh`
- [ ] T040 [US5] Document install profiles and failure modes in `worktree-skill/docs/quickstart.md`

---

## Phase 8: Examples and Quickstart

**Goal**: Prove the 5-10 minute adoption story for new and existing projects.

- [ ] T041 [US1] Write the greenfield quickstart flow in `worktree-skill/examples/greenfield/README.md`
- [ ] T042 [P] [US5] Write the existing-project migration example in `worktree-skill/examples/existing-project/README.md`
- [ ] T043 [P] [US5] Finalize the standalone quickstart in `worktree-skill/docs/quickstart.md`
- [ ] T044 [US5] Finalize migration guidance from the current in-repo assets in `worktree-skill/docs/migration-from-in-repo.md`

---

## Phase 9: Validation and Acceptance Evidence

**Goal**: Prove that the extracted repo is portable and parity-safe.

- [ ] T045 [US1] Add core smoke validation in `worktree-skill/tests/unit/test_worktree_ready.sh`
- [ ] T046 [P] [US1] Add deterministic create validation in `worktree-skill/tests/unit/test_worktree_phase_a.sh`
- [ ] T047 [P] [US1] Add topology registry validation in `worktree-skill/tests/unit/test_git_topology_registry.sh`
- [ ] T048 [P] [US2] Add Codex adapter discovery validation in `worktree-skill/tests/integration/test_codex_adapter.sh`
- [ ] T049 [P] [US3] Add OpenCode adapter discovery validation in `worktree-skill/tests/integration/test_opencode_adapter.sh`
- [ ] T050 [P] [US4] Add Speckit coexistence validation in `worktree-skill/tests/integration/test_speckit_bridge.sh`
- [ ] T051 [US5] Record portable repo acceptance evidence in `worktree-skill/docs/acceptance-evidence.md`

---

## Phase 10: Rollout and Follow-Up Backlog

**Goal**: Prepare the first release and capture follow-up work without hiding scope.

- [ ] T052 [US5] Finalize release notes template and semantic versioning guidance in `worktree-skill/docs/release-policy.md`
- [ ] T053 [P] [US5] Publish supported integration surfaces and support levels in `worktree-skill/docs/compatibility-matrix.md`
- [ ] T054 [P] [US5] Create a follow-up backlog for deferred adapters or optional integrations in `worktree-skill/docs/follow-up-backlog.md`
- [ ] T055 [US5] Update `specs/011-worktree-skill-extraction/tasks.md` with completion state as rollout artifacts land

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1** must complete before any runtime extraction starts.
- **Phase 2** depends on Phase 1 and locks portability boundaries.
- **Phase 3** depends on Phase 2 and creates the standalone repo scaffold.
- **Phase 4** depends on Phase 3 because core artifacts need a stable destination.
- **Phase 5** and **Phase 6** depend on Phase 4 and can proceed in parallel where files do not overlap.
- **Phase 7** depends on Phases 4-6 because install scripts need the real artifact layout.
- **Phase 8** depends on Phases 5-7.
- **Phase 9** depends on Phases 4-8.
- **Phase 10** depends on acceptance evidence from Phase 9.

### User Story Dependencies

- **US1** is the first MVP path because Claude Code plus portable core proves the extraction works at all.
- **US2** depends on the same core from US1 but not on OpenCode.
- **US3** depends on the same core from US1 but not on Codex.
- **US4** depends on portable core and docs scaffolding.
- **US5** spans inventory, migration, release, and acceptance evidence.

### Parallel Opportunities

- Inventory submaps in Phase 1 can run in parallel.
- Adapter README and registration tasks in Phase 5 can run in parallel once core is stable.
- Speckit bridge docs in Phase 6 can run in parallel.
- Validation tasks in Phase 9 can run in parallel after examples and install scripts stabilize.

## Implementation Strategy

### MVP First

1. Complete Phases 1-4.
2. Deliver Claude Code adapter from Phase 5.
3. Deliver install and quickstart minimum from Phases 7-8.
4. Validate with core + Claude path in Phase 9.

### Incremental Delivery

1. Portable core and repo skeleton
2. Claude Code adapter
3. Codex CLI adapter
4. OpenCode adapter
5. Speckit bridge
6. Acceptance evidence and first release
