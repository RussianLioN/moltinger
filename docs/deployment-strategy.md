# Moltis Deployment Strategy

## Overview

This document describes the deployment strategy for Moltis to ainetic.tech using GitHub Actions.

## Architecture

```
+------------------+     SSH      +------------------+
|  GitHub Actions  |------------>|   ainetic.tech   |
|    Workflow      |             |   (Production)   |
+------------------+             +------------------+
                                        |
                                        v
                                 +-------------+
                                 |   Traefik   |
                                 | (Reverse    |
                                 |   Proxy)    |
                                 +-------------+
                                        |
                    +-------------------+-------------------+
                    |                   |                   |
                    v                   v                   v
              +----------+       +------------+       +------------+
              |  Moltis  |       | Watchtower |       |  Backups   |
              | :13131   |       | (Auto-     |       | /var/      |
              |          |       |  update)   |       | backups/   |
              +----------+       +------------+       +------------+
```

## Deployment Methods

### 1. Automatic Deployment (Push to main)

Triggered automatically on push to `main` branch:

```yaml
on:
  push:
    branches: [main]
```

### 2. Tag-based Deployment

Deploy specific versions using git tags:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### 3. Manual Deployment

Use GitHub UI or CLI:

```bash
gh workflow run deploy.yml \
  -f environment=production \
  -f version=v1.0.0
```

### 4. Rollback

Rollback to previous version:

```bash
gh workflow run deploy.yml -f rollback=true
```

## GitHub Secrets Required

Configure these secrets in repository Settings > Secrets and variables > Actions:

| Secret | Description | How to Generate |
|--------|-------------|-----------------|
| `SSH_PRIVATE_KEY` | Private SSH key for ainetic.tech | `ssh-keygen -t ed25519 -C "deploy@ainetic.tech"` |

### Setup SSH Key

```bash
# Generate key pair
ssh-keygen -t ed25519 -C "deploy@ainetic.tech" -f ~/.ssh/ainetic_deploy

# Copy public key to server
ssh-copy-id -i ~/.ssh/ainetic_deploy.pub root@ainetic.tech

# Add private key to GitHub Secrets
cat ~/.ssh/ainetic_deploy | pbcopy
# Paste into SSH_PRIVATE_KEY secret
```

## Deployment Workflow

### Phase 1: Pre-flight Checks

- Validate SSH credentials
- Determine deployment version
- Check prerequisites

### Phase 2: Backup

- Create backup of `/opt/moltinger/config` and `/opt/moltinger/data`
- Store current image version
- Rotate old backups (keep last 10)

### Phase 3: Deploy

1. Pull new image: `ghcr.io/moltis-org/moltis:$VERSION`
2. Update `docker-compose.yml` with new version
3. Stop container gracefully
4. Start new container
5. Wait for health check (max 3 minutes)

### Phase 4: Verify

- Container running check
- Health endpoint test: `http://localhost:13131/health`
- Traefik routing test: `https://ainetic.tech/health`
- WebSocket endpoint availability

## Health Checks

### Container Health Check

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:13131/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 10s
```

### External Health Check

```bash
# Via Traefik
curl https://ainetic.tech/health

# Expected response
{"status": "ok"}
```

## Rollback Procedure

### Automatic Rollback

```bash
gh workflow run deploy.yml -f rollback=true
```

### Manual Rollback

```bash
# SSH to server
ssh root@ainetic.tech

# Find backup
ls -lt /var/backups/moltis/pre_deploy_*.tar.gz

# Restore
cd /opt/moltinger
docker compose stop moltis
tar -xzf /var/backups/moltis/pre_deploy_YYYYMMDD_HHMMSS.tar.gz -C /
docker compose up -d moltis
```

## Monitoring

### Container Status

```bash
docker ps --filter "name=moltis"
docker inspect --format='{{.State.Health.Status}}' moltis
```

### Logs

```bash
docker logs moltis --tail 100 -f
```

### Traefik Routing

```bash
docker logs traefik --tail 100 -f
```

## Troubleshooting

### Container not starting

1. Check logs: `docker logs moltis`
2. Check config: `ls -la /opt/moltinger/config/`
3. Check permissions: `docker exec moltis ls -la /home/moltis/.config/moltis/`

### Health check failing

1. Test manually: `curl http://localhost:13131/health`
2. Check Traefik: `docker logs traefik`
3. Check network: `docker network ls`

### Traefik not routing

1. Check labels: `docker inspect moltis | grep -A 20 Labels`
2. Check Traefik dashboard: http://localhost:8080
3. Check certificates: `docker logs traefik 2>&1 | grep -i acme`

## Security Considerations

1. **SSH Key**: Use dedicated deploy key with limited permissions
2. **Environment Protection**: Production environment requires approval (optional)
3. **Secret Management**: Never commit secrets to repository
4. **Image Verification**: Pull from trusted registry only (ghcr.io/moltis-org)

## Directory Structure on Server

```
/opt/moltinger/
├── docker-compose.yml
├── .env                    # MOLTIS_PASSWORD
├── config/
│   └── ...                 # Moltis configuration
└── data/
    └── ...                 # Sessions, memory, logs

/var/backups/moltis/
├── pre_deploy_20240101_120000.tar.gz
├── pre_deploy_20240101_120000.tar.gz.version
└── ...
```

## CI/CD Pipeline

```
Push/Tag/Manual
       |
       v
+-------------+
|  Preflight  | ----> Validate SSH, Determine version
+-------------+
       |
       v
+-------------+
|   Backup    | ----> Backup config + data
+-------------+
       |
       v
+-------------+
|   Deploy    | ----> Pull image, Update compose, Restart
+-------------+
       |
       v
+-------------+
|   Verify    | ----> Health checks, Smoke tests
+-------------+
       |
       v
   Success!
```
