# Tasks: Clawdiy Agent Platform

**Input**: Design documents from `/specs/001-clawdiy-agent-platform/`
**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/`

**Tests**: Validation scripts and smoke coverage are included because the spec requires independent testability, rollback proof, and operator-visible acceptance gates.

**Organization**: Tasks are grouped by user story so each delivery slice can be implemented, verified, and rolled out independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g. `US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## Phase 0: Planning (Executor Assignment)

**Purpose**: Prepare implementation staffing, research handling, and execution order before touching runtime code.

- [ ] P001 Analyze all tasks in `specs/001-clawdiy-agent-platform/tasks.md` and identify required agent types and capabilities
- [ ] P002 Create any missing delivery agents via meta-agent flow and register them for this feature branch/worktree
- [ ] P003 Assign executors to all implementation tasks in `specs/001-clawdiy-agent-platform/tasks.md`
- [ ] P004 Resolve any new research blockers in `specs/001-clawdiy-agent-platform/research.md` and create narrow clarify prompts only if a true scope blocker appears

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the Clawdiy-specific file skeletons and operator documentation entry points.

- [ ] T001 Create the Clawdiy compose stack skeleton in `docker-compose.clawdiy.yml`
- [ ] T002 [P] Create the Clawdiy runtime and fleet config skeletons in `config/clawdiy/openclaw.json`, `config/fleet/agents-registry.json`, and `config/fleet/policy.json`
- [ ] T003 [P] Add Clawdiy secret inventory placeholders and deployment env mapping notes in `.github/workflows/deploy.yml` and `docs/SECRETS-MANAGEMENT.md`
- [ ] T004 [P] Create the Clawdiy runbook directory and initial documents in `docs/runbooks/clawdiy-deploy.md`, `docs/runbooks/clawdiy-repeat-auth.md`, `docs/runbooks/clawdiy-rollback.md`, and `docs/runbooks/fleet-handoff-incident.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the shared deployment, validation, monitoring, and backup primitives that every user story depends on.

**⚠️ CRITICAL**: No user story work should be considered done until this phase is complete.

- [ ] T005 Extend target-aware validation, duplicate identity checks, and fleet config parsing in `scripts/preflight-check.sh`
- [ ] T006 [P] Extend multi-target deploy and rollback orchestration for Clawdiy in `scripts/deploy.sh`
- [ ] T007 [P] Create isolated GitOps deployment workflow for Clawdiy in `.github/workflows/deploy-clawdiy.yml`
- [ ] T008 [P] Add fleet registry and policy static validation in `tests/static/test_fleet_registry.sh` and `tests/static/test_config_validation.sh`
- [ ] T009 [P] Add per-agent scrape targets, labels, and alerts in `config/prometheus/prometheus.yml`, `config/prometheus/alert-rules.yml`, and `config/alertmanager/alertmanager.yml`
- [ ] T010 [P] Extend backup inventory and restore hooks for Clawdiy config/state/audit data in `config/backup/backup.conf` and `scripts/backup-moltis-enhanced.sh`

**Checkpoint**: Deployment tooling, validation, monitoring, and backup primitives are ready for feature work.

---

## Phase 3: User Story 1 - Permanent Second Agent Deployment (Priority: P1) 🎯 MVP

**Goal**: Deploy Clawdiy as an independently managed permanent runtime beside Moltinger.

**Independent Test**: Clawdiy can be deployed on `clawdiy.ainetic.tech`, restarted independently, and removed or disabled without affecting Moltinger availability.

### Validation for User Story 1

- [ ] T011 [P] [US1] Create same-host deployment smoke coverage in `tests/live_external/test_clawdiy_deploy_smoke.sh`

### Implementation for User Story 1

- [ ] T012 [P] [US1] Add Traefik routing, healthchecks, networks, and distinct persistent mounts in `docker-compose.clawdiy.yml`
- [ ] T013 [P] [US1] Finalize Clawdiy runtime identity, endpoints, and state paths in `config/clawdiy/openclaw.json`
- [ ] T014 [US1] Wire remote sync and deploy steps for the Clawdiy stack in `.github/workflows/deploy-clawdiy.yml` and `scripts/deploy.sh`
- [ ] T015 [US1] Implement `same-host` and `restart-isolation` verification stages in `scripts/clawdiy-smoke.sh`
- [ ] T016 [US1] Document deploy, restart, disable, and ownership procedures in `docs/runbooks/clawdiy-deploy.md` and `docs/INFRASTRUCTURE.md`

**Checkpoint**: Clawdiy exists as a separate long-lived runtime and can be operated without mutating Moltinger state.

---

## Phase 4: User Story 2 - Traceable Inter-Agent Task Handoff (Priority: P1)

**Goal**: Make Moltinger, Clawdiy, and future agents exchange work through an explicit, traceable handoff contract.

**Independent Test**: A handoff between Moltinger and Clawdiy produces correlation identifiers, acknowledgements, and a terminal status or explicit escalation.

### Validation for User Story 2

- [ ] T017 [P] [US2] Create handoff accept/reject/timeout/idempotency coverage in `tests/integration_local/test_clawdiy_handoff.sh`

### Implementation for User Story 2

- [ ] T018 [P] [US2] Populate canonical Moltinger and Clawdiy registry entries with capability metadata in `config/fleet/agents-registry.json`
- [ ] T019 [P] [US2] Implement caller allowlists and capability authorization rules in `config/fleet/policy.json`
- [ ] T020 [US2] Configure internal handoff endpoints, correlation metadata, and acknowledgement callbacks in `config/moltis.toml` and `config/clawdiy/openclaw.json`
- [ ] T021 [US2] Implement `handoff` smoke stages and audit artifact assertions in `scripts/clawdiy-smoke.sh`
- [ ] T022 [US2] Document operator response for rejected, timed-out, duplicate, and late handoffs in `docs/runbooks/fleet-handoff-incident.md`

**Checkpoint**: Cross-agent work exchange is explicit, auditable, and non-silent on failure.

---

## Phase 5: User Story 3 - Separate Auth and Trust Lifecycle (Priority: P1)

**Goal**: Isolate Telegram, human, service, and provider authentication per permanent agent and fail closed on auth degradation.

**Independent Test**: Clawdiy credentials can be rotated or re-authorized without changing Moltinger auth state, and missing scope or trust material produces visible failure instead of degraded success.

### Validation for User Story 3

- [ ] T023 [P] [US3] Create auth-boundary regression coverage for missing tokens, bad scopes, and cross-agent secret reuse in `tests/security_api/test_clawdiy_auth_boundaries.sh`

### Implementation for User Story 3

- [ ] T024 [P] [US3] Add distinct Clawdiy secret refs and runtime env rendering rules in `.github/workflows/deploy-clawdiy.yml` and `docs/SECRETS-MANAGEMENT.md`
- [ ] T025 [P] [US3] Configure service bearer auth, Telegram token isolation, and provider auth profiles in `config/clawdiy/openclaw.json`, `config/moltis.toml`, and `config/fleet/policy.json`
- [ ] T026 [P] [US3] Implement Telegram and provider repeat-auth validation in `scripts/clawdiy-auth-check.sh`
- [ ] T027 [US3] Extend auth failure smoke coverage and fail-closed escalation checks in `scripts/preflight-check.sh` and `scripts/clawdiy-smoke.sh`
- [ ] T028 [US3] Document Clawdiy credential rotation and repeat-auth procedures in `docs/runbooks/clawdiy-repeat-auth.md`

**Checkpoint**: Auth state is isolated per agent, and degraded auth paths are explicitly surfaced and contained.

---

## Phase 6: User Story 4 - Observable Recovery and Rollback (Priority: P2)

**Goal**: Give Clawdiy production-grade health ownership, backup/restore coverage, and rollback safety without losing audit evidence.

**Independent Test**: Operators can distinguish Moltinger and Clawdiy telemetry, restore Clawdiy from backup, and roll back Clawdiy without harming Moltinger or losing handoff evidence.

### Validation for User Story 4

- [ ] T029 [P] [US4] Create rollback and restore resilience coverage in `tests/resilience/test_clawdiy_rollback.sh`

### Implementation for User Story 4

- [ ] T030 [P] [US4] Extend per-agent health, log correlation, and evidence checks in `scripts/health-monitor.sh` and `scripts/clawdiy-smoke.sh`
- [ ] T031 [P] [US4] Extend backup scope for Clawdiy config, state, and audit artifacts in `scripts/backup-moltis-enhanced.sh` and `config/backup/backup.conf`
- [ ] T032 [P] [US4] Extend Clawdiy rollback and restore validation in `.github/workflows/rollback-drill.yml` and `.github/workflows/deploy-clawdiy.yml`
- [ ] T033 [US4] Preserve audit evidence during Clawdiy rollback and disable paths in `scripts/deploy.sh` and `scripts/clawdiy-smoke.sh`
- [ ] T034 [US4] Document single-agent disaster recovery and rollback procedures in `docs/disaster-recovery.md` and `docs/runbooks/clawdiy-rollback.md`

**Checkpoint**: Clawdiy can be observed, restored, and rolled back as a separate production service with preserved evidence.

---

## Phase 7: User Story 5 - Future Fleet Expansion Without Topology Rewrite (Priority: P2)

**Goal**: Keep the same identity, discovery, and handoff model valid for new permanent roles and future Clawdiy extraction to another node or VM.

**Independent Test**: The platform contract stays stable when adding more agent roles or moving Clawdiy off the shared host, with only endpoint placement changing.

### Validation for User Story 5

- [ ] T035 [P] [US5] Create extraction-readiness validation coverage in `tests/integration_local/test_clawdiy_extraction_readiness.sh`

### Implementation for User Story 5

- [ ] T036 [P] [US5] Extend future-role and remote-node friendly registry examples in `config/fleet/agents-registry.json` and `config/fleet/policy.json`
- [ ] T037 [P] [US5] Implement `extraction-readiness` verification in `scripts/clawdiy-smoke.sh`
- [ ] T038 [US5] Document future permanent-agent onboarding and Clawdiy node extraction path in `docs/plans/agent-factory-lifecycle.md` and `docs/GIT-TOPOLOGY-REGISTRY.md`
- [ ] T039 [US5] Document same-host versus remote-node routing, trust, and discovery posture in `docs/INFRASTRUCTURE.md`

**Checkpoint**: The platform contract scales beyond the first two agents without topology rewrite.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Reconcile documentation, test lanes, and hardening across all user stories.

- [ ] T040 [P] Reconcile operator docs and quick references in `docs/deployment-strategy.md`, `docs/QUICK-REFERENCE.md`, and `specs/001-clawdiy-agent-platform/quickstart.md`
- [ ] T041 [P] Wire Clawdiy validation into umbrella test runners in `tests/run.sh`, `tests/run_integration.sh`, and `tests/run_security.sh`
- [ ] T042 [P] Perform final security hardening across `docker-compose.clawdiy.yml`, `config/fleet/policy.json`, and `scripts/preflight-check.sh`
- [ ] T043 Run the quickstart validation flow from `specs/001-clawdiy-agent-platform/quickstart.md` and capture rollout notes in `SESSION_SUMMARY.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup** has no prerequisites and can start immediately.
- **Phase 2: Foundational** depends on Phase 1 and blocks all user-story delivery.
- **Phase 3: US1** depends on Phase 2 and is the MVP slice.
- **Phase 4: US2** depends on Phase 2 and a deployed Clawdiy runtime from US1.
- **Phase 5: US3** depends on Phase 2 and should complete after the US1 runtime boundary and US2 internal service path exist.
- **Phase 6: US4** depends on US1 through US3 because recovery logic must cover the real runtime, handoff, and auth boundaries.
- **Phase 7: US5** depends on US1 through US4 because topology-extraction readiness must be validated against the finished contract.
- **Phase 8: Polish** depends on the completion of all desired user stories.

### User Story Dependencies

- **US1 (P1)**: Starts after foundational work; no dependency on later stories.
- **US2 (P1)**: Requires US1 because there must be a deployed Clawdiy recipient to validate handoff behavior.
- **US3 (P1)**: Requires the US1 runtime boundary and the US2 service-to-service path for meaningful auth isolation checks.
- **US4 (P2)**: Requires US1, US2, and US3 because backup, restore, and rollback must preserve runtime, handoff, and auth evidence together.
- **US5 (P2)**: Requires the finished runtime, protocol, and recovery model so the extraction path is based on the final contract rather than placeholders.

### Within Each User Story

- Validation scripts should be added before the corresponding rollout gate is considered complete.
- Registry, policy, and runtime config changes should land before smoke orchestration and workflow wiring.
- Deployment and routing changes should land before operator runbooks are finalized.
- A story is complete only when its independent test passes and the related runbook is usable.

### Parallel Opportunities

- Setup tasks `T002` through `T004` can run in parallel after `T001`.
- Foundational tasks `T006` through `T010` can run in parallel after `T005`.
- In US1, `T012` and `T013` can run in parallel before `T014`.
- In US2, `T018` and `T019` can run in parallel before `T020`.
- In US3, `T024`, `T025`, and `T026` can run in parallel before `T027`.
- In US4, `T030`, `T031`, and `T032` can run in parallel before `T033`.
- In US5, `T036` and `T037` can run in parallel before `T038`.
- Polish tasks `T040` through `T042` can run in parallel before `T043`.

---

## Parallel Example: User Story 1

```bash
Task: "Add Traefik routing, healthchecks, networks, and distinct persistent mounts in docker-compose.clawdiy.yml"
Task: "Finalize Clawdiy runtime identity, endpoints, and state paths in config/clawdiy/openclaw.json"
```

## Parallel Example: User Story 2

```bash
Task: "Populate canonical Moltinger and Clawdiy registry entries with capability metadata in config/fleet/agents-registry.json"
Task: "Implement caller allowlists and capability authorization rules in config/fleet/policy.json"
```

## Parallel Example: User Story 3

```bash
Task: "Add distinct Clawdiy secret refs and runtime env rendering rules in .github/workflows/deploy-clawdiy.yml and docs/SECRETS-MANAGEMENT.md"
Task: "Implement Telegram and provider repeat-auth validation in scripts/clawdiy-auth-check.sh"
```

## Parallel Example: User Story 4

```bash
Task: "Extend per-agent health, log correlation, and evidence checks in scripts/health-monitor.sh and scripts/clawdiy-smoke.sh"
Task: "Extend Clawdiy rollback and restore validation in .github/workflows/rollback-drill.yml and .github/workflows/deploy-clawdiy.yml"
```

## Parallel Example: User Story 5

```bash
Task: "Extend future-role and remote-node friendly registry examples in config/fleet/agents-registry.json and config/fleet/policy.json"
Task: "Implement extraction-readiness verification in scripts/clawdiy-smoke.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational.
3. Complete Phase 3: User Story 1.
4. Validate same-host deploy, restart isolation, and Moltinger non-regression.
5. Stop and review before enabling inter-agent handoff.

### Incremental Delivery

1. Finish Setup and Foundational to make the repo deployment-ready for Clawdiy assets.
2. Deliver US1 to establish the second permanent runtime.
3. Deliver US2 to make cross-agent handoff explicit and observable.
4. Deliver US3 to isolate auth and repeat-auth procedures.
5. Deliver US4 to harden backup, restore, rollback, and telemetry.
6. Deliver US5 to prove topology portability for future fleet growth.

### Suggested MVP Scope

- **MVP**: Phase 1, Phase 2, and Phase 3 (US1) only.
- **First production-ready control-plane increment**: US1 + US2 + US3.
- **Full feature completion**: US1 through US5 plus Phase 8 polish.
