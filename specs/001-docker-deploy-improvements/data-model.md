# Data Model: Docker Deployment Improvements

**Feature**: 001-docker-deploy-improvements
**Date**: 2026-02-28

## Entities

### 1. Backup

Represents a point-in-time snapshot of Moltis data and configuration.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| id | string | Unique backup identifier | UUID format |
| timestamp | datetime | Backup creation time | ISO 8601 |
| type | enum | Backup type | `manual`, `scheduled`, `pre-deploy` |
| status | enum | Backup status | `pending`, `in_progress`, `success`, `failed` |
| size_bytes | integer | Backup file size | > 0 |
| checksum | string | SHA256 checksum | 64 hex chars |
| encryption | boolean | Whether encrypted | true |
| s3_location | string | S3 path | `s3://bucket/path/file.tar.gz.aes` |
| local_path | string | Local backup path | `/var/backups/moltis/...` |
| retention_days | integer | Days to retain | 30, 90, or 365 |
| metadata | object | Additional info | JSON object |

**State Transitions**:
```
pending → in_progress → success
                    ↘ failed
```

### 2. Secret

Represents a sensitive credential stored as Docker secret.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| name | string | Secret name | `[a-z_]+` pattern |
| file_path | string | Path to secret file | `/run/secrets/{name}` |
| required_by | array | Services using this secret | List of service names |
| rotation_policy | enum | How to rotate | `manual`, `scheduled` |
| last_rotated | datetime | Last rotation time | ISO 8601 or null |

**Secrets Inventory**:
| Secret Name | Used By | Source |
|-------------|---------|--------|
| moltis_password | moltis | GitHub Secret |
| telegram_bot_token | moltis | GitHub Secret |
| tavily_api_key | moltis | GitHub Secret |
| glm_api_key | moltis | GitHub Secret |
| smtp_password | watchtower | GitHub Secret |

### 3. Deployment

Represents a deployment event with full audit trail.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| id | string | Deployment identifier | Commit SHA |
| timestamp | datetime | Deployment time | ISO 8601 |
| trigger | enum | What triggered deploy | `push`, `manual`, `scheduled` |
| status | enum | Deployment status | `pending`, `running`, `success`, `failed`, `rolled_back` |
| git_ref | string | Git reference | Branch or tag |
| image_versions | object | Image versions deployed | `{service: version}` |
| duration_ms | integer | Deployment duration | >= 0 |
| health_status | enum | Post-deploy health | `healthy`, `unhealthy`, `unknown` |
| rollback_available | boolean | Can rollback | true/false |

**State Transitions**:
```
pending → running → success
                ↘ failed → rolled_back
```

### 4. Alert

Represents a monitoring alert event.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| name | string | Alert rule name | Non-empty |
| severity | enum | Alert severity | `critical`, `warning`, `info` |
| status | enum | Alert status | `firing`, `resolved` |
| labels | object | Alert labels | Key-value pairs |
| annotations | object | Alert details | Key-value pairs |
| starts_at | datetime | Alert start time | ISO 8601 |
| ends_at | datetime | Alert end time | ISO 8601 or null |

**Backup Alert Rules**:
| Alert Name | Severity | Condition | Threshold |
|------------|----------|-----------|-----------|
| BackupFailed | critical | backup_status == failed | immediate |
| BackupMissing | warning | last_backup > 24h | 1 hour |
| BackupStorageFull | critical | s3_storage > 90% | immediate |
| BackupRestoreFailed | critical | restore_status == failed | immediate |

---

## Relationships

```
Deployment 1──* Backup (pre-deploy backup created for each deployment)
Backup *──1 Secret (backup may include encrypted secrets metadata)
Alert *──1 Backup (alerts reference backup status)
Deployment *──* Secret (deployment validates secrets exist)
```

---

## Metrics Schema

Prometheus metrics exposed by backup script:

```promql
# Backup metrics
moltis_backup_status{status="success|failed"} 0|1
moltis_backup_duration_seconds 123.45
moltis_backup_size_bytes 1048576
moltis_backup_last_success_timestamp 1705312800

# Deployment metrics
moltis_deployment_status{status="success|failed"} 0|1
moltis_deployment_duration_seconds 45.2
moltis_deployment_rollback_available 1
```

---

## File Formats

### Backup Metadata File (`backup-meta.json`)

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2024-01-15T02:00:00Z",
  "type": "scheduled",
  "status": "success",
  "size_bytes": 1048576,
  "checksum": "abc123...",
  "encryption": true,
  "s3_location": "s3://backups/moltis/2024-01-15.tar.gz.aes",
  "local_path": "/var/backups/moltis/2024-01-15.tar.gz.aes",
  "retention_days": 30,
  "git_sha": "abc123def456",
  "image_versions": {
    "moltis": "v1.7.0",
    "watchtower": "v1.6.0"
  }
}
```

### Deployment Status File (`deploy-status.json`)

```json
{
  "id": "abc123def456",
  "timestamp": "2024-01-15T10:30:00Z",
  "trigger": "push",
  "status": "success",
  "git_ref": "main",
  "image_versions": {
    "moltis": "ghcr.io/moltis-org/moltis:v1.7.0@sha256:abc123",
    "watchtower": "containrrr/watchtower:v1.6.0"
  },
  "duration_ms": 45000,
  "health_status": "healthy",
  "rollback_available": true
}
```
