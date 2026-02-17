# Session Summary: Moltinger Project

> **⚠️ ОБЯЗАТЕЛЬНОЕ ЧТЕНИЕ** в начале каждой сессии!
> Обновляется после каждой значимой сессии. Последнее обновление: 2026-02-17

---

## 🎯 Project Overview

**Проект**: Moltinger - AI-ассистент Moltis в Docker на сервере ainetic.tech
**Репозиторий**: https://github.com/RussianLioN/moltinger
**Ветка**: `main` (feature merged)
**Issue Tracker**: Beads (prefix: `molt`)

### Технологический стек

| Компонент | Технология |
|-----------|------------|
| **Container** | Docker Compose |
| **AI Assistant** | Moltis (ghcr.io/moltis-org/moltis:latest) |
| **Reverse Proxy** | Traefik (существующий на сервере) |
| **LLM Provider** | GLM (Zhipu AI) via api.z.ai |
| **Auto-updates** | Watchtower |
| **CI/CD** | GitHub Actions |
| **Issue Tracking** | Beads |

---

## 📊 Current Status

### Completion Progress

| Metric | Value |
|--------|-------|
| **Tasks Completed** | 80/80 (100%) |
| **Phases Complete** | All phases ✅ |
| **Commits** | 16+ commits on main |
| **Deployment** | ✅ PRODUCTION LIVE |
| **CI/CD** | ✅ WORKING (GitOps-compliant) |

### Git Status

```
Branch: main
Remote: up to date with origin
Recent Commits:
- 4be7f69 docs: plan session context persistence system
- 5177c10 docs: add secrets management policy
- b916ed5 feat(moltis): update configuration
- d6fe552 docs(gitops): clarify scp vs git pull approaches
- 1664d49 fix(docker): connect Moltis to ainetic_net for Traefik routing
```

### Production Status

```
Server: ainetic.tech
Moltis: Running (v0.8.35) ✅
URL: https://moltis.ainetic.tech (subdomain)
Health: OK ✅
Traefik: Routing via ainetic_net ✅
Auth: Active (401 for unauthenticated) ✅
Watchtower: Running ✅
CI/CD: Working (GitOps-compliant sync) ✅
```

---

## 📁 Key Files

### Configuration Files

| File | Purpose | Status |
|------|---------|--------|
| `docker-compose.prod.yml` | Moltis + Watchtower + Traefik + Monitoring | ✅ Live |
| `config/moltis.toml` | GLM provider, sandbox, identity | ✅ Live |
| `scripts/deploy.sh` | Deployment automation | ✅ Working |
| `scripts/backup-moltis-enhanced.sh` | Backup automation | ✅ Ready |
| `.github/workflows/deploy.yml` | CI/CD pipeline | ✅ Working |
| `Makefile` | Common commands | ✅ Ready |

### Documentation

| File | Purpose |
|------|---------|
| `specs/001-moltis-docker-deploy/spec.md` | Feature specification |
| `specs/001-moltis-docker-deploy/plan.md` | Implementation plan |
| `specs/001-moltis-docker-deploy/tasks.md` | Task tracking |
| `docs/reports/moltis-deployment-research.md` | Full research |

---

## 🔄 Beads Issues

```
moltinger-s67 (Epic): Feature: Moltis Docker Deployment
├── moltinger-s67.1: Phase 0: Planning ✅
├── moltinger-s67.2: Phase 1-2: Setup & Foundation ✅
├── moltinger-s67.3: Phase 3-5: MVP (Container + Traefik + Auth) ✅
├── moltinger-s67.4: Phase 6-8: Core Features ✅
├── moltinger-s67.5: Phase 9-14: Extended Features + GLM + Backup ✅
└── moltinger-s67.6: Phase 15: Polish & Documentation ✅

Status: ALL COMPLETE ✅
```

---

## 🚀 GitOps 2.0 Architecture

### CI/CD Pipeline

```
Push to main → GitHub Actions → SSH Deploy → Health Check → Smoke Tests
                                    ↓
                              ainetic.tech
```

### GitHub Secrets Status

| Secret | Status | Purpose |
|--------|--------|---------|
| `SSH_PRIVATE_KEY` | ✅ EXISTS | Deploy key for ainetic.tech |
| `MOLTIS_PASSWORD` | ✅ EXISTS | Authentication password |
| `GLM_API_KEY` | ✅ EXISTS | LLM API key (Zhipu AI) |
| `TAVILY_API_KEY` | ✅ EXISTS | Web Search (FREE, no card) |
| `TELEGRAM_BOT_TOKEN` | ✅ EXISTS | Telegram bot integration |
| `TELEGRAM_ALLOWED_USERS` | ✅ EXISTS | Allowed Telegram user IDs |
| `ELEVENLABS_API_KEY` | ❌ Optional | Voice fallback |
| `ANTHROPIC_API_KEY` | ❌ Optional | Alternative LLM |
| `OPENAI_API_KEY` | ❌ Optional | Alternative LLM |
| `GROQ_API_KEY` | ❌ Optional | STT fallback |
| ~~`BRAVE_API_KEY`~~ | ⛔ NOT NEEDED | Requires credit card |

**All required secrets configured!** ✅

**Policy**: See `docs/SECRETS-MANAGEMENT.md` for secrets workflow

### Workflow Triggers

- **Push to main**: Auto-deploy to production
- **workflow_dispatch**: Manual deploy with version selection
- **Rollback**: One-click rollback to previous version

---

## 📋 Key Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Secrets Storage | GitHub Secrets | Secure, CI/CD-friendly |
| Deploy Method | SSH + Docker Compose | Simple, reliable |
| SSH Key | Passphraseless ed25519 | CI/CD compatibility |
| Smoke Tests | /health only (non-blocking root) | Traefik middleware delays |
| Health Endpoint | Accept 401 as OK | Auth is active |

---

## ⚠️ Important Notes

### Security Configuration

1. **Deploy Key**: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN8ZRXVUNoJplJjua/ZOpxwW51+wSBdi/5y4SaP76NyK moltinger-ci-deploy`
2. **Sensitive Files** (gitignored):
   - `.env` - contains passwords and API keys
   - `data/` - sessions and memory
   - `secrets/` - Docker secrets

### Architecture

```
Internet (HTTPS)
    ↓
Traefik (TLS termination, ainetic_net)
    ↓
Moltis Container (port 13131, ainetic_net)
    URL: https://moltis.ainetic.tech
    ↓
GLM API (api.z.ai)
```

---

## 📝 Session History

### 2026-02-17 (Configuration Update + Security Fixes)

**Research Completed**:
- ✅ Sandbox analysis → `docs/reports/moltis-sandbox-analysis.md`
- ✅ Web Search API comparison → `docs/reports/web-search-api-comparison.md`
- ✅ Voice TTS/STT for Russian → `docs/reports/voice-tts-stt-comparison.md`

**Security Fixes (CRITICAL)**:
- ✅ Removed hardcoded API keys from moltis.toml (lines 558, 581)
- ✅ Changed to environment variable pattern: `${ELEVENLABS_API_KEY}`

**Configuration Changes**:
- ✅ Enabled sandbox: `mode = "all"` (was "off")
- ✅ Added sandbox resource limits (memory: 512M, cpu: 0.5, pids: 100)
- ✅ Switched TTS: `elevenlabs` → `piper` (FREE, Russian)
- ✅ Switched STT: `elevenlabs-stt` → `whisper` (FREE, Russian)
- ✅ Added Brave API key placeholder for web search

**Documentation**:
- ✅ Created `docs/SECRETS-MANAGEMENT.md` (policy)
- ✅ Updated CLAUDE.md with secrets policy reference
- ✅ Updated SESSION_SUMMARY.md with secrets tracking

**Commits**: 3+ (4be7f69, 5177c10, b916ed5)
**Status**: Config updated, needs BRAVE_API_KEY for web search

### 2026-02-16 (Subdomain Migration + GitOps Fixes)

**Problem Solved**:
- Moltis PathPrefix(/moltis) + stripPrefix → 404 on redirects
- Moltis doesn't support base path, generates redirects without prefix

**Changes**:
- ✅ Migrate Moltis to subdomain: `moltis.ainetic.tech`
- ✅ Fix CI/CD pipeline: replace `sed` with full file sync (scp)
- ✅ Fix Docker network: connect to `ainetic_net` (was isolated)
- ✅ Add GitOps compliance check in smoke tests
- ✅ Document GitOps principles (MEMORY.md, CLAUDE.md)

**Key Learnings**:
- `scp` from local machine = ❌ (no audit trail)
- `scp` from CI/CD pipeline = ✅ (GitOps-lite, has audit)
- Docker network isolation causes 504 Gateway Timeout

**Commits**: 4
**Status**: Production Live on subdomain

### 2026-02-16 (GitOps 2.0 Completion)

**Completed**:
- ✅ Setup GitHub Secrets (SSH_PRIVATE_KEY, MOLTIS_PASSWORD, GLM_API_KEY)
- ✅ Generate passphraseless deploy key for CI/CD
- ✅ Add deploy key to server authorized_keys
- ✅ Create and merge PR #1 to main
- ✅ Fix SSH passphrase error in CI/CD
- ✅ Fix smoke tests for auth-enabled endpoints
- ✅ Fix root path timeout (Traefik middleware)
- ✅ CI/CD pipeline fully working

**Commits**: 4+
**Status**: Production Live

### 2026-02-15 (Initial Setup)

**Completed**:
- ✅ Research Moltis documentation (32KB report)
- ✅ Create specification (513 lines, 9 user stories)
- ✅ Setup project structure
- ✅ Configure docker-compose.yml
- ✅ Add GLM provider config
- ✅ Setup backup script
- ✅ Implement GitOps 2.0 architecture

---

## 🔗 Quick Links

- **Spec**: `specs/001-moltis-docker-deploy/spec.md`
- **Plan**: `specs/001-moltis-docker-deploy/plan.md`
- **Tasks**: `specs/001-moltis-docker-deploy/tasks.md`
- **CI/CD**: `.github/workflows/deploy.yml`
- **Deploy Script**: `scripts/deploy.sh`
- **Beads Config**: `.beads/config.yaml`

---

## 📞 Commands Reference

```bash
# Deploy manually
make deploy

# Check status
make status

# View logs
make logs LOGS_OPTS=-f

# Rollback
gh workflow run deploy.yml -f rollback=true

# SSH to server
ssh root@ainetic.tech
docker logs moltis -f
```

---

*Last updated: 2026-02-17 | Session: Configuration Update + Security Fixes*
