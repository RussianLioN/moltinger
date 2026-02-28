# Research: Docker Deployment Improvements

**Feature**: 001-docker-deploy-improvements
**Date**: 2026-02-28
**Status**: Complete

## Research Summary

Based on Consilium expert panel analysis (19 experts), the following research was conducted to resolve technical questions for implementation.

---

## 1. S3 Backup Integration

### Decision: Use rclone for S3 uploads

**Rationale**:
- Already used in existing `backup-moltis-enhanced.sh` script
- Supports multiple S3-compatible providers (AWS, Backblaze, Wasabi, MinIO)
- Built-in retry logic and progress reporting
- Industry standard for cloud storage sync

**Alternatives Considered**:
| Tool | Rejected Because |
|------|------------------|
| AWS CLI | AWS-specific, doesn't support other S3 providers |
| s3cmd | Less maintained, fewer features than rclone |
| restic | Overkill for simple file backup, steeper learning curve |

**Library**: rclone v1.65+ (already installed on target system)

---

## 2. Cron/Systemd Scheduling

### Decision: Use systemd timer with OnCalendar

**Rationale**:
- More robust than cron (auto-restart on failure)
- Better logging via journalctl
- Native dependency management (After=, Requires=)
- RandomizedDelaySec prevents thundering herd

**Implementation Pattern**:
```ini
# /etc/systemd/system/moltis-backup.timer
[Unit]
Description=Daily Moltis Backup

[Timer]
OnCalendar=*-*-* 02:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
```

**Alternatives Considered**:
| Tool | Rejected Because |
|------|------------------|
| cron | Less robust, no native retry, poorer logging |
| Kubernetes CronJob | Not using Kubernetes |
| GitHub Actions scheduled | Requires external trigger, less reliable |

---

## 3. Docker Secrets Management

### Decision: Use Docker Compose secrets with file backend

**Rationale**:
- Native Docker Compose support (no external tools)
- Files can be managed via deployment scripts
- Works with existing GitHub Actions secrets workflow
- Secrets visible only to containers that need them

**Implementation Pattern**:
```yaml
secrets:
  telegram_bot_token:
    file: ./secrets/telegram_bot_token.txt

services:
  moltis:
    secrets:
      - telegram_bot_token
    environment:
      - TELEGRAM_BOT_TOKEN_FILE=/run/secrets/telegram_bot_token
```

**Alternatives Considered**:
| Tool | Rejected Because |
|------|------------------|
| HashiCorp Vault | Overkill for single-node, adds complexity |
| Docker Swarm secrets | Requires Swarm mode |
| SOPS | Adds encryption layer, but still needs file distribution |

---

## 4. Image Version Pinning Strategy

### Decision: Semantic versioning with SHA256 digest

**Rationale**:
- Semantic version (v1.7.0) for readability
- SHA256 digest for immutability guarantee
- Document update process in Makefile

**Implementation Pattern**:
```yaml
image: ghcr.io/moltis-org/moltis:v1.7.0@sha256:abc123...
```

**Version Update Process**:
1. Check available versions: `git tag -l` or GitHub releases
2. Update docker-compose.yml with new version
3. Run `docker compose pull` to verify image exists
4. Commit and push (triggers deployment)

---

## 5. GitOps Compliance Fix

### Decision: Replace sed with full file scp

**Rationale**:
- Full file sync maintains git as source of truth
- No partial updates that cause drift
- Audit trail preserved in git history

**Current Anti-Pattern (uat-gate.yml:273)**:
```yaml
# ❌ WRONG: Partial update
- run: ssh $HOST "sed -i 's|image:.*|image: $IMAGE|' docker-compose.yml"
```

**Correct Pattern (from deploy.yml:357)**:
```yaml
# ✅ CORRECT: Full file sync
- uses: actions/checkout@v4
- run: scp docker-compose.yml $SSH_USER@$SSH_HOST:$DEPLOY_PATH/
```

---

## 6. JSON Output Mode

### Decision: Add --json flag to existing scripts

**Rationale**:
- Backward compatible (existing behavior unchanged)
- Enables AI-assisted monitoring and remediation
- Simple implementation with jq or native Bash

**Implementation Pattern**:
```bash
# Output format
{
  "status": "success|failure",
  "timestamp": "2024-01-15T10:30:00Z",
  "action": "deploy|backup|health-check",
  "details": {
    "image": "ghcr.io/moltis-org/moltis:v1.7.0",
    "duration_ms": 45000,
    "health": "healthy"
  },
  "errors": []
}
```

---

## 7. Backup Alerts

### Decision: Add Prometheus alerting rules for backup status

**Rationale**:
- Integrates with existing Prometheus/AlertManager stack
- Alert routing already configured
- Backup script can expose metrics file

**Alert Rules to Add**:
```yaml
# config/prometheus/backup_rules.yml
groups:
  - name: backup_alerts
    rules:
      - alert: BackupFailed
        expr: moltis_backup_status{status="failed"} > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Moltis backup failed"

      - alert: BackupMissing
        expr: time() - moltis_backup_last_success_timestamp > 86400
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "No successful backup in 24 hours"
```

---

## 8. YAML Anchors for Unified Configuration

### Decision: Create common anchors in base docker-compose.yml

**Rationale**:
- DRY principle - common config defined once
- Consistency between dev and prod
- Easier maintenance

**Implementation Pattern**:
```yaml
# docker-compose.yml
x-common-env: &common-env
  MOLTIS_HOST: 0.0.0.0
  MOLTIS_NO_TLS: true
  MOLTIS_BEHIND_PROXY: true

x-healthcheck: &healthcheck
  test: ["CMD", "curl", "-f", "http://localhost:13131/health"]
  interval: 30s
  timeout: 10s
  retries: 3

services:
  moltis:
    environment:
      <<: *common-env
    healthcheck:
      <<: *healthcheck
```

---

## Dependencies Identified

| Dependency | Purpose | Version | Install Command |
|------------|---------|---------|-----------------|
| rclone | S3 sync | v1.65+ | `brew install rclone` or `apt install rclone` |
| jq | JSON output | v1.6+ | Already installed |
| curl | Health checks | Any | Already installed |
| systemd | Timer scheduling | v245+ | OS package |

---

## Open Questions Resolved

| Question | Resolution |
|----------|------------|
| S3 provider choice | Backward compatible - support any S3-compatible provider |
| Schedule time | 02:00 UTC (configurable via systemd timer) |
| Retention policy | 30 days daily, 12 weeks weekly, 12 months monthly (existing) |
| Alert routing | Use existing AlertManager configuration |

---

## References

- [Docker Compose secrets](https://docs.docker.com/compose/use-secrets/)
- [systemd timer documentation](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)
- [rclone S3 documentation](https://rclone.org/s3/)
- [Prometheus alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
