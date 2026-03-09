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

- [X] P001 [EXECUTOR: MAIN] [SEQUENTIAL] Analyze all tasks in `specs/001-clawdiy-agent-platform/tasks.md` and identify required agent types and capabilities
- [X] P002 [EXECUTOR: MAIN] [SEQUENTIAL] Create any missing delivery agents via meta-agent flow and register them for this feature branch/worktree
- [X] P003 [EXECUTOR: MAIN] [SEQUENTIAL] Assign executors to all implementation tasks in `specs/001-clawdiy-agent-platform/tasks.md`
- [X] P004 [EXECUTOR: MAIN] [SEQUENTIAL] Resolve any new research blockers in `specs/001-clawdiy-agent-platform/research.md` and create narrow clarify prompts only if a true scope blocker appears

**Required Capabilities**

- `deployment-engineer`: compose topology, state boundaries, deploy/rollback orchestration, GitHub Actions rollout wiring
- `bash-master`: `preflight`, `smoke`, `auth-check`, and operational shell flows
- `cicd-architect`: isolated deploy workflow structure and rollout gates
- `traefik-expert`: subdomain routing, labels, and ingress isolation for `clawdiy.ainetic.tech`
- `prometheus-expert`: scrape targets, alert rules, and per-agent observability labels
- `sre-engineer`: health ownership, alert semantics, and operational diagnostics
- `backup-specialist`: backup/restore scope, rollback evidence retention, and disaster recovery drills
- `security-expert`: service auth, allowlists, fail-closed behavior, and secret isolation
- `toml-specialist`: Moltinger-side handoff and auth config in `config/moltis.toml`
- `gitops-guardian`: registry/policy lifecycle, topology invariants, and Git-managed control-plane posture
- `integration-tester`: static, integration, resilience, and live validation scripts
- `technical-writer`: deploy/runbook/disaster-recovery/operator docs

**Agent Creation Result**

- No new repo-local agents are required for this feature.
- Existing profiles in `.claude/agents/` already cover the needed delivery roles: `deployment-engineer`, `bash-master`, `cicd-architect`, `traefik-expert`, `prometheus-expert`, `sre-engineer`, `backup-specialist`, `security-expert`, `toml-specialist`, `gitops-guardian`, `integration-tester`, and `technical-writer`.
- `P002` is therefore closed as `not needed`, with no restart gate required before implementation.

**Research Resolution**

- `research.md`, `plan.md`, and `protocol.md` already resolve the planning-time blockers for transport, Telegram mode, registry placement, auth boundary, and Codex OAuth criticality.
- No narrow `speckit.clarify` prompt is needed at this stage.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the Clawdiy-specific file skeletons and operator documentation entry points.

- [X] T001 [EXECUTOR: deployment-engineer] [SEQUENTIAL] Create the Clawdiy compose stack skeleton in `docker-compose.clawdiy.yml`
  → Artifacts: [docker-compose.clawdiy.yml](/Users/rl/coding/moltinger-openclaw-control-plane/docker-compose.clawdiy.yml)
- [X] T002 [P] [EXECUTOR: deployment-engineer] [PARALLEL-GROUP-SETUP-A] Create the Clawdiy runtime and fleet config skeletons in `config/clawdiy/openclaw.json`, `config/fleet/agents-registry.json`, and `config/fleet/policy.json`
  → Artifacts: [openclaw.json](/Users/rl/coding/moltinger-openclaw-control-plane/config/clawdiy/openclaw.json), [agents-registry.json](/Users/rl/coding/moltinger-openclaw-control-plane/config/fleet/agents-registry.json), [policy.json](/Users/rl/coding/moltinger-openclaw-control-plane/config/fleet/policy.json)
- [X] T003 [P] [EXECUTOR: deployment-engineer] [PARALLEL-GROUP-SETUP-A] Add Clawdiy secret inventory placeholders and deployment env mapping notes in `.github/workflows/deploy.yml` and `docs/SECRETS-MANAGEMENT.md`
  → Artifacts: [deploy.yml](/Users/rl/coding/moltinger-openclaw-control-plane/.github/workflows/deploy.yml), [SECRETS-MANAGEMENT.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/SECRETS-MANAGEMENT.md)
- [X] T004 [P] [EXECUTOR: technical-writer] [PARALLEL-GROUP-SETUP-A] Create the Clawdiy runbook directory and initial documents in `docs/runbooks/clawdiy-deploy.md`, `docs/runbooks/clawdiy-repeat-auth.md`, `docs/runbooks/clawdiy-rollback.md`, and `docs/runbooks/fleet-handoff-incident.md`
  → Artifacts: [clawdiy-deploy.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-deploy.md), [clawdiy-repeat-auth.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-repeat-auth.md), [clawdiy-rollback.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-rollback.md), [fleet-handoff-incident.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/fleet-handoff-incident.md)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the shared deployment, validation, monitoring, and backup primitives that every user story depends on.

**⚠️ CRITICAL**: No user story work should be considered done until this phase is complete.

- [X] T005 [EXECUTOR: bash-master] [SEQUENTIAL] Extend target-aware validation, duplicate identity checks, and fleet config parsing in `scripts/preflight-check.sh`
  → Artifacts: [preflight-check.sh](/Users/rl/coding/moltinger-openclaw-control-plane/scripts/preflight-check.sh), [scripts.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/001-docker-deploy-improvements/contracts/scripts.md), [json-output.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/json-output.md)
- [X] T006 [P] [EXECUTOR: deployment-engineer] [PARALLEL-GROUP-FOUNDATION-A] Extend multi-target deploy and rollback orchestration for Clawdiy in `scripts/deploy.sh`
  → Artifacts: [deploy.sh](/Users/rl/coding/moltinger-openclaw-control-plane/scripts/deploy.sh), [scripts.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/001-docker-deploy-improvements/contracts/scripts.md), [json-output.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/json-output.md)
- [X] T007 [P] [EXECUTOR: cicd-architect] [PARALLEL-GROUP-FOUNDATION-A] Create isolated GitOps deployment workflow for Clawdiy in `.github/workflows/deploy-clawdiy.yml`
  → Artifacts: [deploy-clawdiy.yml](/Users/rl/coding/moltinger-openclaw-control-plane/.github/workflows/deploy-clawdiy.yml)
- [X] T008 [P] [EXECUTOR: integration-tester] [PARALLEL-GROUP-FOUNDATION-A] Add fleet registry and policy static validation in `tests/static/test_fleet_registry.sh` and `tests/static/test_config_validation.sh`
  → Artifacts: [test_fleet_registry.sh](/Users/rl/coding/moltinger-openclaw-control-plane/tests/static/test_fleet_registry.sh), [test_config_validation.sh](/Users/rl/coding/moltinger-openclaw-control-plane/tests/static/test_config_validation.sh), [run.sh](/Users/rl/coding/moltinger-openclaw-control-plane/tests/run.sh)
- [X] T009 [P] [EXECUTOR: prometheus-expert] [PARALLEL-GROUP-FOUNDATION-A] Add per-agent scrape targets, labels, and alerts in `config/prometheus/prometheus.yml`, `config/prometheus/alert-rules.yml`, and `config/alertmanager/alertmanager.yml`
  → Artifacts: [prometheus.yml](/Users/rl/coding/moltinger-openclaw-control-plane/config/prometheus/prometheus.yml), [alert-rules.yml](/Users/rl/coding/moltinger-openclaw-control-plane/config/prometheus/alert-rules.yml), [alertmanager.yml](/Users/rl/coding/moltinger-openclaw-control-plane/config/alertmanager/alertmanager.yml)
- [X] T010 [P] [EXECUTOR: backup-specialist] [PARALLEL-GROUP-FOUNDATION-A] Extend backup inventory and restore hooks for Clawdiy config/state/audit data in `config/backup/backup.conf` and `scripts/backup-moltis-enhanced.sh`
  → Artifacts: [backup.conf](/Users/rl/coding/moltinger-openclaw-control-plane/config/backup/backup.conf), [backup-moltis-enhanced.sh](/Users/rl/coding/moltinger-openclaw-control-plane/scripts/backup-moltis-enhanced.sh)

**Checkpoint**: Deployment tooling, validation, monitoring, and backup primitives are ready for feature work.

---

## Phase 3: User Story 1 - Permanent Second Agent Deployment (Priority: P1) 🎯 MVP

**Goal**: Deploy Clawdiy as an independently managed permanent runtime beside Moltinger.

**Independent Test**: Clawdiy can be deployed on `clawdiy.ainetic.tech`, restarted independently, and removed or disabled without affecting Moltinger availability.

### Validation for User Story 1

- [X] T011 [P] [US1] [EXECUTOR: integration-tester] [PARALLEL-GROUP-US1-A] Create same-host deployment smoke coverage in `tests/live_external/test_clawdiy_deploy_smoke.sh`
  → Artifacts: [test_clawdiy_deploy_smoke.sh](/Users/rl/coding/moltinger-openclaw-control-plane/tests/live_external/test_clawdiy_deploy_smoke.sh), [run.sh](/Users/rl/coding/moltinger-openclaw-control-plane/tests/run.sh)

### Implementation for User Story 1

- [X] T012 [P] [US1] [EXECUTOR: traefik-expert] [PARALLEL-GROUP-US1-A] Add Traefik routing, healthchecks, networks, and distinct persistent mounts in `docker-compose.clawdiy.yml`
  → Artifacts: [docker-compose.clawdiy.yml](/Users/rl/coding/moltinger-openclaw-control-plane/docker-compose.clawdiy.yml)
- [X] T013 [P] [US1] [EXECUTOR: deployment-engineer] [PARALLEL-GROUP-US1-A] Finalize Clawdiy runtime identity, endpoints, and state paths in `config/clawdiy/openclaw.json`
  → Artifacts: [openclaw.json](/Users/rl/coding/moltinger-openclaw-control-plane/config/clawdiy/openclaw.json)
- [X] T014 [US1] [EXECUTOR: deployment-engineer] [SEQUENTIAL] Wire remote sync and deploy steps for the Clawdiy stack in `.github/workflows/deploy-clawdiy.yml` and `scripts/deploy.sh`
  → Artifacts: [deploy-clawdiy.yml](/Users/rl/coding/moltinger-openclaw-control-plane/.github/workflows/deploy-clawdiy.yml), [deploy.sh](/Users/rl/coding/moltinger-openclaw-control-plane/scripts/deploy.sh)
- [X] T015 [US1] [EXECUTOR: bash-master] [SEQUENTIAL] Implement `same-host` and `restart-isolation` verification stages in `scripts/clawdiy-smoke.sh`
  → Artifacts: [clawdiy-smoke.sh](/Users/rl/coding/moltinger-openclaw-control-plane/scripts/clawdiy-smoke.sh)
- [X] T016 [US1] [EXECUTOR: technical-writer] [SEQUENTIAL] Document deploy, restart, disable, and ownership procedures in `docs/runbooks/clawdiy-deploy.md` and `docs/INFRASTRUCTURE.md`
  → Artifacts: [clawdiy-deploy.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-deploy.md), [INFRASTRUCTURE.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/INFRASTRUCTURE.md)

**Checkpoint**: Clawdiy exists as a separate long-lived runtime and can be operated without mutating Moltinger state.

---

## Phase 4: User Story 2 - Traceable Inter-Agent Task Handoff (Priority: P1)

**Goal**: Make Moltinger, Clawdiy, and future agents exchange work through an explicit, traceable handoff contract.

**Independent Test**: A handoff between Moltinger and Clawdiy produces correlation identifiers, acknowledgements, and a terminal status or explicit escalation.

### Validation for User Story 2

- [X] T017 [P] [US2] [EXECUTOR: integration-tester] [PARALLEL-GROUP-US2-A] Create handoff accept/reject/timeout/idempotency coverage in `tests/integration_local/test_clawdiy_handoff.sh`

### Implementation for User Story 2

- [X] T018 [P] [US2] [EXECUTOR: gitops-guardian] [PARALLEL-GROUP-US2-A] Populate canonical Moltinger and Clawdiy registry entries with capability metadata in `config/fleet/agents-registry.json`
- [X] T019 [P] [US2] [EXECUTOR: security-expert] [PARALLEL-GROUP-US2-A] Implement caller allowlists and capability authorization rules in `config/fleet/policy.json`
- [X] T020 [US2] [EXECUTOR: toml-specialist] [SEQUENTIAL] Configure internal handoff endpoints, correlation metadata, and acknowledgement callbacks in `config/moltis.toml` and `config/clawdiy/openclaw.json`
- [X] T021 [US2] [EXECUTOR: bash-master] [SEQUENTIAL] Implement `handoff` smoke stages and audit artifact assertions in `scripts/clawdiy-smoke.sh`
- [X] T022 [US2] [EXECUTOR: technical-writer] [SEQUENTIAL] Document operator response for rejected, timed-out, duplicate, and late handoffs in `docs/runbooks/fleet-handoff-incident.md`

**Checkpoint**: Cross-agent work exchange is explicit, auditable, and non-silent on failure.

---

## Phase 5: User Story 3 - Separate Auth and Trust Lifecycle (Priority: P1)

**Goal**: Isolate Telegram, human, service, and provider authentication per permanent agent and fail closed on auth degradation.

**Independent Test**: Clawdiy credentials can be rotated or re-authorized without changing Moltinger auth state, and missing scope or trust material produces visible failure instead of degraded success.

### Validation for User Story 3

- [X] T023 [P] [US3] [EXECUTOR: integration-tester] [PARALLEL-GROUP-US3-A] Create auth-boundary regression coverage for missing tokens, bad scopes, and cross-agent secret reuse in `tests/security_api/test_clawdiy_auth_boundaries.sh`

### Implementation for User Story 3

- [X] T024 [P] [US3] [EXECUTOR: deployment-engineer] [PARALLEL-GROUP-US3-A] Add distinct Clawdiy secret refs and runtime env rendering rules in `.github/workflows/deploy-clawdiy.yml` and `docs/SECRETS-MANAGEMENT.md`
- [X] T025 [P] [US3] [EXECUTOR: security-expert] [PARALLEL-GROUP-US3-A] Configure service bearer auth, Telegram token isolation, and provider auth profiles in `config/clawdiy/openclaw.json`, `config/moltis.toml`, and `config/fleet/policy.json`
- [X] T026 [P] [US3] [EXECUTOR: bash-master] [PARALLEL-GROUP-US3-A] Implement Telegram and provider repeat-auth validation in `scripts/clawdiy-auth-check.sh`
- [X] T027 [US3] [EXECUTOR: security-expert] [SEQUENTIAL] Extend auth failure smoke coverage and fail-closed escalation checks in `scripts/preflight-check.sh` and `scripts/clawdiy-smoke.sh`
- [X] T028 [US3] [EXECUTOR: technical-writer] [SEQUENTIAL] Document Clawdiy credential rotation and repeat-auth procedures in `docs/runbooks/clawdiy-repeat-auth.md`

**Checkpoint**: Auth state is isolated per agent, and degraded auth paths are explicitly surfaced and contained.

---

## Phase 6: User Story 4 - Observable Recovery and Rollback (Priority: P2)

**Goal**: Give Clawdiy production-grade health ownership, backup/restore coverage, and rollback safety without losing audit evidence.

**Independent Test**: Operators can distinguish Moltinger and Clawdiy telemetry, restore Clawdiy from backup, and roll back Clawdiy without harming Moltinger or losing handoff evidence.

### Validation for User Story 4

- [X] T029 [P] [US4] [EXECUTOR: integration-tester] [PARALLEL-GROUP-US4-A] Create rollback and restore resilience coverage in `tests/resilience/test_clawdiy_rollback.sh`
  → Artifacts: [test_clawdiy_rollback.sh](/Users/rl/coding/moltinger-openclaw-control-plane/tests/resilience/test_clawdiy_rollback.sh), [run.sh](/Users/rl/coding/moltinger-openclaw-control-plane/tests/run.sh)

### Implementation for User Story 4

- [X] T030 [P] [US4] [EXECUTOR: sre-engineer] [PARALLEL-GROUP-US4-A] Extend per-agent health, log correlation, and evidence checks in `scripts/health-monitor.sh` and `scripts/clawdiy-smoke.sh`
  → Artifacts: [health-monitor.sh](/Users/rl/coding/moltinger-openclaw-control-plane/scripts/health-monitor.sh), [clawdiy-smoke.sh](/Users/rl/coding/moltinger-openclaw-control-plane/scripts/clawdiy-smoke.sh)
- [X] T031 [P] [US4] [EXECUTOR: backup-specialist] [PARALLEL-GROUP-US4-A] Extend backup scope for Clawdiy config, state, and audit artifacts in `scripts/backup-moltis-enhanced.sh` and `config/backup/backup.conf`
  → Artifacts: [backup-moltis-enhanced.sh](/Users/rl/coding/moltinger-openclaw-control-plane/scripts/backup-moltis-enhanced.sh), [backup.conf](/Users/rl/coding/moltinger-openclaw-control-plane/config/backup/backup.conf)
- [X] T032 [P] [US4] [EXECUTOR: deployment-engineer] [PARALLEL-GROUP-US4-A] Extend Clawdiy rollback and restore validation in `.github/workflows/rollback-drill.yml` and `.github/workflows/deploy-clawdiy.yml`
  → Artifacts: [rollback-drill.yml](/Users/rl/coding/moltinger-openclaw-control-plane/.github/workflows/rollback-drill.yml), [deploy-clawdiy.yml](/Users/rl/coding/moltinger-openclaw-control-plane/.github/workflows/deploy-clawdiy.yml), [test_config_validation.sh](/Users/rl/coding/moltinger-openclaw-control-plane/tests/static/test_config_validation.sh)
- [X] T033 [US4] [EXECUTOR: bash-master] [SEQUENTIAL] Preserve audit evidence during Clawdiy rollback and disable paths in `scripts/deploy.sh` and `scripts/clawdiy-smoke.sh`
  → Artifacts: [deploy.sh](/Users/rl/coding/moltinger-openclaw-control-plane/scripts/deploy.sh), [clawdiy-smoke.sh](/Users/rl/coding/moltinger-openclaw-control-plane/scripts/clawdiy-smoke.sh)
- [X] T034 [US4] [EXECUTOR: technical-writer] [SEQUENTIAL] Document single-agent disaster recovery and rollback procedures in `docs/disaster-recovery.md` and `docs/runbooks/clawdiy-rollback.md`
  → Artifacts: [disaster-recovery.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/disaster-recovery.md), [clawdiy-rollback.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-rollback.md)

**Checkpoint**: Clawdiy can be observed, restored, and rolled back as a separate production service with preserved evidence.

---

## Phase 7: User Story 5 - Future Fleet Expansion Without Topology Rewrite (Priority: P2)

**Goal**: Keep the same identity, discovery, and handoff model valid for new permanent roles and future Clawdiy extraction to another node or VM.

**Independent Test**: The platform contract stays stable when adding more agent roles or moving Clawdiy off the shared host, with only endpoint placement changing.

### Validation for User Story 5

- [X] T035 [P] [US5] [EXECUTOR: integration-tester] [PARALLEL-GROUP-US5-A] Create extraction-readiness validation coverage in `tests/integration_local/test_clawdiy_extraction_readiness.sh`
  → Artifacts: [test_clawdiy_extraction_readiness.sh](/Users/rl/coding/moltinger-openclaw-control-plane/tests/integration_local/test_clawdiy_extraction_readiness.sh)

### Implementation for User Story 5

- [X] T036 [P] [US5] [EXECUTOR: gitops-guardian] [PARALLEL-GROUP-US5-A] Extend future-role and remote-node friendly registry examples in `config/fleet/agents-registry.json` and `config/fleet/policy.json`
  → Artifacts: [agents-registry.json](/Users/rl/coding/moltinger-openclaw-control-plane/config/fleet/agents-registry.json), [policy.json](/Users/rl/coding/moltinger-openclaw-control-plane/config/fleet/policy.json), [test_fleet_registry.sh](/Users/rl/coding/moltinger-openclaw-control-plane/tests/static/test_fleet_registry.sh)
- [X] T037 [P] [US5] [EXECUTOR: bash-master] [PARALLEL-GROUP-US5-A] Implement `extraction-readiness` verification in `scripts/clawdiy-smoke.sh`
  → Artifacts: [clawdiy-smoke.sh](/Users/rl/coding/moltinger-openclaw-control-plane/scripts/clawdiy-smoke.sh), [openclaw.json](/Users/rl/coding/moltinger-openclaw-control-plane/config/clawdiy/openclaw.json), [test_clawdiy_extraction_readiness.sh](/Users/rl/coding/moltinger-openclaw-control-plane/tests/integration_local/test_clawdiy_extraction_readiness.sh)
- [X] T038 [US5] [EXECUTOR: technical-writer] [SEQUENTIAL] Document future permanent-agent onboarding and Clawdiy node extraction path in `docs/plans/agent-factory-lifecycle.md` and `docs/GIT-TOPOLOGY-REGISTRY.md`
  → Artifacts: [agent-factory-lifecycle.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/plans/agent-factory-lifecycle.md), [GIT-TOPOLOGY-REGISTRY.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/GIT-TOPOLOGY-REGISTRY.md)
- [X] T039 [US5] [EXECUTOR: technical-writer] [SEQUENTIAL] Document same-host versus remote-node routing, trust, and discovery posture in `docs/INFRASTRUCTURE.md`
  → Artifacts: [INFRASTRUCTURE.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/INFRASTRUCTURE.md)

**Checkpoint**: The platform contract scales beyond the first two agents without topology rewrite.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Reconcile documentation, test lanes, and hardening across all user stories.

- [ ] T040 [P] [EXECUTOR: technical-writer] [PARALLEL-GROUP-POLISH-A] Reconcile operator docs and quick references in `docs/deployment-strategy.md`, `docs/QUICK-REFERENCE.md`, and `specs/001-clawdiy-agent-platform/quickstart.md`
- [ ] T041 [P] [EXECUTOR: integration-tester] [PARALLEL-GROUP-POLISH-A] Wire Clawdiy validation into umbrella test runners in `tests/run.sh`, `tests/run_integration.sh`, and `tests/run_security.sh`
- [ ] T042 [P] [EXECUTOR: security-expert] [PARALLEL-GROUP-POLISH-A] Perform final security hardening across `docker-compose.clawdiy.yml`, `config/fleet/policy.json`, and `scripts/preflight-check.sh`
- [ ] T043 [EXECUTOR: MAIN] [SEQUENTIAL] Run the quickstart validation flow from `specs/001-clawdiy-agent-platform/quickstart.md` and capture rollout notes in `SESSION_SUMMARY.md`

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
