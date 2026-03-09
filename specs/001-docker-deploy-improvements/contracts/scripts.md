# Script Contracts: Docker Deployment Improvements

**Feature**: 001-docker-deploy-improvements
**Date**: 2026-02-28

## Overview

This document defines the interface contracts for deployment and backup scripts. All scripts must follow these contracts for consistent behavior and AI-parsable output.

---

## 1. deploy.sh Contract

### Synopsis

```bash
./scripts/deploy.sh [OPTIONS] COMMAND

OPTIONS:
  --json           Output in JSON format
  --no-color       Disable colored output
  --dry-run        Show what would be done without executing
  -h, --help       Show help message

COMMANDS:
  deploy           Deploy the stack
  rollback         Rollback to previous version
  status           Show deployment status
  health           Check health status
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Configuration error |
| 3 | Health check failed |
| 4 | Pre-flight validation failed |
| 5 | Rollback triggered |

### JSON Output Format

**Success Response:**
```json
{
  "status": "success",
  "timestamp": "2024-01-15T10:30:00Z",
  "action": "deploy",
  "details": {
    "image": "ghcr.io/moltis-org/moltis:v1.7.0",
    "duration_ms": 45000,
    "health": "healthy",
    "services": ["moltis", "watchtower"]
  },
  "errors": []
}
```

**Error Response:**
```json
{
  "status": "failure",
  "timestamp": "2024-01-15T10:30:00Z",
  "action": "deploy",
  "details": {},
  "errors": [
    {
      "code": "HEALTH_CHECK_FAILED",
      "message": "Container unhealthy after 3 retries",
      "service": "moltis"
    }
  ]
}
```

---

## 2. backup-moltis-enhanced.sh Contract

### Synopsis

```bash
./scripts/backup-moltis-enhanced.sh [OPTIONS] COMMAND

OPTIONS:
  --json           Output in JSON format
  --no-color       Disable colored output
  --no-upload      Skip S3 upload
  --no-encrypt     Skip encryption (NOT RECOMMENDED)
  -h, --help       Show help message

COMMANDS:
  backup           Create a backup
  restore FILE     Restore from backup file
  list             List available backups
  verify FILE      Verify backup integrity
  cleanup          Remove old backups per retention policy
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Backup creation failed |
| 3 | S3 upload failed |
| 4 | Restore failed |
| 5 | Verification failed |

### JSON Output Format

**Backup Success:**
```json
{
  "status": "success",
  "timestamp": "2024-01-15T02:00:00Z",
  "action": "backup",
  "details": {
    "backup_id": "550e8400-e29b-41d4-a716-446655440000",
    "local_path": "/var/backups/moltis/2024-01-15.tar.gz.aes",
    "s3_location": "s3://backups/moltis/2024-01-15.tar.gz.aes",
    "size_bytes": 1048576,
    "checksum": "abc123def456...",
    "duration_ms": 45000,
    "encrypted": true
  },
  "errors": []
}
```

**Restore Request:**
```json
{
  "status": "success",
  "timestamp": "2024-01-15T10:00:00Z",
  "action": "restore",
  "details": {
    "source": "/var/backups/moltis/2024-01-15.tar.gz.aes",
    "backup_timestamp": "2024-01-15T02:00:00Z",
    "duration_ms": 120000,
    "services_restored": ["moltis"]
  },
  "errors": []
}
```

---

## 3. health-monitor.sh Contract

### Synopsis

```bash
./scripts/health-monitor.sh [OPTIONS]

OPTIONS:
  --json           Output in JSON format
  --no-color       Disable colored output
  --once           Check once and exit (no monitoring loop)
  --interval SEC   Check interval in seconds (default: 30)
  -h, --help       Show help message
```

### JSON Output Format

```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "services": [
    {
      "name": "moltis",
      "status": "healthy",
      "uptime_seconds": 86400,
      "health_endpoint": "http://localhost:13131/health"
    },
    {
      "name": "watchtower",
      "status": "healthy",
      "uptime_seconds": 86400
    }
  ],
  "alerts": []
}
```

---

## 4. Pre-flight Validation Contract

### Synopsis

```bash
./scripts/preflight-check.sh [OPTIONS]

OPTIONS:
  --json             Output in JSON format
  --strict           Fail on warnings (not just errors)
  --ci               CI mode (skip Docker daemon and runtime checks)
  --target <name>    Validation target (moltis|clawdiy)
  -h, --help         Show help message
```

### Validation Checks

| Check | Description | Severity |
|-------|-------------|----------|
| secrets_exist | All required secrets present | error |
| docker_available | Docker daemon running | error |
| compose_valid | Target-specific compose syntax | error |
| network_exists | Required networks exist | error |
| s3_credentials | S3 credentials configured | warning |
| disk_space | Sufficient disk space | warning |

Target-aware additions:
- `--target clawdiy` validates `docker-compose.clawdiy.yml`
- `--target clawdiy` parses `config/clawdiy/openclaw.json`, `config/fleet/agents-registry.json`, and `config/fleet/policy.json`
- `--target clawdiy` fails on duplicate agent/domain/Telegram identity collisions and on reused Moltinger secret refs

### JSON Output Format

```json
{
  "status": "pass",
  "target": "clawdiy",
  "timestamp": "2024-01-15T10:30:00Z",
  "checks": [
    {
      "name": "secrets_exist",
      "status": "pass",
      "message": "All required secrets found for target clawdiy",
      "severity": "error"
    },
    {
      "name": "s3_credentials",
      "status": "warning",
      "message": "S3 credentials not configured, backup will be local only",
      "severity": "warning"
    }
  ],
  "missing_secrets": [],
  "errors": [],
  "warnings": ["Optional secret 'smtp_password' not found for target moltis"]
}
```

`errors` and `warnings` contain the emitted validation messages, not just check ids.

---

## 5. GitHub Actions Workflow Contract

### Workflow Inputs

| Input | Type | Required | Description |
|-------|------|----------|-------------|
| environment | string | yes | Target environment (production/staging) |
| version | string | no | Specific version to deploy |
| dry_run | boolean | no | Perform dry run only |

### Workflow Outputs

| Output | Type | Description |
|--------|------|-------------|
| deployment_status | string | success/failure/rolled_back |
| deployment_id | string | Commit SHA |
| health_status | string | healthy/unhealthy |

### Required Secrets

| Secret | Used In | Description |
|--------|---------|-------------|
| SSH_PRIVATE_KEY | deploy.yml | SSH key for server access |
| SSH_HOST | deploy.yml | Server hostname |
| SSH_USER | deploy.yml | SSH username |
| MOLTIS_PASSWORD | deploy.yml | Moltis admin password |
| TELEGRAM_BOT_TOKEN | deploy.yml | Telegram integration |
| TAVILY_API_KEY | deploy.yml | Tavily search API |
| GLM_API_KEY | deploy.yml | GLM AI API |
| S3_ACCESS_KEY | backup | S3 access key |
| S3_SECRET_KEY | backup | S3 secret key |
