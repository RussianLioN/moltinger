# Tasks: Fallback LLM with Ollama Sidecar

**Input**: Design documents from `/specs/001-fallback-llm-ollama/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: No tests explicitly requested. Focus on implementation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Project Type**: Infrastructure/Docker deployment
- **Primary files**: docker-compose.prod.yml, config/moltis.toml, scripts/*.sh
- **Secrets**: secrets/ (gitignored)

---

## Phase 0: Planning (Executor Assignment)

**Purpose**: Prepare for implementation by analyzing requirements, creating necessary agents, and assigning executors.

- [ ] P001 Analyze all tasks and identify required agent types and capabilities
- [ ] P002 Create missing agents using meta-agent-v3 (launch N calls in single message, 1 per agent), then ask user restart
- [ ] P003 Assign executors to all tasks: MAIN (trivial only), existing agents (100% match), or specific agent names
- [ ] P004 Resolve research tasks: simple (solve with tools now), complex (create prompts in research/)

**Rules**:
- **MAIN executor**: ONLY for trivial tasks (1-2 line fixes, simple imports, single npm install)
- **Existing agents**: ONLY if 100% capability match after thorough examination
- **Agent creation**: Launch all meta-agent-v3 calls in single message for parallel execution
- **After P002**: Must restart claude-code before proceeding to P003

**Artifacts**:
- Updated tasks.md with [EXECUTOR: name], [SEQUENTIAL]/[PARALLEL-GROUP-X] annotations
- .claude/agents/{domain}/{type}/{name}.md (if new agents created)
- research/*.md (if complex research identified)

---

## Phase 1: Setup (Ollama Sidecar Infrastructure)

**Purpose**: Add Ollama container to Docker Compose stack

- [X] T001 Add ollama service to docker-compose.prod.yml with resource limits (4 CPUs, 8GB RAM)
  → Artifacts: [docker-compose.prod.yml](/docker-compose.prod.yml)
- [X] T002 Add ollama-data volume definition to docker-compose.prod.yml
  → Artifacts: [docker-compose.prod.yml](/docker-compose.prod.yml)
- [X] T003 [P] Add ollama_api_key secret definition to docker-compose.prod.yml
  → Artifacts: [docker-compose.prod.yml](/docker-compose.prod.yml)
- [X] T004 [P] Create secrets/ollama_api_key.txt placeholder file with instructions
  → Artifacts: [secrets/ollama_api_key.txt](/secrets/ollama_api_key.txt)

**Checkpoint**: ✅ Ollama container can be started with `docker compose up -d`

---

## Phase 2: Foundational (Moltis Configuration)

**Purpose**: Configure Moltis to use Ollama as fallback provider

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Enable ollama provider in config/moltis.toml (enabled = true)
  → Artifacts: [config/moltis.toml](/config/moltis.toml)
- [X] T006 Configure ollama provider settings in config/moltis.toml (base_url, model, alias)
  → Artifacts: [config/moltis.toml](/config/moltis.toml)
- [X] T007 [P] Configure failover section in config/moltis.toml (enabled, fallback_models)
  → Artifacts: [config/moltis.toml](/config/moltis.toml)
- [X] T008 [P] Add OLLAMA_API_KEY environment variable reference to config/moltis.toml
  → Artifacts: [config/moltis.toml](/config/moltis.toml)

**Checkpoint**: ✅ Moltis can route requests to Ollama container

---

## Phase 3: User Story 1 - Automatic Failover on GLM Outage (Priority: P1) 🎯 MVP

**Goal**: System automatically switches to Ollama when GLM API is unavailable

**Independent Test**: Simulate GLM API unavailability and verify requests go to Ollama

### Implementation for User Story 1

- [X] T009 [P] [US1] Create scripts/ollama-health.sh for Ollama health checks
  → Artifacts: [scripts/ollama-health.sh](/scripts/ollama-health.sh)
- [X] T010 [P] [US1] Add GLM health check function to scripts/health-monitor.sh
  → Artifacts: [scripts/health-monitor.sh](/scripts/health-monitor.sh)
- [X] T011 [US1] Implement circuit breaker state machine in scripts/health-monitor.sh (CLOSED → OPEN → HALF-OPEN)
  → Artifacts: [scripts/health-monitor.sh](/scripts/health-monitor.sh)
- [X] T012 [US1] Add state file management (/tmp/moltis-llm-state.json) to scripts/health-monitor.sh
  → Artifacts: [scripts/health-monitor.sh](/scripts/health-monitor.sh)
- [X] T013 [US1] Add file locking with flock for race condition prevention in scripts/health-monitor.sh
  → Artifacts: [scripts/health-monitor.sh](/scripts/health-monitor.sh)
- [X] T014 [US1] Add automatic provider switching logic to scripts/health-monitor.sh
  → Artifacts: [scripts/health-monitor.sh](/scripts/health-monitor.sh)
- [X] T015 [US1] Add graceful recovery logic (half-open state testing) to scripts/health-monitor.sh
  → Artifacts: [scripts/health-monitor.sh](/scripts/health-monitor.sh)

**Checkpoint**: Circuit breaker automatically switches GLM → Ollama on 3 consecutive failures

---

## Phase 4: User Story 2 - Health Monitoring & Observability (Priority: P2)

**Goal**: Admins can monitor LLM provider health through Prometheus metrics

**Independent Test**: Query Prometheus metrics and verify provider status is reported

### Implementation for User Story 2

- [X] T016 [P] [US2] Add llm_provider_available gauge metric export to scripts/health-monitor.sh
  → Artifacts: [scripts/health-monitor.sh](/scripts/health-monitor.sh)
- [X] T017 [P] [US2] Add llm_fallback_triggered_total counter metric to scripts/health-monitor.sh
  → Artifacts: [scripts/health-monitor.sh](/scripts/health-monitor.sh)
- [X] T018 [US2] Add llm_request_duration_seconds histogram metric to scripts/health-monitor.sh
  → Artifacts: [scripts/health-monitor.sh](/scripts/health-monitor.sh)
- [X] T019 [US2] Add circuit breaker state metric (moltis_circuit_state) to scripts/health-monitor.sh
  → Artifacts: [scripts/health-monitor.sh](/scripts/health-monitor.sh)
- [X] T020 [US2] Add Prometheus alert rules for GLM API unavailability in config/prometheus/alerts.yml
  → Artifacts: [config/prometheus/alert-rules.yml](/config/prometheus/alert-rules.yml)
- [X] T021 [US2] Add AlertManager notification config for failover events in config/alertmanager/alertmanager.yml
  → Artifacts: [config/alertmanager/alertmanager.yml](/config/alertmanager/alertmanager.yml)

**Checkpoint**: Metrics visible in Prometheus, alerts trigger on GLM outage

---

## Phase 5: User Story 3 - CI/CD Validation (Priority: P3)

**Goal**: Failover configuration is validated in CI/CD pipeline before deployment

**Independent Test**: Push invalid config and verify CI fails with clear error

### Implementation for User Story 3

- [ ] T022 [P] [US3] Add Ollama configuration validation to scripts/preflight-check.sh
- [ ] T023 [P] [US3] Add OLLAMA_API_KEY secret existence check to scripts/preflight-check.sh
- [ ] T024 [US3] Add failover smoke test step to .github/workflows/deploy.yml verify job
- [ ] T025 [US3] Add TOML syntax validation for moltis.toml in .github/workflows/deploy.yml
- [ ] T026 [US3] Add Ollama health check step to .github/workflows/deploy.yml verify job

**Checkpoint**: CI pipeline validates Ollama config and fails on invalid configuration

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and final improvements

- [ ] T027 [P] Update SESSION_SUMMARY.md with Fallback LLM feature
- [ ] T028 [P] Update docs/SECRETS-MANAGEMENT.md with OLLAMA_API_KEY instructions
- [ ] T029 Create docs/disaster-recovery.md with failover runbook
- [ ] T030 [P] Add .gitignore entry for secrets/ollama_api_key.txt
- [ ] T031 Run quickstart.md validation - verify deployment works end-to-end
- [ ] T032 Close Beads task moltinger-xh7 (Fallback LLM provider)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational (Phase 2) completion
  - User stories can proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Phase 6)**: Depends on User Story 1 (MVP) completion minimum

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Phase 2 - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Phase 2 - Independent of US1 but uses same scripts
- **User Story 3 (P3)**: Can start after Phase 2 - Independent of US1/US2

### Within Each User Story

- Health check scripts before circuit breaker logic
- Circuit breaker before provider switching
- Core implementation before metrics
- Story complete before moving to next priority

### Parallel Opportunities

- T001-T002: Sequential (same file)
- T003-T004: Parallel (different files)
- T005-T008: T005-T006 sequential, T007-T008 parallel
- T009-T010: Parallel (different files)
- T016-T017: Parallel (same file but different functions)
- T022-T023: Parallel (same file but different checks)
- T027-T028, T030: Parallel (different files)

---

## Parallel Example: Phase 1 Setup

```bash
# Sequential (same file)
Task: "Add ollama service to docker-compose.prod.yml"
Task: "Add ollama-data volume to docker-compose.prod.yml"

# Can run in parallel (different files):
Task: "Add ollama_api_key secret to docker-compose.prod.yml"
Task: "Create secrets/ollama_api_key.txt placeholder"
```

## Parallel Example: User Story 1

```bash
# Can run in parallel (different files):
Task: "Create scripts/ollama-health.sh"
Task: "Add GLM health check to scripts/health-monitor.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (Ollama container)
2. Complete Phase 2: Foundational (Moltis config)
3. Complete Phase 3: User Story 1 (Circuit Breaker)
4. **STOP and VALIDATE**: Test failover manually
5. Deploy - MVP complete!

### Incremental Delivery

1. Setup + Foundational → Ollama running, Moltis configured
2. Add User Story 1 → Automatic failover works → Deploy (MVP!)
3. Add User Story 2 → Metrics visible → Deploy
4. Add User Story 3 → CI validation → Deploy
5. Polish → Documentation complete → Release

### Suggested Executors

| Phase | Suggested Executor | Reason |
|-------|-------------------|--------|
| Phase 0 | MAIN | Planning tasks |
| Phase 1 | consilium-docker-expert | Docker Compose expertise |
| Phase 2 | consilium-toml-specialist | TOML configuration |
| Phase 3 | consilium-sre-engineer | Circuit breaker pattern |
| Phase 4 | consilium-prometheus-expert | Metrics expertise |
| Phase 5 | consilium-cicd-architect | CI/CD expertise |
| Phase 6 | MAIN | Documentation |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Total tasks: 32 (4 planning + 4 setup + 4 foundational + 7 US1 + 6 US2 + 5 US3 + 6 polish)
