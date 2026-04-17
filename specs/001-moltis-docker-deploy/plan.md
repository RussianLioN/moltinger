# Implementation Plan: Moltis Docker Deployment on ainetic.tech

**Branch**: `001-moltis-docker-deploy` | **Date**: 2026-02-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-moltis-docker-deploy/spec.md`

## Summary

Deploy Moltis AI assistant as a Docker container on ainetic.tech server with:
- **Reverse Proxy**: Traefik (already deployed) with automatic TLS
- **LLM Provider**: Primary `openai-codex::gpt-5.4` with single fallback `ollama::gemini-3-flash-preview:cloud`
- **Auto-updates**: Watchtower for automatic container updates
- **Backup**: Daily cron backup with 7-day retention
- **Authentication**: MOLTIS_PASSWORD for initial setup

## Technical Context

**Language/Version**: Bash scripts, YAML (Docker Compose), TOML (Moltis config)
**Primary Dependencies**:
- Docker 24.x+
- Traefik 3.x (existing)
- Moltis image: ghcr.io/moltis-org/moltis:latest
- Watchtower: containrrr/watchtower:latest

**Storage**: Docker bind mounts
- `./config` → `/home/moltis/.config/moltis` (configuration)
- `./data` → `/home/moltis/.moltis` (sessions, memory, logs)

**Testing**: Manual verification
- Health check: `curl http://localhost:13131/health`
- UI access: `https://ainetic.tech`
- Authentication flow verification

**Target Platform**: Linux server (ainetic.tech)
**Project Type**: Infrastructure/DevOps deployment
**Performance Goals**: <2s UI response, <30s container startup
**Constraints**: Single-server, no HA/clustering
**Scale/Scope**: Single instance, ~10 concurrent users max

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| Context-First | ✅ PASS | Research report completed (32KB) |
| Single Source of Truth | ✅ PASS | Config centralized in docker-compose.yml |
| Library-First | ✅ PASS | Using official Moltis image, Watchtower |
| Code Reuse | ✅ PASS | Existing Traefik, documented patterns |
| Type Safety | ✅ N/A | Infrastructure (no TypeScript) |
| Atomic Task Execution | ✅ PASS | Each component = separate task |
| Quality Gates | ✅ PASS | Health check endpoint available |
| Progressive Specification | ✅ PASS | Spec → Plan → Tasks workflow |

**Gate Status**: ✅ ALL GATES PASSED

## Project Structure

### Documentation (this feature)

```text
specs/001-moltis-docker-deploy/
├── spec.md              # Feature specification (complete)
├── plan.md              # This file
├── research.md          # Research findings
├── quickstart.md        # Deployment guide
└── tasks.md             # Implementation tasks
```

### Source Code (repository root)

```text
moltinger/
├── docker-compose.yml   # Main deployment configuration
├── config/
│   ├── moltis.toml      # Moltis configuration
│   └── provider_keys.json # LLM API keys (gitignored)
├── data/                # Persistent data (gitignored)
├── scripts/
│   └── backup-moltis.sh # Backup script
└── .env                 # Environment variables (gitignored)
```

**Structure Decision**: Single-project infrastructure layout. No frontend/backend split - this is a deployment configuration project.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           Internet (HTTPS)               │
                    └─────────────────┬───────────────────────┘
                                      │
                                      ▼
                    ┌─────────────────────────────────────────┐
                    │   Traefik (Reverse Proxy)               │
                    │   - TLS Termination (Let's Encrypt)     │
                    │   - ainetic.tech → localhost:13131      │
                    └─────────────────┬───────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────┐
│                        Docker Network                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐   │
│  │     Moltis      │  │   Watchtower    │  │   (Sandbox)     │   │
│  │   Port: 13131   │  │  Auto-updates   │  │  Docker socket  │   │
│  │                 │  │                 │  │                 │   │
│  │  ./config ──────┼──┤ volumes ────────┼──┤ ./data         │   │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                    ┌─────────────────────────────────────────┐
                    │  Provider Chain                         │
                    │  Codex -> Ollama Cloud                 │
                    └─────────────────────────────────────────┘
```

## Components

### 1. docker-compose.yml

Primary deployment configuration with:
- Moltis service with Traefik labels
- Watchtower service for auto-updates
- Volume mounts for persistence
- Environment variables

### 2. config/moltis.toml

Moltis configuration with:
- ordered provider-chain settings
- Sandbox configuration
- Authentication settings
- Memory system settings

### 3. scripts/backup-moltis.sh

Backup automation:
- Daily tar of config + data
- 7-day retention
- Cron scheduling

### 4. Traefik Labels

Routing configuration:
- Host: ainetic.tech
- TLS: Let's Encrypt
- WebSocket support

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Docker | 24.x+ | Container runtime |
| Traefik | 3.x | Reverse proxy (existing) |
| Moltis | latest | AI assistant |
| Watchtower | latest | Auto-updates |
| Provider chain | live | Codex primary + Ollama Cloud fallback |

## Security Considerations

1. **Docker Socket**: Mounted for sandbox - WARNING: equivalent to root access
2. **API Keys**: Stored in `config/provider_keys.json` (gitignored)
3. **MOLTIS_PASSWORD**: Set via environment variable
4. **TLS**: Handled by Traefik with Let's Encrypt
5. **Rate Limiting**: Built into Moltis (5 login attempts/60s)

## Rollout Plan

1. **Phase 1**: Deploy basic container (no sandbox)
2. **Phase 2**: Configure Traefik labels
3. **Phase 3**: Setup provider chain and fallback policy
4. **Phase 4**: Enable sandbox (Docker socket)
5. **Phase 5**: Configure backups
6. **Phase 6**: Enable Watchtower

## Success Metrics

| Metric | Target | Verification |
|--------|--------|--------------|
| Container startup | <30s | `docker compose up -d && curl /health` |
| UI response time | <2s | Browser load time |
| TLS rating | A+ | SSL Labs test |
| Backup reliability | 100% | Test restore monthly |
| Uptime | 99%+ | Health check monitoring |

## Complexity Tracking

> No violations - simple single-server deployment

| Aspect | Complexity | Justification |
|--------|------------|---------------|
| Architecture | Low | Single container, existing Traefik |
| Configuration | Low | Standard Moltis config |
| Operations | Low | Watchtower auto-updates, cron backup |
