# Project Memory & Lessons Learned

> **⛔ TOKEN LIMIT: ~300 lines max**
> **Новые уроки → docs/LESSONS-LEARNED.md | Новые инциденты → docs/rca/**

> **⚠️ ОБЯЗАТЕЛЬНОЕ ЧТЕНИЕ перед любым планированием или реализацией!**
>
> Этот файл содержит критическую конфигурацию проекта.
> Проверь его ПЕРЕД любыми изменениями в deploy, docker, traefik.

---

## Production Configuration (CRITICAL)

### Server: ainetic.tech (45.148.117.156)

| Resource | Value |
|----------|-------|
| CPU | **2 cores** (не 4!) |
| RAM | 8GB |
| OS | Ubuntu 22.04.5 LTS |
| Deploy Path | `/opt/moltinger` |

### Docker Networks (CRITICAL - проверять ПЕРЕД изменениями!)

| Network | Purpose | Containers |
|---------|---------|------------|
| `traefik-net` | **PRIMARY** Traefik routing | traefik, moltis, ... |
| `ainetic_net` | Internal services | n8n, postgres, redis, grafana, prometheus |
| `monitoring` | Moltis monitoring | moltis, prometheus |

**⚠️ ВАЖНО**:
- Moltis должен быть в `traefik-net`, НЕ `traefik_proxy`!
- Traefik использует `traefik-net` для DNS resolution

### Domain Mapping

| Service | Domain |
|---------|--------|
| Moltis | `moltis.ainetic.tech` |
| N8N | `ainetic.tech` |
| Grafana | `grafana.ainetic.tech` |
| Prometheus | `prometheus.ainetic.tech` |

### Traefik Labels (CRITICAL)

```yaml
# Moltis labels (docker-compose.prod.yml)
labels:
  - "traefik.enable=true"
  - "traefik.docker.network=traefik-net"  # CRITICAL for DNS!
  - "traefik.http.routers.moltis.rule=Host(`moltis.ainetic.tech`)"
```

### Environment Variables (.env on server)

```bash
MOLTIS_DOMAIN=moltis.ainetic.tech  # NOT ainetic.tech!
```

---

## Project Structure (Key Files)

```
moltinger/
├── docker-compose.yml          # Development compose
├── docker-compose.prod.yml     # Production compose (traefik-net!)
├── config/
│   ├── moltis.toml             # Moltis application config
│   ├── prometheus/             # Prometheus config
│   └── alertmanager/           # AlertManager config
├── scripts/
│   ├── deploy.sh               # Deploy script
│   ├── preflight-check.sh      # Pre-flight validation
│   └── health-monitor.sh       # Health monitoring
├── .github/workflows/
│   └── deploy.yml              # CI/CD pipeline
├── docs/
│   ├── LESSONS-LEARNED.md      # Detailed incident analysis
│   └── compose-structure.md    # YAML anchors docs
├── .specify/
│   ├── memory/constitution.md  # Project constitution
│   └── specs/                  # Feature specifications
├── SESSION_SUMMARY.md          # Session history
├── MEMORY.md                   # THIS FILE - READ FIRST!
└── CLAUDE.md                   # AI instructions
```

---

## Debug Commands

```bash
# Check container networks
ssh root@ainetic.tech "docker inspect moltis --format '{{range \$k, \$v := .NetworkSettings.Networks}}{{\$k}} {{end}}'"

# Check Traefik routing
ssh root@ainetic.tech "curl -sk -o /dev/null -w '%{http_code}' https://moltis.ainetic.tech/health"

# Check Traefik logs for Moltis
ssh root@ainetic.tech "docker logs traefik 2>&1 | grep -i moltis | tail -10"

# Check which IP Traefik uses (should be traefik-net IP!)
ssh root@ainetic.tech "docker logs traefik 2>&1 | grep 'moltis@docker' | tail -5"

# Check networks on server
ssh root@ainetic.tech "docker network ls | grep -E 'traefik|ainetic|monitoring'"

# Check .env on server
ssh root@ainetic.tech "cat /opt/moltinger/.env | grep DOMAIN"
```

---

## Docker Network Pitfalls (Lesson #14)

### Problem: Traefik 404/503

**Root Causes (2026-03-02)**:
1. Moltis в `traefik_proxy`, Traefik в `traefik-net` = разные сети
2. `MOLTIS_DOMAIN=ainetic.tech` вместо `moltis.ainetic.tech`
3. Docker DNS возвращает IP из первой по алфавиту сети (monitoring < traefik-net)

**Solutions**:
```yaml
# 1. Использовать существующую сеть
networks:
  traefik-net:    # НЕ traefik_proxy!
    external: true

# 2. Правильный default в compose
MOLTIS_DOMAIN=moltis.ainetic.tech

# 3. Явно указать сеть для Traefik DNS
labels:
  - "traefik.docker.network=traefik-net"
```

---

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

1. **NEVER use `scp`/`ssh` FROM LOCAL MACHINE to production**
   - Manual changes bypass CI/CD = no audit trail
   - If you need to change something → commit → push → let CI/CD deploy

2. **`scp`/`rsync` FROM CI/CD PIPELINE is ACCEPTABLE (GitOps-lite)**
   - CI/CD provides audit trail (who, what, when)
   - File content comes from `git checkout`
   - This is push-based GitOps, acceptable for simple projects

3. **For full GitOps 2.0, consider:**
   - Kubernetes + ArgoCD/Flux (pull-based with reconciliation)
   - Requires more infrastructure, not needed for simple Docker hosts

4. **NEVER use `sed` to partially update config files**
   - Sync entire files from git (scp/rsync)
   - Or use environment variables for dynamic values

5. **ALWAYS validate configuration before deploy**
   - `docker compose config --quiet`
   - Check required labels/keys exist

6. **ALWAYS backup config files for rollback**
   - Include `docker-compose.yml` in backup
   - Restore exact config on rollback

7. **ALWAYS test configuration matches git**
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

## File Operation Safety (MANDATORY)

### The Unauthorized Deletion Incident (2026-02-28)

**What Happened:**
- Sandbox blocked reading `config/provider_keys.json`
- Agent decided to delete the file without:
  1. Reading its content
  2. Checking usage in project
  3. Asking user confirmation
- Created empty `.example` file as replacement
- File contained Ollama provider config (not secrets, but still important)

**Root Cause:**
Agent exceeded scope of user request:
- User asked about "removing from deny list for CI/CD"
- Agent interpreted as "delete file + remove from deny list"
- Sandbox blocking read was treated as "file is not needed"

**The Fix:**
```bash
git checkout HEAD -- config/provider_keys.json
```

### Mandatory File Operation Rules

1. **NEVER delete a file without reading it first**
   - If sandbox blocks reading → ASK USER, don't assume
   - Use `cat`/`Read` before any destructive operation

2. **NEVER exceed scope of user request**
   - If user asks about X, answer about X only
   - If additional changes seem needed → ASK first

3. **ALWAYS check file usage before deletion**
   ```bash
   grep -r "filename" . --include="*.toml" --include="*.yml" --include="*.json"
   ```

4. **ALWAYS ask when uncertain**
   - Sandbox blocking = uncertainty = ASK USER
   - Don't invent solutions without full information

5. **ALWAYS backup before delete**
   ```bash
   cp file file.bak
   # or
   git stash
   ```

### File Deletion Protocol

```
BEFORE deleting ANY file:
1. [ ] Read file content (cat/Read)
2. [ ] Check if used in project (grep -r)
3. [ ] Check if in git (git log -- file)
4. [ ] Ask user confirmation
5. [ ] Create backup
6. [ ] Only then delete
```

### Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Delete without reading | Data loss | Always read first |
| Assume "not needed" | Wrong assumption | Verify usage |
| Exceed user request scope | Unauthorized changes | Stay in scope |
| Sandbox block = delete | Wrong interpretation | Ask user instead |

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
