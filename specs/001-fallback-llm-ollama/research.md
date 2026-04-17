# Research: Fallback LLM with Ollama Cloud

**Feature**: 001-fallback-llm-ollama
**Date**: 2026-03-01
**Status**: Complete

## Research Summary

Исследование выполнено на основе Consilium Report (`docs/reports/consilium/2026-03-01-fallback-llm-architecture.md`) с участием 5 экспертов.

## Key Decisions

### 1. Ollama Deployment Pattern

**Decision**: Docker Compose Sidecar

**Rationale**:
- Минимальные изменения в существующей инфраструктуре
- Shared network с Moltis для low-latency communication
- Resource isolation через Docker
- Автоматический health check

**Alternatives Considered**:
| Pattern | Rejected Because |
|---------|------------------|
| Ollama Cloud Direct API | Зависимость от внешнего API, нет кэширования |
| Separate docker-compose | Усложняет деплой |
| Kubernetes sidecar | Overkill для single-server deployment |

**Library**: `ollama/ollama:latest` (official image)
- Weekly downloads: N/A (Docker Hub)
- Last updated: Active development
- Documentation: https://ollama.com/docs

---

### 2. Circuit Breaker Implementation

**Decision**: Bash implementation in health-monitor.sh

**Rationale**:
- Простота, нет внешних зависимостей
- Интеграция с существующим health-monitor.sh
- Достаточно для single-instance deployment

**Alternatives Considered**:
| Library | Rejected Because |
|---------|------------------|
| circuit-breaker-js | Overkill, требует Node.js runtime |
| resilience4j | Java-based, не подходит |
| hystrix | Deprecated, Java-based |

**Implementation Pattern**:
```bash
# State machine
CLOSED → (3 failures) → OPEN → (60s) → HALF-OPEN → (success) → CLOSED
                                → (failure) → OPEN
```

---

### 3. State Storage

**Decision**: /tmp/moltis-llm-state.json

**Rationale**:
- Быстрый доступ (local filesystem)
- Ephemeral - пересоздаётся при рестарте
- Простой JSON формат
- File locking через flock для race condition prevention

**Schema**:
```json
{
  "current_provider": "openai-codex",
  "circuit_state": "closed",
  "failure_count": 0,
  "last_failure": null,
  "last_success": "2026-03-01T12:00:00Z",
  "last_switch": null
}
```

---

### 4. Health Check Strategy

**Decision**: 5-second interval probes

**Rationale**:
- Быстрое обнаружение сбоев (< 30s для 3 failures)
- Баланс между скоростью и нагрузкой
- Соответствует SLI/SLO требованиям

**Probe Implementation**:
```bash
# Primary health check
check_primary_health() {
  curl -sf --max-time 5 "${PRIMARY_PROVIDER_HEALTHCHECK_URL}" || return 1
}

# Ollama health check
check_ollama_health() {
  curl -sf "http://localhost:11434/api/tags" || return 1
}
```

---

### 5. API Key Management

**Decision**: Docker secrets

**Rationale**:
- GitOps compliant (не хранится в git)
- Интеграция с существующим secrets механизмом
- Автоматическое обновление через CI/CD

**Implementation**:
```yaml
secrets:
  ollama_api_key:
    file: ./secrets/ollama_api_key.txt

services:
  ollama:
    environment:
      OLLAMA_API_KEY_FILE: /run/secrets/ollama_api_key
```

---

## Best Practices Applied

### From Consilium Experts

1. **iac-expert**: Docker Compose sidecar с resource limits
2. **sre-engineer**: Circuit breaker pattern с 3-level state machine
3. **prometheus-expert**: Метрики `llm_fallback_triggered_total`, `llm_provider_available`
4. **cicd-architect**: Validation в preflight, smoke tests в verify
5. **backup-specialist**: Backup не нужен (кэш), RTO < 5 мин

### Industry Standards

- **Circuit Breaker Pattern**: Martin Fowler's definition
- **Health Checks**: Docker best practices (interval, timeout, retries)
- **Secrets Management**: Docker secrets для production workloads
- **Observability**: Prometheus metrics naming conventions

---

## Open Questions (Resolved)

| Question | Resolution | Source |
|----------|------------|--------|
| Local vs Cloud Ollama? | Cloud model (gemini-3-flash-preview:cloud) | User requirement |
| Circuit breaker library? | Custom Bash implementation | Simplicity |
| State persistence? | Ephemeral (/tmp) | RTO < 5min |
| Health check interval? | 5 seconds | Expert consensus |

---

## References

- Consilium Report: `docs/reports/consilium/2026-03-01-fallback-llm-architecture.md`
- Ollama Documentation: https://ollama.com/docs
- Circuit Breaker Pattern: https://martinfowler.com/bliki/CircuitBreaker.html
- Docker Secrets: https://docs.docker.com/engine/swarm/secrets/
