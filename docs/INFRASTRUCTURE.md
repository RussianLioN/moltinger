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

## Clawdiy Same-Host Runtime

Clawdiy is deployed as a second permanent agent on the same server in a separate compose stack.

### Runtime Boundary

| Area | Moltinger | Clawdiy |
|------|-----------|---------|
| Public URL | `https://moltis.ainetic.tech` | `https://clawdiy.ainetic.tech` |
| Local bind | `127.0.0.1:13131` | `127.0.0.1:18789` |
| Compose file | `docker-compose.prod.yml` | `docker-compose.clawdiy.yml` |
| Runtime config | `config/moltis.toml` | `config/clawdiy/openclaw.json` |
| Control-plane registry | `config/fleet/agents-registry.json` + `config/fleet/policy.json` | `config/fleet/agents-registry.json` + `config/fleet/policy.json` |
| Persistent state | `data/` | `data/clawdiy/state` |
| Audit evidence | mixed app logs | `data/clawdiy/audit` |

### Shared Networks

- `traefik-net`: public ingress through Traefik
- `fleet-internal`: private agent-to-agent path
- `moltinger_monitoring`: Prometheus and cAdvisor visibility for per-agent metrics

### Topology Profiles

| Profile | What changes | What must stay invariant | Machine trust posture |
|---------|--------------|--------------------------|-----------------------|
| `same_host` | container placement and local bind remain on one server | `agent_id`, logical address, handoff paths, message envelope | private `fleet-internal` network, bearer service auth, no public machine handoffs |
| `remote_node` | Clawdiy internal endpoint, health, and metrics move to a private remote endpoint | `agent_id=clawdiy`, `agent://clawdiy`, `/internal/v1/agent-handoffs*`, public web URL | private overlay or equivalent, bearer service auth, public machine handoffs still forbidden |

### Extraction Invariants

- Moving Clawdiy to another node is a placement change, not an identity change.
- `agent_id`, `logical_address`, correlation headers, required acknowledgements, and handoff envelope schema must remain unchanged.
- `config/fleet/agents-registry.json` and `config/fleet/policy.json` stay authoritative for discovery and trust policy in both profiles.
- `clawdiy.ainetic.tech` remains the human-facing URL even if the internal machine endpoint changes to a remote private hostname.

### Same-Host vs Remote-Node Routing

| Concern | Same-host phase | Remote-node target |
|---------|-----------------|--------------------|
| Human ingress | Traefik -> `clawdiy.ainetic.tech` on current host | same public hostname through Traefik or equivalent edge |
| Machine handoff | `fleet-internal` -> `http://clawdiy:18789/internal/v1` | private overlay/private DNS -> `https://clawdiy-int.ainetic.tech/internal/v1` |
| Discovery source | git-managed registry + policy | same git-managed registry + policy |
| Auth boundary | bearer token bound to `X-Agent-Id` | same bearer contract, with room for later mTLS hardening |
| Observability | local health/metrics + Prometheus scrape | same health/metrics paths, new host placement |

### Routing and Trust Rules

- Telegram is never the authoritative inter-agent transport.
- Public subdomains are for human/operator ingress; machine handoffs stay on private authenticated paths.
- Remote-node extraction does not authorize public machine-to-machine traffic just because Clawdiy has a public URL.
- Future permanent roles such as architect, tester, and researcher must reuse the same registry/policy contract instead of inventing new routing rules.

### Operator Commands

```bash
# Same-host deploy flow
./scripts/deploy.sh clawdiy deploy
./scripts/clawdiy-smoke.sh --stage same-host
./scripts/clawdiy-smoke.sh --stage restart-isolation

# Stop only Clawdiy
./scripts/deploy.sh clawdiy stop

# Inspect current Clawdiy status
./scripts/deploy.sh --json clawdiy status | jq .

# Verify the platform is ready for remote-node extraction
./scripts/clawdiy-smoke.sh --json --stage extraction-readiness | jq .
```

### Ownership Rules

- Clawdiy must not reuse Moltinger password material, cookies, or state directories.
- Clawdiy control-plane config remains Git-managed under `config/clawdiy/` and `config/fleet/`.
- A Clawdiy restart must not change Moltinger container identity or health.

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

## Configuration Files

```
config/
├── moltis.toml              # Main Moltis configuration
├── prometheus/
│   ├── prometheus.yml       # Prometheus config
│   └── alert-rules.yml      # Alert definitions
├── alertmanager/
│   └── alertmanager.yml     # Alert routing
├── backup/
│   └── backup.conf          # Backup settings
├── systemd/
│   └── moltis-health-monitor.service
└── cron/
    └── moltis-cron          # Cron jobs
```

## Backup Strategy

### Retention Policy

| Type | Frequency | Retention |
|------|-----------|-----------|
| Daily | Every day at 2:00 AM | 30 days |
| Weekly | Sunday at 3:00 AM | 12 weeks |
| Monthly | 1st of month | 12 months |

### Backup Contents

- Configuration files (`./config/`)
- Data directory (`./data/`)
- Container state (metadata)
- Encryption (AES-256-CBC)

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
- Docker cleanup
- Log rotation

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

# Force recreate
docker compose -f docker-compose.prod.yml up -d --force-recreate moltis
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
| `GLM_API_KEY` | Yes | GLM API key |
| `MOLTIS_DOMAIN` | No | Domain for Traefik |
| `SMTP_*` | No | Email notifications |
| `SLACK_WEBHOOK` | No | Slack notifications |
| `S3_*` | No | S3 backup storage |

## Support

- Documentation: https://docs.moltis.org
- Issues: https://github.com/moltis-org/moltis/issues
