# Tasks: Moltis Docker Deployment on ainetic.tech

**Input**: Design documents from `/specs/001-moltis-docker-deploy/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, quickstart.md ✅

**Tests**: Manual verification via health checks and UI access (no automated tests for infrastructure)

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

- **Infrastructure project**: Root-level files (docker-compose.yml, config/, scripts/)
- **Configuration**: `config/` directory
- **Scripts**: `scripts/` directory (or `specs/001-moltis-docker-deploy/scripts/` for templates)

---

## Phase 0: Planning (Executor Assignment)

**Purpose**: Prepare for implementation by analyzing requirements, creating necessary agents, and assigning executors.

- [ ] P001 Analyze all tasks and identify required agent types and capabilities
- [ ] P002 Create missing agents using meta-agent-v3 (if needed), then ask user restart
- [ ] P003 Assign executors to all tasks: MAIN (trivial only), existing agents (100% match), or specific agent names
- [ ] P004 Resolve research tasks: All research completed in research.md

**Executor Assignment**:
- Infrastructure tasks → **MAIN** (simple config files)
- Script tasks → **MAIN** (bash scripts)
- No new agents required for this infrastructure project

**Artifacts**:
- tasks.md with executor annotations
- All research resolved in research.md

---

## Phase 1: Setup (Project Structure)

**Purpose**: Create project structure and base configuration

- [X] T001 Create project directory structure: `config/`, `data/`, `scripts/`
- [X] T002 Create `.env.example` file with required environment variables
- [X] T003 [P] Update `.gitignore` to exclude sensitive files (.env, data/, config/provider_keys.json)

**Artifacts**:
- `config/` directory
- `data/` directory (gitignored)
- `scripts/` directory
- `.env.example`
- Updated `.gitignore`

---

## Phase 2: Foundational (Docker Compose Base)

**Purpose**: Create base docker-compose.yml that all user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create `docker-compose.yml` with Moltis service definition (no Traefik labels yet)
- [X] T005 [P] Add volume mounts for config and data directories
- [X] T006 [P] Add environment variables: MOLTIS_HOST, MOLTIS_NO_TLS, MOLTIS_BEHIND_PROXY
- [X] T007 [P] Add Docker healthcheck using `/health` endpoint

**Checkpoint**: Base container can start and respond to health check

**Artifacts**:
- `docker-compose.yml` (base version)

---

## Phase 3: User Story 1 - Container Deployment (Priority: P1) 🎯 MVP

**Goal**: Deploy Moltis as Docker container accessible via Web UI

**Independent Test**:
1. Run `docker compose up -d`
2. Verify `curl http://localhost:13131/health` returns HTTP 200
3. Verify Web UI loads at http://localhost:13131

### Implementation for User Story 1

- [X] T008 [US1] Configure Moltis image in docker-compose.yml: `ghcr.io/moltis-org/moltis:latest`
- [X] T009 [US1] Set container name and restart policy: `restart: unless-stopped`
- [X] T010 [US1] Expose port 13131 for HTTP/WebSocket gateway
- [ ] T011 [US1] Verify container starts successfully with `docker compose up -d`
- [ ] T012 [US1] Test health check endpoint: `curl http://localhost:13131/health`

**Checkpoint**: Container running, health check passing, UI accessible locally

**Artifacts**:
- Updated `docker-compose.yml`
- Working Moltis container

---

## Phase 4: User Story 2 - Secure Remote Access (Priority: P1)

**Goal**: Configure Traefik reverse proxy with TLS for secure remote access

**Independent Test**:
1. Verify `https://ainetic.tech` loads without certificate warnings
2. Verify SSL Labs rating A or above

### Implementation for User Story 2

- [X] T013 [US2] Add Traefik labels to Moltis service in docker-compose.yml
- [X] T014 [US2] Configure Traefik router rule: `Host(\`ainetic.tech\`)`
- [X] T015 [US2] Configure Traefik entrypoint: `websecure`
- [X] T016 [US2] Configure TLS certResolver: `letsencrypt`
- [X] T017 [US2] Configure Traefik service port: `13131`
- [ ] T018 [US2] Add WebSocket support headers in Traefik config
- [X] T019 [US2] Set `MOLTIS_BEHIND_PROXY=true` environment variable
- [ ] T020 [US2] Test remote access via `https://ainetic.tech`

**Checkpoint**: Remote access works with valid TLS certificate

**Artifacts**:
- Updated `docker-compose.yml` with Traefik labels

---

## Phase 5: User Story 3 - Authentication Setup (Priority: P1)

**Goal**: Configure authentication for remote access

**Independent Test**:
1. Verify login page appears at `https://ainetic.tech`
2. Verify login with correct password succeeds
3. Verify login with wrong password fails

### Implementation for User Story 3

- [X] T021 [US3] Add `MOLTIS_PASSWORD` to `.env.example`
- [X] T022 [US3] Configure MOLTIS_PASSWORD in docker-compose.yml environment
- [X] T023 [US3] Document authentication flow in quickstart.md (already done)
- [ ] T024 [US3] Test login with correct password
- [ ] T025 [US3] Test rate limiting (5 failed attempts → 429 error)

**Checkpoint**: Authentication working, rate limiting active

**Artifacts**:
- Updated `.env.example`
- Updated `docker-compose.yml`

---

## Phase 6: User Story 4 - Persistent Data Storage (Priority: P2)

**Goal**: Ensure data persists across container restarts

**Independent Test**:
1. Create a session in Web UI
2. Restart container: `docker compose restart`
3. Verify session still exists

### Implementation for User Story 4

- [X] T026 [US4] Verify config volume mount: `./config:/home/moltis/.config/moltis`
- [X] T027 [US4] Verify data volume mount: `./data:/home/moltis/.moltis`
- [X] T028 [US4] Set volume permissions: `chown -R 1000:1000 config data`
- [ ] T029 [US4] Test persistence: create session, restart, verify

**Checkpoint**: Data persists across container restarts

**Artifacts**:
- Verified volume mounts in `docker-compose.yml`

---

## Phase 7: User Story 5 - Sandboxed Command Execution (Priority: P2)

**Goal**: Enable sandboxed shell command execution via Docker socket

**Independent Test**:
1. Ask AI to run `ls /` command
2. Verify command executes in sandbox container

### Implementation for User Story 5

- [X] T030 [US5] Add Docker socket mount: `/var/run/docker.sock:/var/run/docker.sock`
- [X] T031 [US5] Add privileged mode (required for Docker socket access)
- [X] T032 [US5] Configure sandbox in config/moltis.toml with resource limits
- [ ] T033 [US5] Test sandbox execution with simple command

**⚠️ Security Warning**: Docker socket mount = root access on host

**Checkpoint**: Sandboxed commands working

**Artifacts**:
- Updated `docker-compose.yml`
- `config/moltis.toml` with sandbox config

---

## Phase 8: User Story 6 - Health Monitoring (Priority: P3)

**Goal**: Configure health monitoring and Docker healthcheck

**Independent Test**:
1. Verify `curl https://ainetic.tech/health` returns HTTP 200
2. Verify Docker marks container as healthy

### Implementation for User Story 6

- [X] T034 [US6] Add Docker healthcheck to docker-compose.yml
- [X] T035 [US6] Configure healthcheck interval: 30s, timeout: 10s, retries: 3
- [ ] T036 [US6] Test healthcheck: `docker inspect moltis | grep Health`

**Checkpoint**: Health monitoring configured

**Artifacts**:
- Updated `docker-compose.yml` with healthcheck

---

## Phase 9: User Story 7 - API Key Management (Priority: P2)

**Goal**: Document API key management for programmatic access

**Independent Test**:
1. Create API key in Settings
2. Test API key with `curl -H "Authorization: Bearer mk_xxx"`

### Implementation for User Story 7

- [X] T037 [US7] Document API key creation in quickstart.md
- [X] T038 [US7] Add API key scopes table to quickstart.md
- [ ] T039 [US7] Test API key authentication

**Note**: API keys managed through Web UI, no code changes needed

**Checkpoint**: API key documentation complete

**Artifacts**:
- Updated `quickstart.md`

---

## Phase 10: User Story 8 - Passkey Authentication (Priority: P2)

**Goal**: Document passkey/WebAuthn authentication

**Independent Test**:
1. Register passkey in Settings
2. Login with passkey (Touch ID, YubiKey)

### Implementation for User Story 8

- [X] T040 [US8] Document passkey registration in quickstart.md
- [X] T041 [US8] Document supported authenticators (YubiKey, Touch ID, Windows Hello)

**Note**: Passkeys managed through Web UI, no code changes needed

**Checkpoint**: Passkey documentation complete

**Artifacts**:
- Updated `quickstart.md`

---

## Phase 11: User Story 9 - OpenTelemetry Monitoring (Priority: P3)

**Goal**: Document OpenTelemetry integration

**Independent Test**:
1. Configure `[telemetry]` in moltis.toml
2. Verify metrics appear in OTLP collector

### Implementation for User Story 9

- [X] T042 [US9] Add telemetry configuration example to config/moltis.toml
- [X] T043 [US9] Document OTLP endpoint configuration in quickstart.md

**Note**: Optional feature, depends on external OTLP collector

**Checkpoint**: Telemetry documentation complete

**Artifacts**:
- Updated `config/moltis.toml`
- Updated `quickstart.md`

---

## Phase 12: Backup Configuration

**Goal**: Configure automated daily backups

**Independent Test**:
1. Run backup script manually
2. Verify backup file created in `/var/backups/moltis/`
3. Test restore from backup

### Implementation

- [X] T044 [P] Copy backup script to scripts/ directory
- [X] T045 Configure backup directories in script: CONFIG_DIR, DATA_DIR
- [ ] T046 [P] Create cron job for daily backup at 3 AM
- [ ] T047 Test backup and restore process

**Checkpoint**: Automated backups configured

**Artifacts**:
- `scripts/backup-moltis.sh`
- Cron job configured

---

## Phase 13: Watchtower Auto-Updates

**Goal**: Configure automatic container updates

**Independent Test**:
1. Verify Watchtower container running
2. Verify Watchtower logs show update checks

### Implementation

- [X] T048 Add Watchtower service to docker-compose.yml
- [X] T049 Configure Watchtower environment: CLEANUP, POLL_INTERVAL=86400
- [X] T050 Add Watchtower label to Moltis service
- [ ] T051 Test Watchtower: `docker compose exec watchtower /watchtower --run-once`

**Checkpoint**: Auto-updates configured

**Artifacts**:
- Updated `docker-compose.yml` with Watchtower

---

## Phase 14: GLM Provider Configuration

**Goal**: Configure GLM as LLM provider

**Independent Test**:
1. Open Web UI
2. Configure GLM provider
3. Send test message

### Implementation

- [X] T052 [P] Create config/moltis.toml with GLM provider settings
- [X] T053 Add GLM base_url: `https://api.z.ai/api/coding/paas/v4`
- [X] T054 Add GLM_API_KEY to .env.example
- [ ] T055 Test GLM provider in Web UI

**Checkpoint**: GLM provider working

**Artifacts**:
- `config/moltis.toml`
- Updated `.env.example`

---

## Phase 15: Polish & Documentation

**Purpose**: Final improvements and validation

- [ ] T056 [P] Validate quickstart.md steps manually
- [ ] T057 [P] Add troubleshooting section to quickstart.md
- [ ] T058 Create final README.md with deployment instructions
- [ ] T059 Security audit: verify no hardcoded credentials
- [ ] T060 Final validation: complete deployment test

**Artifacts**:
- Validated `quickstart.md`
- `README.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 0 (Planning)**: No dependencies
- **Phase 1 (Setup)**: No dependencies
- **Phase 2 (Foundational)**: Depends on Phase 1
- **Phase 3 (US1 - Container)**: Depends on Phase 2 - 🎯 MVP
- **Phase 4 (US2 - Traefik)**: Depends on Phase 3
- **Phase 5 (US3 - Auth)**: Depends on Phase 4
- **Phase 6 (US4 - Persistence)**: Depends on Phase 2 (parallel with US1-US3)
- **Phase 7 (US5 - Sandbox)**: Depends on Phase 2
- **Phase 8 (US6 - Health)**: Depends on Phase 2
- **Phase 9-11 (US7-US9 - Docs)**: Can run in parallel after Phase 2
- **Phase 12 (Backup)**: Depends on Phase 2
- **Phase 13 (Watchtower)**: Depends on Phase 2
- **Phase 14 (GLM)**: Depends on Phase 3
- **Phase 15 (Polish)**: Depends on all previous phases

### Critical Path (MVP)

```
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 14
          ↓
       (MVP ready after Phase 5 + GLM)
```

### Parallel Opportunities

**After Phase 2 completes**:
- Phase 3 (US1), Phase 6 (US4), Phase 7 (US5), Phase 8 (US6) can run in parallel
- Phase 12 (Backup), Phase 13 (Watchtower) can run in parallel

**Documentation phases**:
- Phase 9, 10, 11 can run in parallel

---

## Implementation Strategy

### MVP First (Phases 1-5 + 14)

1. Complete Phase 1: Setup (directories, .gitignore)
2. Complete Phase 2: Foundational (docker-compose base)
3. Complete Phase 3: Container Deployment
4. Complete Phase 4: Traefik Configuration
5. Complete Phase 5: Authentication
6. Complete Phase 14: GLM Provider
7. **STOP and VALIDATE**: Full deployment working

### Incremental Delivery

1. **MVP**: Container + Traefik + Auth + GLM → Basic working AI assistant
2. **Add**: Sandbox + Persistence → Full functionality
3. **Add**: Backup + Watchtower → Operations
4. **Add**: Health + Telemetry → Observability
5. **Add**: Documentation → Complete

---

## Notes

- Infrastructure project: MAIN executor for all tasks
- No automated tests: manual verification via health checks
- Security warning on Docker socket mount documented
- All configuration via environment variables (no hardcoded credentials)
- Commit after each completed phase
