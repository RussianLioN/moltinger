# Project Memory & Lessons Learned

## GitOps Principles (MANDATORY)

### The Configuration Drift Incident (2026-02-16)

**What Happened:**
- Changed `docker-compose.yml` to use subdomain `moltis.ainetic.tech`
- Pushed changes to git
- CI/CD pipeline ran but **only updated image version via `sed`**
- Server still had OLD configuration with `PathPrefix(/moltis)`
- Result: 404 errors, smoke tests failed

**Root Cause:**
Pipeline used `sed` to update only the image version, NOT the entire file:
```yaml
# BAD - causes config drift
sed -i "s|image: ...:.*|image: ...:$VERSION|" docker-compose.yml
```

**The Fix:**
Sync ENTIRE file from git to server:
```yaml
# GOOD - GitOps compliant
scp docker-compose.yml $SSH_USER@$SSH_HOST:$DEPLOY_PATH/docker-compose.yml
```

### Mandatory GitOps Rules

1. **NEVER use `scp`/`ssh` directly for production changes**
   - All changes MUST go through CI/CD pipeline
   - If pipeline is broken, FIX THE PIPELINE first

2. **NEVER use `sed` to partially update config files**
   - Sync entire files from git
   - Use `scp`/`rsync` in pipeline, not `sed`

3. **ALWAYS validate configuration before deploy**
   - `docker compose config --quiet`
   - Check required labels/keys exist

4. **ALWAYS backup config files for rollback**
   - Include `docker-compose.yml` in backup
   - Restore exact config on rollback

5. **ALWAYS test configuration matches git**
   - Smoke tests should verify Traefik labels
   - Fail if config drift detected

### Pattern: GitOps Deployment Flow

```
git push → CI/CD Pipeline → Server
              ↓
    1. Sync ALL config files (scp/rsync)
    2. Validate configuration
    3. Deploy containers
    4. Verify configuration matches expected
              ↓
         Production State = Git State
```

### Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| `sed` in pipeline | Config drift | Sync entire files |
| Direct `scp` to server | Bypasses audit | Use pipeline only |
| Partial file updates | Inconsistent state | Full file sync |
| No config validation | Silent failures | Add validation step |
| No backup of config | Can't rollback | Backup compose file |

---

## Project-Specific Patterns

### Moltis Deployment

- **Subdomain**: `moltis.ainetic.tech` (not path prefix)
- **Traefik labels**: Check `traefik.http.routers.moltis.rule`
- **Health check**: `https://moltis.ainetic.tech/health`

### Traefik Configuration

- Moltis uses Host-based routing: `Host(\`moltis.ainetic.tech\`)`
- No stripPrefix middleware needed (subdomain approach)
- TLS via Let's Encrypt (`letsencrypt` certresolver)
