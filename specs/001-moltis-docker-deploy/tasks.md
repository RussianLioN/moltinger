# Tasks: Moltis Docker Deployment on ainetic.tech

**Input**: Design documents from `/specs/001-moltis-docker-deploy/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, quickstart.md ✅

**Architecture**: GitOps 2.0 with Push-based CI/CD via GitHub Actions SSH

**Tests**: Manual verification via health checks and UI access (no automated tests for infrastructure)

**Organization**: Tasks grouped by phase for GitOps deployment workflow.

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

## Phase 13: Git-Tracked Container Update Controls

**Goal**: Keep any update helper sidecars non-authoritative and route Moltis version changes through git-tracked backup-safe rollout

**Independent Test**:
1. Verify Watchtower container running
2. Verify Moltis version bumps still require compose changes in git plus the deploy helper/workflow

### Implementation

- [X] T048 Add Watchtower service to docker-compose.yml
- [X] T049 Configure Watchtower environment: CLEANUP, POLL_INTERVAL=86400
- [X] T050 Add Watchtower label to Moltis service
- [ ] T051 Verify Watchtower remains non-authoritative for Moltis updates; use tracked git rollout for actual version bumps

**Checkpoint**: Helper sidecar present, but tracked git rollout remains the Moltis update authority

**Artifacts**:
- Updated `docker-compose.yml` with Watchtower
- Backup-safe tracked rollout documented in `docs/runbooks/moltis-backup-safe-update.md`

---

## Phase 14: Primary Codex + Ordered Fallback Chain

**Goal**: Configure the production provider chain with Codex primary and Ollama Cloud fallback

**Independent Test**:
1. Open Web UI
2. Verify `openai-codex::gpt-5.4` remains the primary model
3. Verify the only active fallback lane is `ollama::gemini-3-flash-preview:cloud`
4. Send a test message without any raw provider/tool leakage

### Implementation

- [X] T052 [P] Create `config/moltis.toml` with primary Codex plus Ollama Cloud fallback settings
- [X] T053 Keep the primary lane on OpenAI Codex OAuth / `gpt-5.4` without static API-key coupling
- [X] T054 Add provider-chain secret requirements to `.env.example` and deployment docs (`OLLAMA_API_KEY`)
- [ ] T055 Test Web UI and Telegram entrypoints against the ordered provider chain

**Checkpoint**: Provider chain working without legacy Z.ai aliases or any retired non-Ollama fallback lanes

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
- **Phase 14 (Provider Chain)**: Depends on Phase 3
- **Phase 15 (Polish)**: Depends on all previous phases

### Critical Path (MVP)

```
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 14
          ↓
       (MVP ready after Phase 5 + provider chain)
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
6. Complete Phase 14: Provider Chain
7. **STOP and VALIDATE**: Full deployment working

### Incremental Delivery

1. **MVP**: Container + Traefik + Auth + primary/fallback provider chain → Basic working AI assistant
2. **Add**: Sandbox + Persistence → Full functionality
3. **Add**: Backup + Watchtower → Operations
4. **Add**: Health + Telemetry → Observability
5. **Add**: Documentation → Complete

---

## Phase 16: GitOps CI/CD Infrastructure (NEW - Expert Consultation)

**Purpose**: Implement GitOps 2.0 architecture with push-based CI/CD

**Triggers**:
- Push to `main` → Auto-deploy
- Tag `v*` → Deploy specific version
- Manual workflow_dispatch → User-selected version

- [X] G001 Create `.github/workflows/deploy.yml` with SSH deployment
- [X] G002 Add preflight job for validation and version determination
- [X] G003 Add backup job for pre-deployment backup
- [X] G004 Add deploy job with health check verification
- [X] G005 Add rollback job for emergency restoration
- [X] G006 Add verify job with smoke tests
- [ ] G007 Configure GitHub Secret: `SSH_PRIVATE_KEY`
- [ ] G008 Configure GitHub Environment: `production`

**Checkpoint**: CI/CD pipeline ready for deployment

**Artifacts**:
- `.github/workflows/deploy.yml`

---

## Phase 17: Production Infrastructure (NEW - Expert Consultation)

**Purpose**: Production-ready infrastructure with monitoring

- [X] P001 Create `docker-compose.prod.yml` with resource limits and monitoring
- [X] P002 Add Prometheus configuration in `config/prometheus/prometheus.yml`
- [X] P003 Add AlertManager configuration in `config/alertmanager/alertmanager.yml`
- [X] P004 Add alert rules in `config/prometheus/alert-rules.yml`
- [X] P005 Create `scripts/deploy.sh` with blue-green deployment
- [X] P006 Create `scripts/health-monitor.sh` for self-healing
- [X] P007 Create `scripts/backup-moltis-enhanced.sh` with encryption and S3
- [X] P008 Create `Makefile` for management commands
- [X] P009 Create systemd service file in `config/systemd/`
- [X] P010 Create cron configuration in `config/cron/`

**Checkpoint**: Production infrastructure complete

**Artifacts**:
- `docker-compose.prod.yml`
- `config/prometheus/`
- `config/alertmanager/`
- `scripts/deploy.sh`
- `scripts/health-monitor.sh`
- `Makefile`

---

## Phase 18: Server Deployment (GitOps)

**Purpose**: Deploy to ainetic.tech using GitOps workflow

**Prerequisites**:
- SSH key deployed to server
- Server has SSH access to GitHub
- Traefik already running on server

- [ ] S001 Clone repository on server: `git clone https://github.com/RussianLioN/moltinger.git /opt/moltinger`
- [ ] S002 Setup environment: `cp .env.example .env && nano .env`
- [ ] S003 Add secrets to `.env` (`MOLTIS_PASSWORD`, `OLLAMA_API_KEY`)
- [ ] S004 Run `make setup` to create networks and secrets
- [ ] S005 Run `make deploy` for initial deployment
- [ ] S006 Verify health: `curl https://ainetic.tech/health`
- [ ] S007 Install systemd service: `sudo cp config/systemd/*.service /etc/systemd/system/`
- [ ] S008 Install cron jobs: `sudo cp config/cron/* /etc/cron.d/`
- [ ] S009 Configure GitHub Secret: `SSH_PRIVATE_KEY` (from local machine)
- [ ] S010 Trigger CI/CD: `git push origin main`

**Checkpoint**: Production deployment complete with CI/CD

**Artifacts**:
- Running Moltis on ainetic.tech
- CI/CD pipeline activated

---

## Phase 19: Documentation & Handoff

**Purpose**: Complete documentation for operations

- [X] D001 Create `docs/architecture/gitops-architecture.md`
- [X] D002 Create `docs/deployment-strategy.md`
- [X] D003 Create `docs/INFRASTRUCTURE.md`
- [ ] D004 Update `README.md` with deployment instructions
- [ ] D005 Create runbook for common operations
- [ ] D006 Create PR and merge to main

**Checkpoint**: Documentation complete

---

## Updated Dependencies & Execution Order

### Phase Dependencies (GitOps Enhanced)

```
Phase 1 (Setup) → Phase 2 (Foundational)
       ↓
Phase 16 (GitOps CI/CD) + Phase 17 (Production Infra)  [PARALLEL]
       ↓
Phase 3-14 (Feature Phases - already complete)
       ↓
Phase 18 (Server Deployment)
       ↓
Phase 19 (Documentation)
```

### Critical Path (GitOps)

```
Phase 1 → Phase 2 → Phase 16 → Phase 17 → Phase 18 → Phase 19
                                    ↓
                            [Push to main triggers CI/CD]
```

---

## Updated Implementation Strategy

### GitOps Workflow (Recommended)

1. **Local Development**: All changes in feature branches
2. **Push to Main**: Triggers GitHub Actions deployment
3. **Automatic Deployment**: SSH to ainetic.tech, backup, deploy, verify
4. **Rollback**: One-click via GitHub Actions UI or CLI

### Deployment Commands

```bash
# Initial setup (one-time on server)
make setup
make deploy

# Daily operations
make status
make logs LOGS_OPTS="-f"
make health-check

# Rollback
make restore FILE=/var/backups/moltis/daily/backup.tar.gz
# OR via GitHub Actions: workflow_dispatch(rollback=true)

# CI/CD triggered automatically on push to main
git push origin main
```

---

## Notes

- **GitOps 2.0**: Push-based deployment via GitHub Actions SSH
- **Self-healing**: health-monitor.sh daemon with auto-restart
- **Backup**: Enhanced with encryption, S3 offsite, 30/12/12 retention
- **Monitoring**: Prometheus + AlertManager with 20+ alert rules
- **Security warning**: Docker socket mount = root access on host
- **All secrets**: Managed via .env on server + GitHub Secrets for CI/CD
- **Commit after each completed phase**
