# Feature Specification: Docker Deployment Improvements

**Feature Branch**: `001-docker-deploy-improvements`
**Created**: 2026-02-28
**Status**: Draft
**Input**: User description: "Improve Docker deployment process based on consilium recommendations: Enable S3 backup with cron, migrate API keys to Docker secrets, pin image versions, fix GitOps sed violation, add backup alerts, add JSON output mode, add secrets validation, unify compose files"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automated Off-Site Backup (Priority: P1)

As a system administrator, I need automated daily backups stored off-site so that data is protected against server failure.

**Why this priority**: Critical for data loss prevention. Consilium experts unanimously identified this as the highest risk gap - currently no automated backup schedule and S3 backup is disabled.

**Independent Test**: Can be fully tested by verifying backup files exist in S3 storage after cron trigger, and restore procedure completes successfully.

**Acceptance Scenarios**:

1. **Given** the backup system is configured, **When** the daily cron triggers, **Then** a backup is created and uploaded to S3
2. **Given** a backup exists in S3, **When** restore procedure is initiated, **Then** data is restored to the specified point in time
3. **Given** backup fails for any reason, **When** failure occurs, **Then** administrators receive an alert within 5 minutes

---

### User Story 2 - Secure Secrets Management (Priority: P1)

As a security-conscious administrator, I need all sensitive credentials stored as Docker secrets so they are not exposed in environment variables.

**Why this priority**: Security vulnerability - API keys currently visible in environment. Docker Expert identified this as critical security gap.

**Independent Test**: Can be fully tested by verifying no API keys appear in `docker inspect` environment output, and all services function correctly with secrets.

**Acceptance Scenarios**:

1. **Given** API keys are migrated to secrets, **When** container inspection is performed, **Then** no API keys are visible in environment variables
2. **Given** secrets are configured, **When** container starts, **Then** services authenticate successfully using secrets
3. **Given** a secret is missing, **When** deployment is attempted, **Then** deployment fails with clear error message identifying the missing secret

---

### User Story 3 - Reproducible Deployments (Priority: P1)

As a DevOps engineer, I need all Docker images pinned to specific versions so that deployments are predictable and rollbacks are reliable.

**Why this priority**: `:latest` tag creates non-deterministic behavior. IaC Expert and multiple experts flagged this as critical for reproducibility.

**Independent Test**: Can be fully tested by verifying all image references in compose files contain version tags, and redeployment produces identical container versions.

**Acceptance Scenarios**:

1. **Given** all images have pinned versions, **When** deployment runs, **Then** exact same image versions are used regardless of registry updates
2. **Given** a rollback is needed, **When** previous version is specified, **Then** exact previous image is deployed
3. **Given** version update is required, **When** new version is specified in compose, **Then** only that service is updated

---

### User Story 4 - GitOps Compliance (Priority: P1)

As a platform maintainer, I need all configuration changes to go through git so that there is a complete audit trail and no configuration drift.

**Why this priority**: GitOps Guardian identified `sed` command in uat-gate.yml as anti-pattern violating GitOps principles.

**Independent Test**: Can be fully tested by triggering UAT gate workflow and verifying full file sync pattern is used instead of partial `sed` updates.

**Acceptance Scenarios**:

1. **Given** UAT gate workflow runs, **When** configuration update is needed, **Then** entire file is synced from git (not partial sed update)
2. **Given** git commit SHA is recorded, **When** drift detection runs, **Then** deployed configuration matches git state
3. **Given** configuration drift is detected, **When** alert fires, **Then** remediation can trace back to specific git commit

---

### User Story 5 - AI-Ready Output Mode (Priority: P2)

As an automation engineer, I need JSON output from deployment scripts so that AI systems can parse and act on deployment status.

**Why this priority**: Prompt Engineer identified lack of structured output as barrier to AI-assisted monitoring and remediation.

**Independent Test**: Can be fully tested by running scripts with `--json` flag and verifying output is valid, parseable JSON.

**Acceptance Scenarios**:

1. **Given** deploy script is run with `--json`, **When** execution completes, **Then** output is valid JSON with status, version, and timing fields
2. **Given** backup script is run with `--json`, **When** backup completes, **Then** output includes backup path, size, checksum, and status
3. **Given** script fails, **When** `--json` flag is used, **Then** error details are included in structured JSON format

---

### User Story 6 - Pre-Flight Validation (Priority: P2)

As a deployment operator, I need early validation of required secrets so that deployments fail fast with clear error messages.

**Why this priority**: DevOps Engineer recommended secrets validation in pre-flight gate to prevent mid-deployment failures.

**Independent Test**: Can be fully tested by intentionally removing a secret and verifying pre-flight fails with clear message.

**Acceptance Scenarios**:

1. **Given** all required secrets exist, **When** pre-flight gate runs, **Then** deployment proceeds to next stage
2. **Given** a required secret is missing, **When** pre-flight gate runs, **Then** deployment fails immediately with secret name in error
3. **Given** pre-flight passes, **When** subsequent stages fail, **Then** failure is not due to missing secrets

---

### User Story 7 - Unified Configuration (Priority: P2)

As a platform maintainer, I need consistent patterns between development and production compose files so that behavior is predictable across environments.

**Why this priority**: IaC Expert identified config drift between compose files as maintenance burden.

**Independent Test**: Can be fully tested by verifying YAML anchors exist in base compose and both files validate successfully.

**Acceptance Scenarios**:

1. **Given** YAML anchors are defined, **When** compose config is validated, **Then** both dev and prod files parse without errors
2. **Given** common settings are anchored, **When** setting needs update, **Then** single anchor update affects both environments
3. **Given** unified structure, **When** new service is added, **Then** consistent pattern is followed

---

### Edge Cases

- What happens when S3 bucket is unreachable? → Local backup should succeed, alert should fire for S3 failure
- What happens when backup encryption key is lost? → Document key recovery procedure, store key in multiple secure locations
- What happens when pinned image version is deleted from registry? → Fail deployment with clear error, maintain local copy of critical images
- What happens when secrets rotation occurs during deployment? → Deployment should use secrets at start time, document rotation procedure
- What happens when JSON output exceeds terminal buffer? → Output to file when `--json-file` flag is used

## Requirements *(mandatory)*

### Functional Requirements

**Backup & Recovery**
- **FR-001**: System MUST create automated daily backups without manual intervention
- **FR-002**: System MUST upload backups to S3-compatible storage within 1 hour of creation
- **FR-003**: System MUST encrypt backups using AES-256 before upload
- **FR-004**: System MUST alert administrators within 5 minutes of backup failure
- **FR-005**: System MUST support restore from any backup within 30 days retention window

**Secrets Management**
- **FR-006**: System MUST store all API keys as Docker secrets, not environment variables
- **FR-007**: System MUST validate all required secrets exist before deployment starts
- **FR-008**: System MUST fail deployment with clear error message when secrets are missing
- **FR-009**: System MUST NOT expose secrets in container inspection output

**Image Management**
- **FR-010**: System MUST use specific version tags for all Docker images (no `:latest`)
- **FR-011**: System MUST document version update procedure
- **FR-012**: System MUST support rollback to previous known-good version

**GitOps Compliance**
- **FR-013**: System MUST sync entire configuration files from git (not partial updates)
- **FR-014**: System MUST record git commit SHA for each deployment
- **FR-015**: System MUST detect and alert on configuration drift

**AI Integration**
- **FR-016**: System MUST support `--json` output flag for deployment scripts
- **FR-017**: System MUST include status, version, and timing in JSON output
- **FR-018**: System MUST support `--no-color` flag for plain text output

**Configuration Consistency**
- **FR-019**: System MUST use YAML anchors for common configuration patterns
- **FR-020**: System MUST pass `docker compose config --quiet` validation for all compose files

### Key Entities

- **Backup**: Represents a point-in-time snapshot with metadata (timestamp, size, checksum, S3 location, encryption status)
- **Secret**: Represents a sensitive credential with metadata (name, file path, required-by services)
- **Deployment**: Represents a deployment event with metadata (git SHA, image versions, timestamp, status)
- **Alert**: Represents a notification event with metadata (type, severity, timestamp, resolution status)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Daily backups complete successfully 99.9% of the time (max 1 failure per 3 years)
- **SC-002**: Backup restore completes within 15 minutes (RTO target)
- **SC-003**: Zero secrets visible in container environment inspection
- **SC-004**: Deployment fails within 30 seconds when secrets are missing (fail-fast)
- **SC-005**: All images use pinned versions with 100% coverage (no `:latest` tags)
- **SC-006**: GitOps compliance verification passes on 100% of deployments
- **SC-007**: JSON output parses successfully with standard JSON tools (jq, python json)
- **SC-008**: Pre-flight validation completes in under 60 seconds
- **SC-009**: Configuration drift detection identifies any deviation within 6 hours

### Quality Metrics

- **SC-010**: GitOps compliance score maintains 100% (up from 95%)
- **SC-011**: Security audit passes with zero critical findings related to secrets management
- **SC-012**: Recovery test succeeds on first attempt (documented and tested procedure)

## Assumptions

- S3-compatible storage already exists or will be provisioned
- Backup encryption key is stored securely and accessible for recovery
- Existing backup scripts can be extended (not rewritten from scratch)
- GitHub Actions secrets are already configured for CI/CD access
- Docker Compose is the deployment orchestration tool (no Kubernetes migration)
- Single-node deployment (no high-availability changes in this feature)
