# Systemd Timer Setup Documentation

**Feature**: 001-docker-deploy-improvements
**Last Updated**: 2026-02-28

## Overview

Moltis uses systemd timers for automated daily backups. This document explains how to install, configure, and manage the backup timer.

---

## Prerequisites

- Root/sudo access on the server
- Docker installed and running
- Backup script at `/usr/local/bin/backup-moltis-enhanced.sh`

---

## Installation

### Step 1: Copy Service and Timer Files

```bash
# Copy systemd files
sudo cp systemd/moltis-backup.timer /etc/systemd/system/
sudo cp systemd/moltis-backup.service /etc/systemd/system/
```

### Step 2: Reload Systemd

```bash
# Reload systemd to recognize new units
sudo systemctl daemon-reload
```

### Step 3: Enable and Start Timer

```bash
# Enable timer to start on boot and start immediately
sudo systemctl enable --now moltis-backup.timer
```

### Step 4: Verify Installation

```bash
# Check timer status
systemctl status moltis-backup.timer

# List all timers
systemctl list-timers | grep moltis
```

Expected output:
```
Fri 2024-01-16 02:00:00 UTC  14h left  n/a  n/a  moltis-backup.timer
```

---

## Timer Configuration

### Schedule

The timer runs daily at 2:00 AM UTC with a 1-hour random delay to avoid thundering herd:

```ini
[Timer]
OnCalendar=*-*-* 02:00:00
RandomizedDelaySec=3600
Persistent=true
```

### Modify Schedule

To change the backup time, edit the timer file:

```bash
# Edit timer
sudo systemctl edit --full moltis-backup.timer
```

Change `OnCalendar` value:

| Schedule | OnCalendar Value |
|----------|------------------|
| Daily at 2 AM | `*-*-* 02:00:00` |
| Daily at 3 AM | `*-*-* 03:00:00` |
| Every 6 hours | `*-*-* 00/6:00:00` |
| Twice daily | `*-*-* 02,14:00:00` |
| Weekly (Sunday 2 AM) | `Sun *-*-* 02:00:00` |

After editing:
```bash
sudo systemctl daemon-reload
sudo systemctl restart moltis-backup.timer
```

---

## Manual Operations

### Trigger Backup Immediately

```bash
# Start backup service directly
sudo systemctl start moltis-backup.service
```

### Check Backup Status

```bash
# Check if backup is running
systemctl status moltis-backup.service

# Check exit status of last run
systemctl show moltis-backup.service -p ExecMainStatus
```

### Stop Running Backup

```bash
# Stop the backup service
sudo systemctl stop moltis-backup.service
```

---

## Viewing Logs

### Recent Logs

```bash
# View last 50 lines
journalctl -u moltis-backup.service -n 50

# View last 100 lines
journalctl -u moltis-backup.service -n 100
```

### Follow Logs in Real-Time

```bash
# Follow logs
journalctl -u moltis-backup.service -f
```

### Filter by Time

```bash
# Logs from today
journalctl -u moltis-backup.service --since today

# Logs from last hour
journalctl -u moltis-backup.service --since "1 hour ago"

# Logs from specific date
journalctl -u moltis-backup.service --since "2024-01-15"

# Logs between dates
journalctl -u moltis-backup.service --since "2024-01-14" --until "2024-01-16"
```

### Filter by Priority

```bash
# Errors only
journalctl -u moltis-backup.service -p err

# Warnings and above
journalctl -u moltis-backup.service -p warning
```

### Export Logs

```bash
# Export to file
journalctl -u moltis-backup.service --since today > backup-logs.txt

# Export as JSON
journalctl -u moltis-backup.service --since today -o json > backup-logs.json
```

---

## Enable/Disable Timer

### Disable Timer

```bash
# Stop and disable timer
sudo systemctl stop moltis-backup.timer
sudo systemctl disable moltis-backup.timer

# Verify disabled
systemctl is-enabled moltis-backup.timer
# Expected: disabled
```

### Enable Timer

```bash
# Enable and start timer
sudo systemctl enable --now moltis-backup.timer

# Verify enabled
systemctl is-enabled moltis-backup.timer
# Expected: enabled
```

### Temporarily Disable

```bash
# Stop timer (keeps enabled, won't auto-start)
sudo systemctl stop moltis-backup.timer

# Start again
sudo systemctl start moltis-backup.timer
```

---

## Troubleshooting

### Timer Not Running

**Symptoms**: Backups not happening, timer shows inactive

```bash
# Check timer status
systemctl status moltis-backup.timer

# Check if enabled
systemctl is-enabled moltis-backup.timer

# Check timer list
systemctl list-timers --all | grep moltis
```

**Solution**:
```bash
sudo systemctl enable --now moltis-backup.timer
```

### Service Failing

**Symptoms**: `systemctl status` shows failed

```bash
# Check service status
systemctl status moltis-backup.service

# View detailed error
journalctl -u moltis-backup.service -n 50 --no-pager
```

**Common Issues**:

1. **Script not found**:
   ```bash
   # Verify script exists
   ls -la /usr/local/bin/backup-moltis-enhanced.sh

   # Make executable
   sudo chmod +x /usr/local/bin/backup-moltis-enhanced.sh
   ```

2. **Permission denied**:
   ```bash
   # Check permissions
   ls -la /usr/local/bin/backup-moltis-enhanced.sh

   # Fix permissions
   sudo chmod 755 /usr/local/bin/backup-moltis-enhanced.sh
   ```

3. **Docker not accessible**:
   ```bash
   # Verify Docker is running
   systemctl status docker

   # Start Docker if needed
   sudo systemctl start docker
   ```

### Last Run Failed

```bash
# Check exit code
systemctl show moltis-backup.service -p ExecMainStatus

# 0 = success, non-zero = failure

# View failure logs
journalctl -u moltis-backup.service -n 100
```

### Timer Running But No Backups

```bash
# Check if service is being triggered
journalctl -u moltis-backup.service --since "1 day ago"

# Check timer next run
systemctl list-timers | grep moltis

# Verify timer persistence
systemctl show moltis-backup.timer -p Persistent
```

---

## File Reference

### Timer File: `/etc/systemd/system/moltis-backup.timer`

```ini
[Unit]
Description=Daily Moltis Backup Timer
Documentation=specs/001-docker-deploy-improvements/spec.md

[Timer]
OnCalendar=*-*-* 02:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
```

### Service File: `/etc/systemd/system/moltis-backup.service`

```ini
[Unit]
Description=Moltis Backup Service
Documentation=specs/001-docker-deploy-improvements/spec.md
After=network.target docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=no
ExecStart=/usr/local/bin/backup-moltis-enhanced.sh backup --json
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

---

## Monitoring Integration

### Prometheus Metrics

The backup script exposes metrics for monitoring:

```promql
# Backup status (1 = success, 0 = failed)
moltis_backup_status{status="success"}
moltis_backup_status{status="failed"}

# Last successful backup timestamp
moltis_backup_last_success_timestamp

# Backup duration
moltis_backup_duration_seconds
```

### AlertManager Alerts

Configure alerts in `config/prometheus/backup_rules.yml`:

- `BackupFailed` - Critical, immediate notification
- `BackupMissing` - Warning, no backup in 24 hours
- `BackupStorageFull` - Critical, storage nearly full

---

## Best Practices

1. **Test backups regularly** - Verify restore works monthly
2. **Monitor timer status** - Set up alerts for missed runs
3. **Review logs weekly** - Check for warnings or failures
4. **Rotate encryption keys** - Every 90 days recommended
5. **Off-site backups** - Ensure S3 upload is working
6. **Document retention** - Know how long backups are kept

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| `specs/001-docker-deploy-improvements/quickstart.md` | Quick start guide |
| `docs/json-output.md` | JSON output format |
| `config/backup/backup.conf` | Backup configuration |
| `config/prometheus/backup_rules.yml` | Alerting rules |
