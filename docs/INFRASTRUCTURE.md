# Moltis Infrastructure Documentation

## Overview

This document describes the production-ready infrastructure for Moltis deployment.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           Internet / Users               │
                    └────────────────┬────────────────────────┘
                                     │
                                     ▼
                    ┌─────────────────────────────────────────┐
                    │         Traefik Reverse Proxy            │
                    │   (SSL termination, load balancing)      │
                    └────────────────┬────────────────────────┘
                                     │
                    ┌────────────────┴────────────────────────┐
                    │                                         │
                    ▼                                         ▼
        ┌───────────────────┐                    ┌───────────────────┐
        │   Moltis :13131   │                    │  Watchtower       │
        │   (Main App)      │                    │  (Auto-updates)   │
        └─────────┬─────────┘                    └───────────────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
    ▼             ▼             ▼
┌─────────┐ ┌──────────┐ ┌──────────────┐
│ Config  │ │   Data   │ │ Docker Socket│
│ (RO)    │ │  (RW)    │ │    (RO)      │
└─────────┘ └──────────┘ └──────────────┘

                    MONITORING STACK
                    ┌───────────────┐
                    │  Prometheus   │◄──── Scrape metrics
                    │   :9090       │
                    └───────┬───────┘
                            │
                    ┌───────▼───────┐
                    │ AlertManager  │──── Email/Slack
                    │   :9093       │
                    └───────────────┘

                    ┌───────────────┐
                    │   cAdvisor    │◄──── Container metrics
                    │   :8080       │
                    └───────────────┘
```

## Components

### Core Services

| Service | Port | Purpose |
|---------|------|---------|
| Moltis | 13131 | Main application |
| Traefik | 80/443 | Reverse proxy, SSL |
| Watchtower | - | Auto-updates |

### Monitoring Stack

| Service | Port | Purpose |
|---------|------|---------|
| Prometheus | 9090 | Metrics collection |
| AlertManager | 9093 | Alert handling |
| cAdvisor | 8080 | Container metrics |

## Quick Start

```bash
# Initial setup
make setup

# Deploy
make deploy

# Check status
make status

# View logs
make logs LOGS_OPTS="-f"

# Create backup
make backup
```

For LLM/operator step-by-step remote image rollout and recovery guidance, see [LLM-REMOTE-MOLTIS-DOCKER-RUNBOOK.md](./knowledge/LLM-REMOTE-MOLTIS-DOCKER-RUNBOOK.md).

## Configuration Files

```
config/
├── moltis.toml              # Main Moltis configuration
├── prometheus/
│   ├── prometheus.yml       # Prometheus config
│   └── alert-rules.yml      # Alert definitions
├── alertmanager/
│   └── alertmanager.yml     # Alert routing
└── backup/
    └── backup.conf          # Backup settings

systemd/
├── moltis-health-monitor.service
├── moltis-telegram-web-user-monitor.service
└── moltis-telegram-web-user-monitor.timer

scripts/cron.d/
├── moltis-backup-verify
├── moltis-telegram-user-monitor
├── moltis-telegram-web-user-monitor
└── moltis-telegram-webhook-monitor
```

## Runtime Config State

Production runtime uses three different server-side surfaces:

- Branch/worktree-specific deploy root: `${DEPLOY_PATH:-/opt/moltinger}`
- Active automation root symlink: `/opt/moltinger-active`
- Git-synced static config under the active root: `/opt/moltinger-active/config`
- Writable live runtime config: `${MOLTIS_RUNTIME_CONFIG_DIR:-/opt/moltinger-state/config-runtime}`

The writable runtime config directory is prepared from the static config tree during deploy and then mounted into the container at `/home/moltis/.config/moltis`.
This is where Moltis persists runtime-managed files such as:

- `oauth_tokens.json`
- `provider_keys.json`
- `credentials.json`

## Backup Strategy

### Retention Policy

| Type | Frequency | Retention |
|------|-----------|-----------|
| Daily | Every day at 2:00 AM | 30 days |
| Weekly | Sunday at 3:00 AM | 12 weeks |
| Monthly | 1st of month | 12 months |

### Backup Contents

- Configuration files (`./config/`)
- Runtime config state (`${MOLTIS_RUNTIME_CONFIG_DIR:-/opt/moltinger-state/config-runtime}`)
- Data directory (`./data/`)
- Container state (metadata)
- Encryption (AES-256-CBC)

Runtime auth/state files must exist only in the runtime config directory, not in the git-synced static `config/` tree.

### Offsite Backup Options

1. **AWS S3** - Set `S3_ENABLED=true` in backup.conf
2. **SFTP** - Set `SFTP_ENABLED=true` in backup.conf

## Disaster Recovery

### Recovery Time Objective (RTO)

- Simple container restart: < 1 minute
- Full restore from backup: < 15 minutes
- Complete environment rebuild: < 1 hour

### Recovery Point Objective (RPO)

- Daily backups: < 24 hours data loss
- With frequent backups: < 1 hour data loss

### Recovery Procedure

```bash
# 1. List available backups
make backup-list

# 2. Restore from backup
make restore FILE=/var/backups/moltis/daily/moltis_daily_20240115_020000.tar.gz.enc

# 3. Verify
make health-check
```

## Monitoring & Alerting

### Key Metrics

- `up{job="moltis"}` - Service availability
- `container_memory_usage_bytes` - Memory usage
- `rate(moltis_errors_total[5m])` - Error rate
- `histogram_quantile(0.95, ...)` - Latency

### Alert Channels

1. **Email** - All alerts
2. **Slack** - Critical and warnings

### Alert Severities

| Severity | Response Time | Example |
|----------|--------------|---------|
| Critical | Immediate | Service down |
| Warning | < 4 hours | High memory |
| Info | < 24 hours | Backup old |

## Self-Healing

The health monitor (`health-monitor.sh`) provides:

1. **Container restart** on health check failure
2. **Exponential backoff** for repeated failures
3. **Full recovery** if restart fails
4. **Resource monitoring** (disk, memory)
5. **Notifications** on all actions

Critical rule:
- Cron jobs, systemd units, and recovery automation must execute from `/opt/moltinger-active`, not from a hardcoded historical worktree like `/opt/moltinger`.

## Security Considerations

1. **Secrets Management**
   - Docker secrets for sensitive data
   - Never commit `.env` or `secrets/`

2. **Network Isolation**
   - Traefik proxy network (external access)
   - Monitoring network (internal only)

3. **TLS/SSL**
   - Handled by Traefik with Let's Encrypt
   - Moltis runs with `MOLTIS_NO_TLS=true`

4. **Backup Encryption**
   - AES-256-CBC encryption
   - Key stored separately (`/etc/moltis/backup.key`)

## Maintenance Tasks

### Daily (Automated)

- Backup creation
- Log rotation
- Health checks

### Weekly (Automated)

- Full backup
- Storage maintenance (`/opt/moltinger-active/scripts/moltis-storage-maintenance.sh reclaim`)
- Log rotation

Repository-managed storage maintenance now reclaims:

- unused Docker images older than the configured retention window
- stale BuildKit cache
- known ephemeral probe volumes
- excess journald usage above the configured size budget

### Monthly (Manual)

- Review alert rules
- Test restore procedure
- Update documentation

## Troubleshooting

### Container won't start

```bash
# Check logs
make logs

# Check container status
docker inspect moltis

# Safer recreate path for fixed-name Moltis container
docker stop --time 45 moltis || true
docker rm -f moltis || true
docker compose -p moltinger -f docker-compose.prod.yml up -d moltis
```

### Health check failing

```bash
# Manual health check
curl http://localhost:13131/health

# Check container logs
docker logs moltis --tail 100
```

### Backup issues

```bash
# Verify backup integrity
./scripts/backup-moltis-enhanced.sh verify /path/to/backup.tar.gz.enc

# Generate new encryption key
./scripts/backup-moltis-enhanced.sh generate-key
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `MOLTIS_PASSWORD` | Yes | Authentication password |
| `GLM_API_KEY` | Yes | GLM-5 last-fallback API key |
| `OLLAMA_API_KEY` | No | Ollama Cloud key for `gemini-3-flash-preview:cloud` fallback |
| `MOLTIS_DOMAIN` | No | Domain for Traefik |
| `MOLTIS_RUNTIME_CONFIG_DIR` | No | Writable live Moltis config path on server (default `/opt/moltinger-state/config-runtime`) |
| `SMTP_*` | No | Email notifications |
| `SLACK_WEBHOOK` | No | Slack notifications |
| `S3_*` | No | S3 backup storage |

## Support

- Documentation: https://docs.moltis.org
- Issues: https://github.com/moltis-org/moltis/issues
