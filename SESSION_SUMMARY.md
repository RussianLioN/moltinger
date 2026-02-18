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
| **Commits** | 20+ commits on main |
| **Deployment** | ✅ PRODUCTION LIVE |
| **CI/CD** | ✅ WORKING (GitOps-compliant) |
| **UI** | ✅ WORKING (black screen fixed) |
| **Telegram** | ✅ CONFIGURED (awaiting test) |

### Git Status

```
Branch: main
Remote: up to date with origin
Recent Commits (GLM-5 Configuration):
- 1374fc5 fix(moltis): update allowed_models with exact zai::model IDs
- a46921f fix(moltis): rename provider alias to 'zai', add explicit models whitelist
- 4c972d8 fix(moltis): use exact model IDs in allowed_models to filter out gpt-4o
- b40ed89 config(moltis): remove local-llm from offered list, keep only openai (GLM)
- 3b8e0da config(moltis): finalize allowed_models to 3 GLM models only
- de86084 fix(moltis): use only API-discoverable GLM models
- 8d2450c fix(moltis): restore glm-4.7-flash to allowed_models
- 63e1b7f fix(moltis): replace unavailable glm-4.7-flash with glm-4.6
- 1ecbaa2 fix(moltis): configure GLM-5 via OpenAI-compatible provider
```

### Production Status

```
Server: ainetic.tech
Moltis: Running ✅
URL: https://moltis.ainetic.tech (subdomain)
Health: OK ✅ (HTTP 200)
UI: WORKING ✅
Traefik: Routing via ainetic_net ✅
Auth: Active ✅
Telegram: WORKING ✅
  Bot: @moltinger_bot
LLM Provider: zai (GLM-5 via Z.ai Coding Plan) ✅
Models: 5 available (glm-5, glm-4.7, glm-4.6, glm-4.5, glm-4.5-air)
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
| `docs/LESSONS-LEARNED.md` | Incident analysis |
| `docs/SECRETS-MANAGEMENT.md` | Secrets policy |

---

## 🔄 Beads Issues

### Current Issues

```
moltinger-ema (Digest): Health check fixes - CLOSED
├── Security: Remove hardcoded API keys ✅
├── Config: Fix server bind/port ✅
└── Telegram: Enable integration ✅

moltinger-6ql [P3] - Implement SearXNG self-hosted web search (backlog)
```

### Closed This Session

| Issue | Priority | Resolution |
|-------|----------|------------|
| moltinger-lzy | P1 CRITICAL | Removed hardcoded API keys |
| moltinger-66p | P2 HIGH | Added secrets/ to .gitignore |
| moltinger-35g | P1 CRITICAL | Fixed bind=0.0.0.0, port=13131 |
| moltinger-pmc | P2 HIGH | Added enabled=true for Telegram |

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
| Server bind | 0.0.0.0 (not 127.0.0.1) | Required for Docker |
| Server port | 13131 (not 38415) | Match docker-compose.yml |
| Telegram | enabled = true | Required for bot to work |

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
Moltis Container (0.0.0.0:13131, ainetic_net)
    URL: https://moltis.ainetic.tech
    ↓
GLM API (api.z.ai)
```

---

## 📝 Session History

### 2026-02-17 (GLM-5 LLM Configuration Fix)

**Problem**: LLM models not working in Moltis (Web UI and Telegram silent)

**Root Cause Analysis**:
- `[providers.glm-coding]` - NOT a valid Moltis provider!
- Moltis only recognizes: anthropic, openai, gemini, groq, xai, deepseek, mistral, openrouter, cerebras, minimax, moonshot, venice, ollama, local-llm, openai-codex, github-copilot, kimi-code

**Solution**:
- ✅ Use `[providers.openai]` with custom `base_url` for Z.ai Coding Plan
- ✅ Endpoint: `https://api.z.ai/api/coding/paas/v4` (Coding Plan specific)
- ✅ Model: `glm-5` (Pro subscription)
- ✅ Alias: `zai` (clean provider name)
- ✅ Added `GLM_API_KEY` to docker-compose.yml environment

**Research Sources**:
- Z.ai Official Docs: https://docs.z.ai/api-reference/introduction
- API Discovery: `curl https://api.z.ai/api/coding/paas/v4/models`
- Rate Limits: https://z.ai/manage-apikey/rate-limits

**Model Filtering Attempts**:
- `allowed_models` with patterns: fuzzy match, not strict whitelist
- `models = [...]` in provider: ignored by Moltis
- `offered` provider list: works for hiding providers
- **Result**: 5 models visible (Moltis limitation - no strict whitelist)

**Known Limitations**:
- `glm-4.7-flash` NOT available via API (only Z.ai web interface)
- `gpt-4o` and `local-llm` removed from offered list
- Moltis `allowed_models` is fuzzy filter, not strict whitelist

**Commits**: 10
**Status**: Web UI ✅, Telegram ✅, LLM Working ✅

### 2026-02-17 (Health Check + Critical Fixes)

**Bug Hunting Results** (via `/health-bugs`):
- 12 bugs found (2 CRITICAL, 3 HIGH, 4 MEDIUM, 3 LOW)

**CRITICAL Fixes**:
- ✅ Removed hardcoded ElevenLabs API keys from git
  - Deleted `config/moltis.toml.backup`
  - Redacted keys from `docs/plans/parallel-doodling-coral.md`
- ✅ Fixed server bind/port mismatch (black screen root cause)
  - `bind`: 127.0.0.1 → 0.0.0.0
  - `port`: 38415 → 13131

**HIGH Fixes**:
- ✅ Added `secrets/` to `.gitignore`
- ✅ Enabled Telegram: `enabled = true` in `[channels.telegram]`

**Diagnostic Reports**:
- `.tmp/current/bug-hunting-report.md` - Full bug analysis
- `.tmp/current/moltis-runtime-diagnosis.md` - Runtime issue diagnosis

**Beads Issues**:
- Created: moltinger-lzy, moltinger-66p, moltinger-35g, moltinger-pmc
- All closed with fixes

**Commits**: 4
**Status**: All issues resolved, production healthy

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
- ✅ Tavily MCP via SSE transport (remote server)
- ✅ Telegram bot configured

**CI/CD Fixes**:
- ✅ Added config/ sync to deploy workflow
- ✅ Added .env generation from GitHub Secrets
- ✅ Fixed TOML duplicate section error

**Documentation**:
- ✅ Created `docs/SECRETS-MANAGEMENT.md` (policy)
- ✅ Created `docs/LESSONS-LEARNED.md` (incident analysis)
- ✅ Added Pre-Integration Checklist to CLAUDE.md
- ✅ Updated SESSION_SUMMARY.md with secrets tracking

**Commits**: 12+
**Status**: Production healthy

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
- **Bug Report**: `.tmp/current/bug-hunting-report.md`
- **Runtime Diagnosis**: `.tmp/current/moltis-runtime-diagnosis.md`

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

# Check health
curl -I https://moltis.ainetic.tech/health
```

---

## 🎯 Next Steps

1. **Moltis Feature Request**: Request strict model whitelist in Moltis (allowed_models should be exact match)
2. **Known Issue**: Emoji rendering broken in Moltis frontend (font issue)
3. **Backlog**: Implement SearXNG self-hosted web search (moltinger-6ql)

---

*Last updated: 2026-02-17 | Session: GLM-5 LLM Configuration Fix*
