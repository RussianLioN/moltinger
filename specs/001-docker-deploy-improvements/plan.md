# Implementation Plan: Docker Deployment Improvements

**Branch**: `001-docker-deploy-improvements` | **Date**: 2026-02-28 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-docker-deploy-improvements/spec.md`

## Summary

Improve Docker deployment process based on Consilium expert panel recommendations (19 experts). Focus areas: automated S3 backups, secure secrets management, reproducible deployments with pinned versions, GitOps compliance, AI-ready output modes, and unified configuration patterns.

## Technical Context

**Language/Version**: Bash 5.x, YAML 1.2, TOML 1.0
**Primary Dependencies**: Docker Compose v2, GitHub Actions, Prometheus, AlertManager, Traefik
**Storage**: Docker volumes (bind mounts + named volumes), S3-compatible storage for backups
**Testing**: Shell script validation (shellcheck), docker compose config validation, smoke tests
**Target Platform**: Linux server (Docker host)
**Project Type**: Infrastructure deployment (single project)
**Performance Goals**: Deployment <5min, backup <15min, restore <15min RTO
**Constraints**: GitOps compliance required, no breaking changes to existing deployment
**Scale/Scope**: Single-node deployment, ~7 services (Moltis, Watchtower, cAdvisor, Prometheus, AlertManager, Traefik)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-First Development | ✅ Pass | Consilium provided comprehensive context from 19 experts |
| II. Single Source of Truth | ✅ Pass | YAML anchors will centralize common config |
| III. Library-First Development | ✅ Pass | Using existing tools (Docker secrets, cron, rclone) |
| IV. Code Reuse & DRY | ✅ Pass | Extending existing backup/deploy scripts |
| V. Strict Type Safety | ⚪ N/A | Infrastructure project (Bash/YAML) |
| VI. Atomic Task Execution | ✅ Pass | 8 atomic tasks defined |
| VII. Quality Gates | ✅ Pass | docker compose config validation, smoke tests |
| VIII. Progressive Specification | ✅ Pass | Spec → Plan → Tasks workflow |
| IX. Error Handling | ✅ Pass | Structured error messages, fail-fast |
| X. Observability | ✅ Pass | Prometheus alerts for backups |
| XI. Accessibility | ⚪ N/A | Infrastructure project |

**Gate Status**: ✅ PASS - All applicable principles satisfied

## Project Structure

### Documentation (this feature)

```text
specs/001-docker-deploy-improvements/
├── spec.md              # Feature specification ✅
├── plan.md              # This file ✅
├── research.md          # Phase 0 output (to be created)
├── data-model.md        # Phase 1 output (to be created)
├── quickstart.md        # Phase 1 output (to be created)
├── contracts/           # Phase 1 output (to be created)
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
# Infrastructure Project Structure
docker-compose.yml           # Development compose
docker-compose.prod.yml      # Production compose
config/
├── moltis.toml             # Moltis configuration
├── prometheus/
│   └── prometheus.yml      # Prometheus config
├── alertmanager/
│   └── alertmanager.yml    # AlertManager config
└── backup/
    └── backup.conf         # Backup configuration

scripts/
├── deploy.sh               # Main deployment script
├── backup-moltis-enhanced.sh  # Backup automation
├── health-monitor.sh       # Health monitoring
├── gitops-guards.sh        # GitOps compliance checks
└── gitops-metrics.sh       # Metrics collection

secrets/                     # Docker secrets (gitignored)
├── moltis_password.txt
├── telegram_bot_token.txt
├── tavily_api_key.txt
└── glm_api_key.txt

.github/workflows/
├── deploy.yml              # Main deployment workflow
├── uat-gate.yml            # UAT approval workflow
└── gitops-drift-detection.yml  # Drift detection
```

**Structure Decision**: Infrastructure project - using existing Docker Compose + Bash scripts structure. No code changes needed, only configuration and script enhancements.

## Complexity Tracking

> No constitution violations - all principles satisfied or N/A for infrastructure project.

| Aspect | Approach | Rationale |
|--------|----------|-----------|
| Secrets Management | Docker secrets | Native Docker solution, no external dependencies |
| Backup Storage | S3 via rclone | Industry standard, already partially configured |
| Cron Scheduling | systemd timer | More robust than cron, better logging |
| JSON Output | Bash functions | Lightweight, no external dependencies |
