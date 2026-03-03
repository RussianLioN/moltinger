# Tasks: RCA Skill Enhancements

**Input**: Design documents from `/specs/001-rca-skill-upgrades/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Manual verification in new Claude Code session (no automated tests requested)

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1-US5)
- Include exact file paths in descriptions

---

## Phase 0: Planning (Executor Assignment) ✅ COMPLETE

**Purpose**: Prepare for implementation by analyzing requirements, creating necessary agents, and assigning executors.

- [X] P001 Analyze all tasks and identify required agent types and capabilities
- [X] P002 Create missing agents using meta-agent-v3 (if needed), then ask user restart
- [X] P003 Assign executors to all tasks: MAIN (trivial only), existing agents (100% match), or specific agent names
- [X] P004 Resolve research tasks: simple (solve with tools now), complex (create prompts in research/)

**Executor Summary**:
- **MAIN**: Trivial tasks only (directory creation)
- **skill-builder-v2**: SKILL.md enhancements, template creation
- **consilium-bash-master**: Bash scripts (context-collector.sh, rca-index.sh)
- **technical-writer**: Documentation updates

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create directory structure and initialize skill enhancement

- [X] T001 [EXECUTOR: MAIN] Create templates directory at `.claude/skills/rca-5-whys/templates/` → Artifacts: [templates/](.claude/skills/rca-5-whys/templates/)
- [X] T002 [EXECUTOR: MAIN] Create lib directory at `.claude/skills/rca-5-whys/lib/` → Artifacts: [lib/](.claude/skills/rca-5-whys/lib/)
- [X] T003 [EXECUTOR: MAIN] Create tests/rca directory for generated regression tests → Artifacts: [tests/rca/](tests/rca/)
- [X] T004 [P] [EXECUTOR: MAIN] Initialize docs/rca/INDEX.md with empty registry structure → Artifacts: [INDEX.md](docs/rca/INDEX.md)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core skill enhancements that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [EXECUTOR: skill-builder-v2] Update SKILL.md header with new allowed-tools → Artifacts: [SKILL.md](.claude/skills/rca-5-whys/SKILL.md)
- [X] T006 [EXECUTOR: skill-builder-v2] Add Auto-Context Collection section to SKILL.md → Artifacts: [SKILL.md](.claude/skills/rca-5-whys/SKILL.md)
- [X] T007 [EXECUTOR: consilium-bash-master] Create context-collector.sh in `.claude/skills/rca-5-whys/lib/` → Artifacts: [context-collector.sh](.claude/skills/rca-5-whys/lib/context-collector.sh)
- [X] T008 [EXECUTOR: skill-builder-v2] Add Domain Templates section to SKILL.md → Artifacts: [SKILL.md](.claude/skills/rca-5-whys/SKILL.md)
- [X] T009 [EXECUTOR: skill-builder-v2] Add RCA Index section to SKILL.md → Artifacts: [SKILL.md](.claude/skills/rca-5-whys/SKILL.md)
- [X] T010 [EXECUTOR: skill-builder-v2] Add Chain-of-Thought section to SKILL.md → Artifacts: [SKILL.md](.claude/skills/rca-5-whys/SKILL.md)
- [X] T011 [EXECUTOR: skill-builder-v2] Add Test Generation section to SKILL.md → Artifacts: [SKILL.md](.claude/skills/rca-5-whys/SKILL.md)

**Checkpoint**: Foundation ready - user story implementation can begin in parallel

---

## Phase 3: User Story 1 - Auto-Context Collection (Priority: P1) 🎯 MVP

**Goal**: Автоматический сбор контекста (git, docker, system) при любой ошибке

**Independent Test**:
1. Спровоцировать ошибку `cat /nonexistent`
2. Проверить, что RCA содержит собранный контекст (pwd, git branch, disk, memory)
3. Проверить, что контекст включён в отчёт

### Implementation for User Story 1

- [X] T012 [US1] Implement base context collection (timestamp, pwd, shell) in `.claude/skills/rca-5-whys/lib/context-collector.sh` → Artifacts: [context-collector.sh](.claude/skills/rca-5-whys/lib/context-collector.sh)
- [X] T013 [P] [US1] Add git context collection (branch, status, recent commits) in context-collector.sh
- [X] T014 [P] [US1] Add docker context collection (version, containers, networks) in context-collector.sh
- [X] T015 [P] [US1] Add system context collection (disk, memory) in context-collector.sh
- [X] T016 [US1] Add error type detection (docker, cicd, shell, data-loss, generic) in context-collector.sh
- [X] T017 [US1] Integrate context-collector.sh into SKILL.md workflow
- [X] T018 [US1] Update docs/rca/TEMPLATE.md with Context section → Artifacts: [TEMPLATE.md](docs/rca/TEMPLATE.md)

**Checkpoint**: Auto-Context Collection fully functional - errors now include environment context

---

## Phase 4: User Story 2 - Domain-Specific Templates (Priority: P1)

**Goal**: Автоматический выбор шаблона в зависимости от типа ошибки

**Independent Test**:
1. Спровоцировать Docker-ошибку
2. Проверить, что использовался Docker template с Layer Analysis
3. Спровоцировать CI/CD-ошибку
4. Проверить, что использовался CI/CD template

### Implementation for User Story 2

- [X] T019 [P] [US2] Create Docker template at `.claude/skills/rca-5-whys/templates/docker.md` → Artifacts: [docker.md](.claude/skills/rca-5-whys/templates/docker.md)
- [X] T020 [P] [US2] Create CI/CD template at `.claude/skills/rca-5-whys/templates/cicd.md` → Artifacts: [cicd.md](.claude/skills/rca-5-whys/templates/cicd.md)
- [X] T021 [P] [US2] Create Data Loss template at `.claude/skills/rca-5-whys/templates/data-loss.md` → Artifacts: [data-loss.md](.claude/skills/rca-5-whys/templates/data-loss.md)
- [X] T022 [P] [US2] Create Generic template at `.claude/skills/rca-5-whys/templates/generic.md` → Artifacts: [generic.md](.claude/skills/rca-5-whys/templates/generic.md)
- [X] T023 [US2] Add template selection logic to SKILL.md based on error type
- [X] T024 [US2] Add template reference section to SKILL.md

**Checkpoint**: Domain-Specific Templates functional - errors use appropriate analysis patterns

---

## Phase 5: User Story 3 - RCA Hub Architecture (Priority: P2)

**Goal**: Индекс всех RCA с метриками и трендами

**Independent Test**:
1. Создать несколько RCA отчётов
2. Открыть docs/rca/INDEX.md
3. Проверить, что все RCA отражены с метаданными

### Implementation for User Story 3

- [X] T025 [US3] Create rca-index.sh script at `.claude/skills/rca-5-whys/lib/rca-index.sh` → Artifacts: [rca-index.sh](.claude/skills/rca-5-whys/lib/rca-index.sh)
- [X] T026 [US3] Implement `update` command in rca-index.sh (add new RCA entry)
- [X] T027 [US3] Implement `validate` command in rca-index.sh (check consistency)
- [X] T028 [US3] Implement `next-id` command in rca-index.sh (get RCA-NNN)
- [X] T029 [US3] Implement statistics calculation in rca-index.sh (by category, severity)
- [X] T030 [US3] Implement pattern detection in rca-index.sh (3+ RCA in category)
- [X] T031 [US3] Update docs/rca/INDEX.md with full structure per contracts/rca-index-schema.md → Artifacts: [INDEX.md](docs/rca/INDEX.md)
- [X] T032 [US3] Integrate rca-index.sh into SKILL.md workflow

**Checkpoint**: RCA Hub Architecture functional - all RCA tracked with analytics

---

## Phase 6: User Story 4 - Chain-of-Thought Pattern (Priority: P2)

**Goal**: Структурированный процесс RCA с гипотезами и валидацией

**Independent Test**:
1. Спровоцировать нетривиальную ошибку
2. Проверить, что RCA включает: Error Classification → Hypothesis → 5 Whys → Validation
3. Проверить confidence levels у гипотез

### Implementation for User Story 4

- [X] T033 [US4] Add Error Classification section to SKILL.md (type, confidence, context quality)
- [X] T034 [US4] Add Hypothesis Generation section to SKILL.md (3 hypotheses with confidence)
- [X] T035 [US4] Add 5 Whys with Evidence format to SKILL.md
- [X] T036 [US4] Add Root Cause Validation section to SKILL.md (actionable, systemic, preventable)
- [X] T037 [US4] Update docs/rca/TEMPLATE.md with CoT structure → Artifacts: [TEMPLATE.md](docs/rca/TEMPLATE.md)

**Checkpoint**: Chain-of-Thought Pattern functional - RCA has structured reasoning

---

## Phase 7: User Story 5 - Test Generation (Priority: P3)

**Goal**: Автоматическое создание failing test для code-ошибок

**Independent Test**:
1. Провести RCA для бага в коде
2. Проверить, что предложено создать failing test
3. Создать тест, запустить — должен падать
4. Исправить баг, запустить — должен проходить

### Implementation for User Story 5

- [X] T038 [US5] Add Test Generation section to SKILL.md (for code errors only)
- [X] T039 [US5] Create test template structure in SKILL.md (Given/When/Then)
- [X] T040 [US5] Add test file naming convention to SKILL.md (tests/rca/RCA-NNN.test.ts)
- [X] T041 [US5] Update docs/rca/TEMPLATE.md with optional Test section → Artifacts: [TEMPLATE.md](docs/rca/TEMPLATE.md)

**Checkpoint**: Test Generation functional - code errors can generate regression tests

---

## Phase 8: Integration & Polish

**Purpose**: Cross-cutting concerns and final integration

- [X] T042 Update `.claude/skills/systematic-debugging/SKILL.md` with RCA integration reference
- [X] T043 [P] Update docs/rca/TEMPLATE.md with all new sections (Context, CoT, Test) → Artifacts: [TEMPLATE.md](docs/rca/TEMPLATE.md)
- [ ] T044 Run quickstart.md validation - test all user stories in new session
- [X] T045 Update CLAUDE.md RCA section to reference enhanced skill
- [X] T046 Create sample RCA report using all new features in docs/rca/ → Artifacts: [2026-03-03-sample-enhanced-rca.md](docs/rca/2026-03-03-sample-enhanced-rca.md)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 and US2 (both P1) can proceed in parallel
  - US3 and US4 (both P2) can proceed in parallel
  - US5 (P3) can proceed independently
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

```
Phase 2 (Foundational)
        │
        ├──► US1 (Auto-Context) ──┐
        │                         │
        ├──► US2 (Templates) ─────┼──► Phase 8 (Integration)
        │                         │
        ├──► US3 (Hub/Index) ─────┤
        │                         │
        ├──► US4 (CoT Pattern) ───┤
        │                         │
        └──► US5 (Test Gen) ──────┘
```

### Parallel Opportunities

| Phase | Parallel Tasks |
|-------|----------------|
| Phase 1 | T001, T002, T003, T004 (all directory creation) |
| Phase 2 | T006-T011 (SKILL.md sections - different sections) |
| Phase 3 | T013, T014, T015 (different context types) |
| Phase 4 | T019, T020, T021, T022 (different template files) |
| Phase 5 | T026, T027, T028 (different commands in same file - sequential) |
| Phase 8 | T043, T046 (different files) |

---

## Parallel Example: Phase 4 (Templates)

```bash
# Launch all template creation in parallel:
Task: "Create Docker template at .claude/skills/rca-5-whys/templates/docker.md"
Task: "Create CI/CD template at .claude/skills/rca-5-whys/templates/cicd.md"
Task: "Create Data Loss template at .claude/skills/rca-5-whys/templates/data-loss.md"
Task: "Create Generic template at .claude/skills/rca-5-whys/templates/generic.md"
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1 (Auto-Context)
4. Complete Phase 4: User Story 2 (Templates)
5. **STOP and VALIDATE**: Test US1 + US2 in new session
6. Deploy - this is a working MVP!

### Incremental Delivery

| Increment | Stories | Value Delivered |
|-----------|---------|-----------------|
| MVP | US1 + US2 | Auto-context + Domain templates |
| v1.1 | +US3 +US4 | Analytics + Structured reasoning |
| v1.2 | +US5 | Regression test generation |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- Each user story independently testable
- Commit after each task or logical group
- Test in NEW Claude Code session to verify skill works
- Sandbox restrictions: Some context collection may fail - handle gracefully
