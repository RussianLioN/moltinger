# Implementation Plan: Fallback LLM with Ollama Cloud

**Branch**: `001-fallback-llm-ollama` | **Date**: 2026-03-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-fallback-llm-ollama/spec.md`

## Summary

Реализовать отказоустойчивый fallback механизм для Moltis с primary `openai-codex::gpt-5.4` через OAuth и единственным tracked fallback `ollama::gemini-3-flash-preview:cloud`.

**Primary Requirement**: При падении primary Codex lane система автоматически переключается на Ollama Cloud за < 30 секунд.

**Technical Approach**: Docker Compose sidecar + Bash scripts для health monitoring + TOML конфигурация для Moltis providers.

## Technical Context

**Language/Version**: Bash 5.x, TOML (Moltis config), YAML (Docker Compose)
**Primary Dependencies**: Docker Compose v2.0+, Ollama official image, Moltis (ghcr.io/moltis-org/moltis)
**Storage**: Docker volumes (ollama-data), state file (/tmp/moltis-llm-state.json)
**Testing**: Shell scripts (smoke tests), curl health checks
**Target Platform**: Linux server (Docker)
**Project Type**: Infrastructure/Docker deployment
**Performance Goals**: Failover < 30s, Recovery < 5min, P95 latency < 15s
**Constraints**: Resource limits 4 CPUs, 8GB RAM for Ollama; GitOps compliance
**Scale/Scope**: Single server deployment, 1 Moltis instance + 1 Ollama sidecar

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-First Development | ✅ PASS | Изучены существующие docker-compose.prod.yml, health-monitor.sh, moltis.toml |
| II. Single Source of Truth | ✅ PASS | Конфигурация в moltis.toml, secrets в Docker secrets |
| III. Library-First Development | ✅ PASS | Ollama official image используется |
| IV. Code Reuse & DRY | ✅ PASS | Расширяем существующий health-monitor.sh |
| V. Strict Type Safety | ⚠️ N/A | Bash scripts, no TypeScript |
| VI. Atomic Task Execution | ✅ PASS | Задачи разбиты по фазам |
| VII. Quality Gates | ✅ PASS | CI/CD validation, smoke tests |
| VIII. Progressive Specification | ✅ PASS | Spec → Plan → Tasks workflow |

**Gate Status**: ✅ PASSED - No violations

## Project Structure

### Documentation (this feature)

```text
specs/001-fallback-llm-ollama/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (API contracts)
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
# Existing structure - modifications only
docker-compose.prod.yml  # Add ollama service
config/
└── moltis.toml          # Enable ollama provider, configure failover
scripts/
├── health-monitor.sh    # Add circuit breaker logic
└── ollama-health.sh     # NEW: Ollama health probe
secrets/
└── ollama_api_key.txt   # NEW: Ollama API key (gitignored)
.github/workflows/
└── deploy.yml           # Add Ollama validation, smoke tests
```

**Structure Decision**: Modify existing files, add 2 new scripts. No new directories needed.

## Complexity Tracking

> No Constitution violations - table not needed.

## Phase 0: Research Summary

See [research.md](./research.md) for detailed findings.

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Ollama Deployment | Sidecar container | Minimal invasion, shared network with Moltis |
| Circuit Breaker | Bash implementation in health-monitor.sh | Simplicity, no external dependencies |
| State Storage | /tmp/moltis-llm-state.json | Fast access, ephemeral (recreated on restart) |
| Health Check Interval | 5 seconds | Fast detection (< 30s failover) |
| API Key Management | Docker secrets | GitOps compliant, secure |

### Libraries Evaluated

| Library | Decision | Reason |
|---------|----------|--------|
| ollama/ollama:latest | ✅ USE | Official image, well-maintained |
| circuit-breaker-js | ❌ SKIP | Overkill for Bash-based monitoring |
| prometheus/client_golang | ❌ SKIP | Phase 2 - not in scope |

## Phase 1: Design Artifacts

### Data Model

See [data-model.md](./data-model.md) for entity definitions.

**Key Entities**:
1. **LLM Provider** - OpenAI Codex (primary) and Ollama (fallback)
2. **Circuit Breaker State** - CLOSED, OPEN, HALF-OPEN
3. **Failover Event** - Switch records for observability

### Contracts

See [contracts/](./contracts/) for API specifications.

**Contracts Defined**:
1. `ollama-health-api.md` - Ollama health check endpoint
2. `circuit-breaker-state.md` - State file schema
3. `moltis-failover-config.md` - TOML configuration schema

### Quick Start

See [quickstart.md](./quickstart.md) for deployment instructions.

## Implementation Phases

### Phase 1: Ollama Sidecar Setup (P1)
- Add ollama service to docker-compose.prod.yml
- Configure Docker secrets for OLLAMA_API_KEY
- Set resource limits (4 CPUs, 8GB RAM)
- Add health check

### Phase 2: Moltis Configuration (P1)
- Enable ollama provider in moltis.toml
- Configure failover settings
- Add fallback_models array

### Phase 3: Circuit Breaker Implementation (P1)
- Add health probes to scripts/health-monitor.sh
- Implement state machine (CLOSED → OPEN → HALF-OPEN)
- Create /tmp/moltis-llm-state.json management
- Add metrics export

### Phase 4: CI/CD Integration (P2/P3)
- Add Ollama validation to preflight job
- Add smoke tests to verify job
- Add failover configuration test

## Risk Mitigation

| Risk | Mitigation | Owner |
|------|------------|-------|
| Ollama cold start (~60s) | Preload model in Docker entrypoint | Phase 1 |
| Memory competition | Resource limits 8GB for Ollama | Phase 1 |
| Race conditions | File locking with flock | Phase 3 |
| False-positive primary outage detection | Configure proper timeout (5s) | Phase 3 |

## Success Metrics

| Metric | Target | Validation |
|--------|--------|------------|
| Failover time | < 30s | Smoke test |
| Recovery time | < 5min | Smoke test |
| Availability | 99.5% | Prometheus metrics |
| P95 Latency | < 15s | Prometheus metrics |

## Next Steps

1. Run `/speckit.tasks` to generate task breakdown
2. Run `/speckit.tobeads` to import into Beads
3. Run `/speckit.implement` to execute implementation
