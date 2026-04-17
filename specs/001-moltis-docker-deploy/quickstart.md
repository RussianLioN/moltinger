# Quickstart: Moltis Deployment on ainetic.tech

This guide covers the complete deployment process for Moltis AI assistant.

## Prerequisites

- [x] Docker 24.x+ installed
- [x] Traefik 3.x deployed with Let's Encrypt
- [x] DNS: ainetic.tech pointing to server IP
- [x] OpenAI Codex OAuth runtime already bootstrapped on the target host

## Quick Deploy

```bash
# 1. Clone repository
git clone https://github.com/RussianLioN/moltinger.git
cd moltinger

# 2. Create environment file
cat > .env << EOF
MOLTIS_PASSWORD=your-secure-password
OLLAMA_API_KEY=your-ollama-cloud-key
EOF

# 3. Create directories
mkdir -p config data scripts
chmod 755 config data scripts
sudo chown -R 1000:1000 config data

# 4. Copy backup script
cp specs/001-moltis-docker-deploy/scripts/backup-moltis.sh scripts/
chmod +x scripts/backup-moltis.sh

# 5. Deploy
docker compose up -d

# 6. Verify
curl http://localhost:13131/health
```

## Access

- **URL**: https://ainetic.tech
- **Login**: Use password from `MOLTIS_PASSWORD`

## Configuration Files

### docker-compose.yml

Located at repository root. Contains:
- Moltis service with Traefik labels
- Watchtower service for auto-updates
- Volume mounts for persistence

### config/moltis.toml

Moltis configuration. Key settings:
- OpenAI Codex primary model via OAuth runtime state
- Optional Ollama Cloud fallback lane
- Sandbox configuration
- Authentication settings

### config/provider_keys.json

Runtime credential store for provider integrations. Created automatically on first run or during OAuth/bootstrap:

```json
{
  "openai-codex": "oauth-managed-runtime-state"
}
```

## Troubleshooting

### Container won't start

```bash
# Check logs
docker compose logs moltis

# Verify volumes
ls -la config/ data/

# Check permissions
sudo chown -R 1000:1000 config data
```

### Can't access Web UI

```bash
# Check Traefik logs
docker logs traefik

# Verify Traefik labels
docker inspect moltis | grep -A 20 Labels

# Test locally
curl http://localhost:13131/health
```

### Authentication fails

```bash
# Reset password (restart container to regenerate setup code)
docker compose restart moltis
docker compose logs moltis | grep "setup code"
```

## Backup & Restore

### Backup

```bash
# Manual backup
/usr/local/bin/backup-moltis.sh

# Automated (cron)
echo "0 3 * * * root /usr/local/bin/backup-moltis.sh" | sudo tee /etc/cron.d/moltis-backup
```

### Restore

```bash
# List backups
ls /var/backups/moltis/

# Restore through the tracked rollback helper
./scripts/deploy.sh --json moltis rollback
```

## Updates

Moltis updates are git-tracked and backup-safe. Do not use Watchtower as the authority for version bumps.

```bash
# 1. Update the tracked image version in git
$EDITOR docker-compose.yml
$EDITOR docker-compose.prod.yml

# 2. Validate the tracked version contract
./scripts/moltis-version.sh assert-tracked

# 3. Commit/push, then deploy through the safe helper or workflow
./scripts/deploy.sh --json moltis deploy
```

## Monitoring

### Health Check

```bash
curl https://ainetic.tech/health
# Expected: HTTP 200
```

### Logs

```bash
# Container logs
docker compose logs -f moltis

# Backup logs
tail -f /var/log/moltis-backup.log
```

## Security Checklist

- [ ] MOLTIS_PASSWORD set to strong password
- [ ] OLLAMA_API_KEY stored in .env when Ollama Cloud fallback is required
- [ ] config/provider_keys.json gitignored
- [ ] TLS certificate valid (check SSL Labs)
- [ ] Rate limiting active (5 attempts/60s)
- [ ] Backup cron configured

## Next Steps

1. Confirm Codex OAuth session and optional Ollama Cloud fallback in Web UI
2. Test sandbox execution with simple command
3. Set up monitoring for /health endpoint
4. Document any custom configurations
