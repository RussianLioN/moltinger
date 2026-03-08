# JSON Output Format Documentation

**Feature**: 001-docker-deploy-improvements
**Last Updated**: 2026-02-28

## Overview

All deployment and backup scripts support a `--json` flag for machine-parsable output. This enables CI/CD integration, monitoring systems, and automated tooling to consume script results programmatically.

**Enabling JSON Output:**

```bash
./scripts/deploy.sh deploy --json
./scripts/backup-moltis-enhanced.sh backup --json
./scripts/health-monitor.sh --once --json
./scripts/preflight-check.sh --json
```

---

## Common Response Structure

All JSON responses follow a consistent structure:

```json
{
  "status": "success|failure|pass|fail|healthy|unhealthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "action": "deploy|backup|restore|check|health",
  "details": { ... },
  "errors": []
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | Operation result status |
| `timestamp` | string | ISO 8601 timestamp of operation |
| `action` | string | The action that was performed |
| `details` | object | Action-specific details |
| `errors` | array | List of error objects (empty if success) |

### Error Object Structure

```json
{
  "code": "ERROR_CODE",
  "message": "Human-readable error message",
  "service": "affected_service_name"
}
```

---

## 1. deploy.sh JSON Output

### Success Response

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

### Error Response

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

### Fields Reference

| Field | Type | Description |
|-------|------|-------------|
| `details.image` | string | Full image reference deployed |
| `details.duration_ms` | number | Total deployment time in milliseconds |
| `details.health` | string | Post-deploy health status |
| `details.services` | array | List of services deployed |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Configuration error |
| 3 | Health check failed |
| 4 | Pre-flight validation failed |
| 5 | Rollback triggered |

### Commands

| Command | Description |
|---------|-------------|
| `deploy` | Deploy the stack |
| `rollback` | Rollback to previous version |
| `status` | Show deployment status |
| `health` | Check health status |

---

## 2. backup-moltis-enhanced.sh JSON Output

### Backup Success Response

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

### Restore Success Response

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

### List Response

```json
{
  "status": "success",
  "timestamp": "2024-01-15T10:00:00Z",
  "action": "list",
  "details": {
    "backups": [
      {
        "filename": "2024-01-15.tar.gz.aes",
        "size_bytes": 1048576,
        "timestamp": "2024-01-15T02:00:00Z",
        "encrypted": true
      },
      {
        "filename": "2024-01-14.tar.gz.aes",
        "size_bytes": 1024000,
        "timestamp": "2024-01-14T02:00:00Z",
        "encrypted": true
      }
    ],
    "total_count": 2
  },
  "errors": []
}
```

### Fields Reference

| Field | Type | Description |
|-------|------|-------------|
| `details.backup_id` | string | UUID of the backup |
| `details.local_path` | string | Local filesystem path |
| `details.s3_location` | string | S3 URI (if uploaded) |
| `details.size_bytes` | number | Backup file size in bytes |
| `details.checksum` | string | SHA256 checksum |
| `details.duration_ms` | number | Operation duration |
| `details.encrypted` | boolean | Whether backup is encrypted |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Backup creation failed |
| 3 | S3 upload failed |
| 4 | Restore failed |
| 5 | Verification failed |

### Commands

| Command | Description |
|---------|-------------|
| `backup` | Create a backup |
| `restore FILE` | Restore from backup file |
| `list` | List available backups |
| `verify FILE` | Verify backup integrity |
| `cleanup` | Remove old backups per retention policy |

---

## 3. health-monitor.sh JSON Output

### Healthy Response

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

### Unhealthy Response

```json
{
  "status": "unhealthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "services": [
    {
      "name": "moltis",
      "status": "unhealthy",
      "uptime_seconds": 3600,
      "health_endpoint": "http://localhost:13131/health",
      "last_error": "Connection refused"
    },
    {
      "name": "watchtower",
      "status": "healthy",
      "uptime_seconds": 86400
    }
  ],
  "alerts": [
    {
      "service": "moltis",
      "severity": "critical",
      "message": "Service unhealthy for 5 minutes"
    }
  ]
}
```

### Fields Reference

| Field | Type | Description |
|-------|------|-------------|
| `services` | array | List of service health objects |
| `services[].name` | string | Service name |
| `services[].status` | string | `healthy` or `unhealthy` |
| `services[].uptime_seconds` | number | Container uptime |
| `services[].health_endpoint` | string | Health check URL |
| `services[].last_error` | string | Last error message (if unhealthy) |
| `alerts` | array | Active alerts |

### Options

| Option | Description |
|--------|-------------|
| `--once` | Check once and exit (no monitoring loop) |
| `--interval SEC` | Check interval in seconds (default: 30) |
| `--json` | Output in JSON format |
| `--no-color` | Disable colored output |

---

## 4. preflight-check.sh JSON Output

### Pass Response

```json
{
  "status": "pass",
  "timestamp": "2024-01-15T10:30:00Z",
  "checks": [
    {
      "name": "secrets_exist",
      "status": "pass",
      "message": "All 4 required secrets found",
      "severity": "error"
    },
    {
      "name": "docker_available",
      "status": "pass",
      "message": "Docker daemon is running",
      "severity": "error"
    },
    {
      "name": "compose_valid",
      "status": "pass",
      "message": "docker-compose.yml syntax is valid",
      "severity": "error"
    },
    {
      "name": "network_exists",
      "status": "pass",
      "message": "Network traefik-net exists",
      "severity": "error"
    },
    {
      "name": "s3_credentials",
      "status": "warning",
      "message": "S3 credentials not configured, backup will be local only",
      "severity": "warning"
    },
    {
      "name": "disk_space",
      "status": "pass",
      "message": "50GB free space available",
      "severity": "warning"
    }
  ],
  "missing_secrets": [],
  "errors": [],
  "warnings": ["s3_credentials"]
}
```

### Fail Response

```json
{
  "status": "fail",
  "timestamp": "2024-01-15T10:30:00Z",
  "checks": [
    {
      "name": "secrets_exist",
      "status": "fail",
      "message": "Missing secrets: moltis_password, telegram_bot_token",
      "severity": "error"
    },
    {
      "name": "docker_available",
      "status": "pass",
      "message": "Docker daemon is running",
      "severity": "error"
    },
    {
      "name": "compose_valid",
      "status": "fail",
      "message": "Invalid YAML syntax at line 42",
      "severity": "error"
    }
  ],
  "missing_secrets": ["moltis_password", "telegram_bot_token"],
  "errors": ["secrets_exist", "compose_valid"],
  "warnings": []
}
```

### Validation Checks

| Check | Description | Severity |
|-------|-------------|----------|
| `secrets_exist` | All required secrets present | error |
| `docker_available` | Docker daemon running | error |
| `compose_valid` | docker-compose.yml syntax | error |
| `network_exists` | Required networks exist | error |
| `s3_credentials` | S3 credentials configured | warning |
| `disk_space` | Sufficient disk space | warning |

### Fields Reference

| Field | Type | Description |
|-------|------|-------------|
| `checks` | array | List of validation check results |
| `checks[].name` | string | Check identifier |
| `checks[].status` | string | `pass`, `fail`, or `warning` |
| `checks[].message` | string | Human-readable result |
| `checks[].severity` | string | `error` or `warning` |
| `missing_secrets` | array | List of missing secret names |
| `errors` | array | Names of failed error-severity checks |
| `warnings` | array | Names of warning-severity checks |

### Options

| Option | Description |
|--------|-------------|
| `--json` | Output in JSON format |
| `--strict` | Fail on warnings (not just errors) |
| `-h, --help` | Show help message |

---

## Integration Examples

### CI/CD Pipeline (GitHub Actions)

```yaml
- name: Run Pre-flight Checks
  id: preflight
  run: |
    RESULT=$(./scripts/preflight-check.sh --json)
    echo "result=$RESULT" >> $GITHUB_OUTPUT
    echo "$RESULT" | jq -e '.status == "pass"'

- name: Deploy
  if: steps.preflight.outputs.result | jq -e '.status == "pass"'
  run: |
    RESULT=$(./scripts/deploy.sh deploy --json)
    echo "$RESULT" | jq -e '.status == "success"'
```

### Monitoring Integration

```bash
# Prometheus node exporter textfile collector
./scripts/health-monitor.sh --once --json | jq '
  .services[] |
  "moltis_service_health{service=\"\(.name)\"} \(.status == "healthy" | tonumber)"
' > /var/lib/node_exporter/textfile_collector/moltis_health.prom
```

### Alerting Hook

```bash
#!/bin/bash
# Post-backup alert hook
RESULT=$(./scripts/backup-moltis-enhanced.sh backup --json)

if [ "$(echo "$RESULT" | jq -r '.status')" != "success" ]; then
  ERROR_MSG=$(echo "$RESULT" | jq -r '.errors[0].message')
  curl -X POST "${WEBHOOK_URL}" \
    -H "Content-Type: application/json" \
    -d "{\"text\": \"Backup failed: $ERROR_MSG\"}"
fi
```

### Parsing with jq

```bash
# Get deployment duration
./scripts/deploy.sh deploy --json | jq '.details.duration_ms'

# Check if any warnings in preflight
./scripts/preflight-check.sh --json | jq 'if .warnings | length > 0 then "warnings" else "clean" end'

# Get backup size
./scripts/backup-moltis-enhanced.sh backup --json | jq '.details.size_bytes'

# Extract all unhealthy services
./scripts/health-monitor.sh --once --json | jq '[.services[] | select(.status == "unhealthy")]'
```

---

## Error Codes Reference

### deploy.sh

| Code | Constant | Description |
|------|----------|-------------|
| 0 | SUCCESS | Operation completed successfully |
| 1 | ERROR | General/unspecified error |
| 2 | CONFIG_ERROR | Configuration file invalid |
| 3 | HEALTH_FAILED | Post-deploy health check failed |
| 4 | PREFLIGHT_FAILED | Pre-flight validation failed |
| 5 | ROLLBACK | Deployment rolled back |

### backup-moltis-enhanced.sh

| Code | Constant | Description |
|------|----------|-------------|
| 0 | SUCCESS | Operation completed successfully |
| 1 | ERROR | General/unspecified error |
| 2 | BACKUP_FAILED | Backup creation failed |
| 3 | S3_FAILED | S3 upload/download failed |
| 4 | RESTORE_FAILED | Restore operation failed |
| 5 | VERIFY_FAILED | Backup verification failed |

---

## Best Practices

1. **Always check exit codes** - JSON output is only generated on clean exits
2. **Validate JSON before parsing** - Use `jq -e` to catch malformed output
3. **Handle timeouts** - Scripts may hang; use `timeout` command in CI
4. **Log raw output** - Store full JSON for debugging failures
5. **Use `--no-color` in CI** - Prevents ANSI escape codes in logs

```bash
# Recommended CI pattern
set -euo pipefail
./scripts/preflight-check.sh --json --no-color 2>&1 | tee preflight-result.json
jq -e '.status == "pass"' preflight-result.json
```
