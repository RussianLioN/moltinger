# Quickstart: Docker Deployment Improvements

**Feature**: 001-docker-deploy-improvements
**Date**: 2026-02-28

## Prerequisites

- Docker 24.0+ and Docker Compose v2
- Server access (SSH)
- S3-compatible storage credentials (optional but recommended)
- GitHub repository access with secrets configured

## 5-Minute Setup

### Step 1: Configure Secrets

```bash
# Create secrets directory
mkdir -p secrets

# Create secret files from GitHub Secrets
echo "${MOLTIS_PASSWORD}" > secrets/moltis_password.txt
echo "${TELEGRAM_BOT_TOKEN}" > secrets/telegram_bot_token.txt
echo "${TAVILY_API_KEY}" > secrets/tavily_api_key.txt
echo "${GLM_API_KEY}" > secrets/glm_api_key.txt

# Set permissions
chmod 600 secrets/*.txt
```

### Step 2: Verify Configuration

```bash
# Validate docker-compose syntax
docker compose config --quiet

# Run pre-flight checks
./scripts/preflight-check.sh --json
```

### Step 3: Deploy

```bash
# Deploy with health check
./scripts/deploy.sh deploy --json

# Expected output:
# {"status": "success", "health": "healthy", ...}
```

### Step 4: Enable Automated Backups

```bash
# Install systemd timer
sudo cp systemd/moltis-backup.timer /etc/systemd/system/
sudo cp systemd/moltis-backup.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now moltis-backup.timer

# Verify timer is active
systemctl list-timers | grep moltis
```

### Step 5: Verify Setup

```bash
# Check health
./scripts/health-monitor.sh --once --json

# Test backup
./scripts/backup-moltis-enhanced.sh backup --json

# View deployment status
./scripts/deploy.sh status --json
```

---

## Common Tasks

### Manual Backup

```bash
# Create backup immediately
./scripts/backup-moltis-enhanced.sh backup

# Verify backup
./scripts/backup-moltis-enhanced.sh verify /var/backups/moltis/latest.tar.gz.aes
```

### Restore from Backup

```bash
# List available backups
./scripts/backup-moltis-enhanced.sh list --json

# Restore specific backup
./scripts/backup-moltis-enhanced.sh restore /var/backups/moltis/2024-01-15.tar.gz.aes
```

### Rollback Deployment

```bash
# Rollback to previous version
./scripts/deploy.sh rollback --json
```

### Update Image Version

```bash
# 1. Edit docker-compose.yml with new version
vim docker-compose.yml

# 2. Validate configuration
docker compose config --quiet

# 3. Deploy new version
./scripts/deploy.sh deploy --json

# 4. Verify health
./scripts/health-monitor.sh --once --json
```

---

## Troubleshooting

### Backup Fails

```bash
# Check S3 credentials
rclone config show

# Test S3 connectivity
rclone ls backup-s3:moltis-backups/

# Check disk space
df -h /var/backups

# View backup logs
journalctl -u moltis-backup.service -f
```

### Secrets Missing

```bash
# Check which secrets exist
ls -la secrets/

# Validate all secrets
./scripts/preflight-check.sh --json | jq '.missing_secrets'

# Recreate missing secrets
echo "${SECRET_VALUE}" > secrets/secret_name.txt
chmod 600 secrets/secret_name.txt
```

### Health Check Fails

```bash
# Check container logs
docker logs moltis --tail 100

# Check container status
docker ps -a | grep moltis

# Manual health check
curl -f http://localhost:13131/health

# Restart container
docker compose restart moltis
```

### Deployment Stuck

```bash
# Check deployment status
./scripts/deploy.sh status --json

# Force rollback if needed
./scripts/deploy.sh rollback --force

# Check Docker events
docker events --filter 'type=container'
```

---

## Monitoring

### Prometheus Metrics

Access at `http://localhost:9090`

**Key Metrics:**
- `moltis_backup_status` - Backup success/failure
- `moltis_deployment_status` - Deployment status
- `up{job="moltis"}` - Service availability

### AlertManager Alerts

Access at `http://localhost:9093`

**Critical Alerts:**
- `BackupFailed` - Backup creation failed
- `MoltisDown` - Service unavailable
- `BackupMissing` - No backup in 24 hours

### Grafana Dashboard

Access at `http://localhost:3000` (if configured)

---

## File Locations

| File | Purpose |
|------|---------|
| `/var/backups/moltis/` | Local backup storage |
| `/etc/systemd/system/moltis-backup.*` | Systemd timer/service |
| `secrets/` | Docker secrets files |
| `config/backup/backup.conf` | Backup configuration |
| `/var/log/moltis/` | Application logs |

---

## Next Steps

1. **Configure AlertManager routing** for backup alerts
2. **Set up Grafana dashboards** for visualization
3. **Test disaster recovery** procedure
4. **Document version update process** for team

---

## Support

- GitHub Issues: https://github.com/RussianLioN/moltinger/issues
- Documentation: `docs/` directory
- Runbook: `docs/runbooks/deployment.md`
