# Tasks: Docker Deployment Improvements

**Input**: Design documents from `/specs/001-docker-deploy-improvements/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: No explicit test tasks requested in specification. Validation via smoke tests and health checks.

**Organization**: Tasks grouped by user story for independent implementation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1-US7)
- File paths are exact locations for modifications

---

## Phase 0: Planning (Executor Assignment)

**Purpose**: Prepare for implementation by analyzing requirements and assigning executors.

- [X] P001 Analyze all tasks and identify required agent types and capabilities
- [X] P002 Create missing agents using meta-agent-v3 (if needed), then ask user restart
- [X] P003 Assign executors to all tasks: MAIN (trivial only), existing agents (100% match), or specific agent names
- [X] P004 Resolve research tasks: all research completed in research.md

**Executor Assignments:**
- Phase 1-2: [EXECUTOR: MAIN] - directory creation, simple config
- Phase 3-6 (P1): [EXECUTOR: infrastructure-specialist] - systemd, secrets, versions
- Phase 7-9 (P2): [EXECUTOR: MAIN] - script enhancements
- Phase 10: [EXECUTOR: MAIN] - documentation

**Rules**:
- **MAIN executor**: Only for trivial tasks (single file edits, simple config changes)
- **Existing agents**: Use infrastructure-specialist, bash-master, docker-expert from consilium
- **No new agents needed**: Existing project agents sufficient

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create base structure for new configuration files

- [X] T001 Create systemd directory for timer files at `systemd/`
  → Artifacts: [systemd/](systemd/)
- [X] T002 Create backup metrics export directory at `config/prometheus/targets/`
  → Artifacts: [targets/.gitkeep](config/prometheus/targets/.gitkeep)
- [X] T003 [P] Create pre-flight validation script structure at `scripts/preflight-check.sh`
  → Artifacts: [preflight-check.sh](scripts/preflight-check.sh)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before user stories

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create secrets directory structure at `secrets/` with .gitkeep
  → Artifacts: [secrets/.gitkeep](secrets/.gitkeep)
- [X] T005 [P] Add YAML anchors to docker-compose.yml for common configuration
  → Artifacts: [docker-compose.yml](docker-compose.yml)
- [X] T006 [P] Update docker-compose.prod.yml to use anchors from base file
  → Artifacts: [docker-compose.prod.yml](docker-compose.prod.yml) - anchors already existed, verified consistency
- [X] T007 Validate both compose files with `docker compose config --quiet`
  → Validated: both files pass

**Checkpoint**: Foundation ready - user story implementation can begin

---

## Phase 3: User Story 1 - Automated Off-Site Backup (Priority: P1) 🎯 MVP

**Goal**: Daily automated backups with S3 off-site storage

**Independent Test**: Verify backup files exist in S3 after cron trigger, restore procedure succeeds

### Implementation for User Story 1

- [X] T008 [P] [US1] Create systemd timer unit at `systemd/moltis-backup.timer`
  → Artifacts: [moltis-backup.timer](systemd/moltis-backup.timer)
- [X] T009 [P] [US1] Create systemd service unit at `systemd/moltis-backup.service`
  → Artifacts: [moltis-backup.service](systemd/moltis-backup.service)
- [X] T010 [US1] Update backup script to support --json flag in `scripts/backup-moltis-enhanced.sh`
  → Artifacts: [backup-moltis-enhanced.sh](scripts/backup-moltis-enhanced.sh) - JSON output with status/details/errors
- [X] T011 [US1] Add S3 upload retry logic to backup script in `scripts/backup-moltis-enhanced.sh`
  → 3 retries with exponential backoff (1s, 2s, 4s)
- [X] T012 [US1] Add backup metrics export for Prometheus in `scripts/backup-moltis-enhanced.sh`
  → Writes to /var/lib/node_exporter/textfile_dir/moltis_backup.prom
- [X] T013 [US1] Create backup status file at end of backup in `/var/lib/moltis/backup-status.json`
  → JSON status file with backup_id, timestamp, size, checksum
- [X] T014 [US1] Update Makefile with `backup-enable` and `backup-disable` targets
  → Artifacts: [Makefile](Makefile) - backup-enable, backup-disable, backup-status targets

**Checkpoint**: Automated daily backups functional, S3 upload working

---

## Phase 4: User Story 2 - Secure Secrets Management (Priority: P1)

**Goal**: All API keys stored as Docker secrets, not environment variables

**Independent Test**: Verify no API keys in `docker inspect` environment output

### Implementation for User Story 2

- [X] T015 [P] [US2] Create template for TELEGRAM_BOT_TOKEN secret at `secrets/telegram_bot_token.txt.example`
  → Artifacts: [telegram_bot_token.txt.example](secrets/telegram_bot_token.txt.example)
- [X] T016 [P] [US2] Create template for TAVILY_API_KEY secret at `secrets/tavily_api_key.txt.example`
  → Artifacts: [tavily_api_key.txt.example](secrets/tavily_api_key.txt.example)
- [X] T017 [P] [US2] Create template for GLM_API_KEY secret at `secrets/glm_api_key.txt.example`
  → Artifacts: [glm_api_key.txt.example](secrets/glm_api_key.txt.example)
- [X] T018 [US2] Update docker-compose.yml to use secrets section for all API keys
  → Artifacts: [docker-compose.yml](docker-compose.yml) - Added secrets section with *_FILE environment variables
- [X] T019 [US2] Update docker-compose.prod.yml to use secrets section for all API keys
  → Artifacts: [docker-compose.prod.yml](docker-compose.prod.yml) - Extended secrets section with all API keys
- [ ] T020 [US2] Update Moltis service to read secrets from `/run/secrets/` paths
- [ ] T021 [US2] Update GitHub Actions deploy.yml to create secret files from GitHub Secrets

**Checkpoint**: All secrets migrated, services authenticate successfully

---

## Phase 5: User Story 3 - Reproducible Deployments (Priority: P1)

**Goal**: All Docker images pinned to specific versions

**Independent Test**: Verify all image references contain version tags, redeployment produces identical versions

### Implementation for User Story 3

- [X] T022 [P] [US3] Pin Moltis image version in `docker-compose.yml` (change `:latest` to `:v1.7.0`)
  → Artifacts: [docker-compose.yml](docker-compose.yml) - moltis:v1.7.0
- [X] T023 [P] [US3] Pin Moltis image version in `docker-compose.prod.yml`
  → Artifacts: [docker-compose.prod.yml](docker-compose.prod.yml) - moltis:v1.7.0
- [X] T024 [P] [US3] Pin Watchtower image version in `docker-compose.yml`
  → Artifacts: [docker-compose.yml](docker-compose.yml) - watchtower:v1.7.1
- [X] T025 [P] [US3] Pin Watchtower image version in `docker-compose.prod.yml`
  → Artifacts: [docker-compose.prod.yml](docker-compose.prod.yml) - watchtower:v1.7.1
- [X] T026 [US3] Document version update process in `docs/version-update.md`
  → Artifacts: [version-update.md](docs/version-update.md) - 165 lines of documentation
- [X] T027 [US3] Add Makefile target `version-check` to list current versions
  → Artifacts: [Makefile](Makefile) - version-check target

**Checkpoint**: All images pinned, predictable deployments

---

## Phase 6: User Story 4 - GitOps Compliance (Priority: P1)

**Goal**: All configuration changes go through git, no sed anti-patterns

**Independent Test**: UAT gate workflow uses full file sync pattern

### Implementation for User Story 4

- [X] T028 [US4] Identify sed command location in `.github/workflows/uat-gate.yml`
  → Found at line 273, replaced with GitOps-compliant scp
- [X] T029 [US4] Replace sed with full file scp pattern in `.github/workflows/uat-gate.yml`
  → Artifacts: [uat-gate.yml](.github/workflows/uat-gate.yml) - scp docker-compose.yml + config/ + scripts/
- [X] T030 [US4] Add git SHA verification step to deploy workflow in `.github/workflows/deploy.yml`
  → Artifacts: [deploy.yml](.github/workflows/deploy.yml) - .deployed-sha and .deployment-info files
- [X] T031 [US4] Update gitops-guards.sh to verify no sed patterns in workflows
  → Artifacts: [gitops-guards.sh](scripts/gitops-guards.sh) - gitops_check_workflow_sed() function

**Checkpoint**: 100% GitOps compliance achieved

---

## Phase 7: User Story 5 - AI-Ready Output Mode (Priority: P2)

**Goal**: JSON output from deployment scripts for AI parsing

**Independent Test**: Scripts with `--json` flag produce valid, parseable JSON

### Implementation for User Story 5

- [X] T032 [P] [US5] Add --json flag to deploy.sh in `scripts/deploy.sh`
  → Artifacts: [deploy.sh](scripts/deploy.sh) - JSON output for deploy/rollback/status
- [X] T033 [P] [US5] Add --no-color flag to deploy.sh in `scripts/deploy.sh`
  → Artifacts: [deploy.sh](scripts/deploy.sh) - --no-color for CI/CD logs
- [X] T034 [P] [US5] Add --json flag to health-monitor.sh in `scripts/health-monitor.sh`
  → Artifacts: [health-monitor.sh](scripts/health-monitor.sh) - JSON health status
- [ ] T035 [US5] Create JSON output format documentation in `docs/json-output.md`

**Checkpoint**: All scripts support structured output

---

## Phase 8: User Story 6 - Pre-Flight Validation (Priority: P2)

**Goal**: Early validation of required secrets before deployment

**Independent Test**: Pre-flight fails with clear message when secrets missing

### Implementation for User Story 6

- [X] T036 [US6] Implement preflight-check.sh with secrets validation in `scripts/preflight-check.sh`
  → Created in Phase 1 - validates secrets, Docker, compose syntax, disk space
- [X] T037 [US6] Add --json output support to preflight-check.sh
  → Already has --json and --strict flags
- [X] T038 [US6] Add preflight job to deploy.yml workflow in `.github/workflows/deploy.yml`
  → Artifacts: [deploy.yml](.github/workflows/deploy.yml) - preflight validation step
- [X] T039 [US6] Add preflight job to uat-gate.yml workflow in `.github/workflows/uat-gate.yml`
  → Artifacts: [uat-gate.yml](.github/workflows/uat-gate.yml) - preflight validation step

**Checkpoint**: Fail-fast on missing secrets

---

## Phase 9: User Story 7 - Unified Configuration (Priority: P2)

**Goal**: Consistent patterns between dev and prod compose files

**Independent Test**: Both compose files validate, common patterns in anchors

### Implementation for User Story 7

- [X] T040 [P] [US7] Create x-common-env anchor in docker-compose.yml
  → Done in Phase 2 - x-common-env with MOLTIS_HOST, MOLTIS_NO_TLS, MOLTIS_BEHIND_PROXY
- [X] T041 [P] [US7] Create x-healthcheck anchor in docker-compose.yml
  → Done in Phase 2 - x-healthcheck with curl health check
- [X] T042 [P] [US7] Create x-logging anchor in docker-compose.yml
  → Done in Phase 2 - x-logging with json-file driver
- [X] T043 [US7] Update docker-compose.prod.yml to use anchors with overrides
  → Already uses anchors - verified consistency
- [ ] T044 [US7] Document unified structure in `docs/compose-structure.md`

**Checkpoint**: Unified configuration across environments

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T045 [P] Add backup alert rules to `config/prometheus/backup_rules.yml`
- [ ] T046 [P] Update AlertManager routing for backup alerts in `config/alertmanager/alertmanager.yml`
- [ ] T047 Update quickstart.md with new procedures in `specs/001-docker-deploy-improvements/quickstart.md`
- [ ] T048 Create systemd installation documentation in `docs/systemd-setup.md`
- [ ] T049 Run smoke test validation via `make deploy && make health-check`
- [ ] T050 Update CLAUDE.md with new deployment procedures

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
- **User Stories (Phase 3-9)**: All depend on Foundational completion
  - US1-US4 (P1): Can run in parallel
  - US5-US7 (P2): Can run in parallel after P1 stories
- **Polish (Phase 10)**: Depends on user stories

### User Story Dependencies

| Story | Priority | Depends On | Can Start After |
|-------|----------|------------|-----------------|
| US1 (Backup) | P1 | Foundation | Phase 2 complete |
| US2 (Secrets) | P1 | Foundation | Phase 2 complete |
| US3 (Versions) | P1 | Foundation | Phase 2 complete |
| US4 (GitOps) | P1 | Foundation | Phase 2 complete |
| US5 (JSON) | P2 | US1, US3 | After P1 stories |
| US6 (Preflight) | P2 | US2 | After US2 complete |
| US7 (Unified) | P2 | Foundation | Phase 2 complete |

### Parallel Opportunities

**P1 Stories (can run in parallel)**:
```bash
# Launch US1, US2, US3, US4 together:
Task: "Create systemd timer unit" (US1)
Task: "Create secret templates" (US2)
Task: "Pin image versions" (US3)
Task: "Fix sed in uat-gate.yml" (US4)
```

**P2 Stories (can run in parallel after P1)**:
```bash
# Launch US5, US6, US7 together:
Task: "Add --json flag to deploy.sh" (US5)
Task: "Implement preflight-check.sh" (US6)
Task: "Create YAML anchors" (US7)
```

---

## Implementation Strategy

### MVP First (P1 Stories Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3-6: User Stories 1-4 (P1)
4. **STOP and VALIDATE**: Test all P1 stories
5. Deploy to production

### Incremental Delivery

1. Foundation → US1 (Backup) → Deploy (Critical fix!)
2. US2 (Secrets) → Deploy (Security fix!)
3. US3 (Versions) + US4 (GitOps) → Deploy
4. US5-US7 (P2) → Deploy (Enhancements)

---

## Notes

- All [P] tasks modify different files - no conflicts
- Infrastructure project - no code compilation needed
- Validation via `docker compose config --quiet` and health checks
- Commit after each user story completion
- Deploy after each P1 story for incremental value
