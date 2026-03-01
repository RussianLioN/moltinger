# Consilium Report: Fallback LLM Architecture

> **Date:** 2026-03-01
> **Topic:** Fallback LLM for Moltis with Ollama Cloud + Gemini-3-flash-preview
> **Experts Consulted:** 5/19 (rate limit constraints)
> **Consensus:** Strong

---

## Executive Summary

**Recommended Solution:** Ollama Sidecar + Circuit Breaker Pattern

Эксперты консилиума рекомендуют добавить Ollama как sidecar-контейнер в docker-compose.prod.yml с реализацией circuit breaker для автоматического переключения при падении GLM API.

**Implementation Time:** 3-4 дня
**Confidence Level:** High (4/5 экспертов согласны)

---

## Question

Как организовать Fallback LLM для Moltis с использованием Ollama Cloud + Gemini-3-flash-preview?

**Context:**
- Primary LLM: GLM-5 через Z.ai Coding Plan (api.z.ai)
- Fallback: НЕ настроен (КРИТИЧЕСКАЯ ПРОБЛЕМА)
- Если GLM API недоступен — Moltis полностью неработоспособен

---

## Expert Opinions

### prometheus-expert ✅
- **Key Points:**
  - Метрики: `llm_request_total`, `llm_fallback_triggered_total`, `llm_provider_available`
  - Alerts: GLMAPIUnavailable (>5 мин), HighFallbackRate (>10%), LatencyDegraded (P95 > 10s)
  - SLI/SLO: Availability 99.5%, Latency P95 < 5s, Fallback Rate < 0.5%
- **Opinion:** Требуется exporter для Moltis API, histogram для latency tracking
- **Status:** ⚠️ Basic - требуется реализация

### backup-specialist ✅
- **Key Points:**
  - Ollama модели НЕ требуют бэкапа (кэш, загружается из реестра)
  - RPO: 0 (конфигурация в git)
  - RTO: < 5 минут (git pull + redeploy)
- **Opinion:** Добавить fallback в health-monitor, создать disaster recovery runbook
- **Status:** ✅ Agreed

### iac-expert ✅
- **Key Points:**
  - Docker Compose sidecar для Ollama
  - Resource limits: 4 CPUs, 8G RAM
  - Docker secrets для OLLAMA_API_KEY
- **Opinion:** Использовать существующий GitOps pipeline, минимальная инвазия
- **Status:** ✅ Agreed

### sre-engineer ✅
- **Key Points:**
  - Circuit Breaker Pattern (3 уровня)
  - Health probes: 5s interval для LLM
  - State tracking: `/tmp/moltis-llm-state.json`
- **Opinion:** Phase-based внедрение: Detection → Automatic Fallback → Observability
- **Status:** ✅ Agreed

### cicd-architect ✅
- **Key Points:**
  - Валидация Ollama config в preflight job
  - Smoke tests для failover в verify job
  - Parallel deployment (Ollama не зависит от Moltis)
- **Opinion:** Добавить TLS cert validation, failover configuration test
- **Status:** ✅ Agreed

---

## 5 Deployment Variants

### Variant 1: Ollama Sidecar (Recommended) ⭐

**Architecture:**
```
┌─────────────────────────────────────────┐
│           Docker Compose                 │
│  ┌─────────┐      ┌─────────────────┐   │
│  │ Moltis  │─────▶│ Ollama Sidecar  │   │
│  │ :13131  │      │ :11434          │   │
│  └────┬────┘      └────────┬────────┘   │
│       │                    │             │
│       ▼                    ▼             │
│  ┌────────────────────────────────┐     │
│  │     Monitoring Network         │     │
│  └────────────────────────────────┘     │
└─────────────────────────────────────────┘
```

**Configuration:**
```yaml
# docker-compose.prod.yml
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama-fallback
    ports: ["11434:11434"]
    volumes: [ollama-data:/root/.ollama]
    environment:
      OLLAMA_HOST: 0.0.0.0
    deploy:
      resources:
        limits: {cpus: '4', memory: 8G}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
    networks: [monitoring]
```

**Pros:**
- ✅ Минимальные изменения (добавить 1 сервис)
- ✅ Shared network с Moltis
- ✅ Resource isolation через Docker
- ✅ Автоматический health check

**Cons:**
- ⚠️ Требует 4-8GB RAM на сервере
- ⚠️ Cold start ~30-60s при первой загрузке модели

**Complexity:** Low (1-2 дня)

---

### Variant 2: Ollama Cloud Direct API

**Architecture:**
```
┌─────────────────────────────────────────┐
│              Moltis                      │
│  ┌─────────────────────────────────┐    │
│  │ providers.ollama                │    │
│  │ base_url = "https://ollama.com" │    │
│  │ api_key = "${OLLAMA_API_KEY}"   │    │
│  └─────────────────────────────────┘    │
│              │                           │
│              ▼                           │
│  ┌─────────────────────────────────┐    │
│  │     ollama.com/api/chat         │    │
│  │     (Gemini-3-flash-preview)    │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

**Configuration:**
```toml
# config/moltis.toml
[providers.ollama]
enabled = true
base_url = "https://ollama.com"
api_key = "${OLLAMA_API_KEY}"
model = "gemini-3-flash-preview:cloud"

[failover]
enabled = true
fallback_models = ["ollama::gemini-3-flash-preview:cloud"]
```

**Pros:**
- ✅ Нет локальных ресурсов (CPU/RAM)
- ✅ Мгновенный доступ (нет cold start)
- ✅ Минимальная конфигурация

**Cons:**
- ⚠️ Зависимость от внешнего API (latency, availability)
- ⚠️ Требует OLLAMA_API_KEY (платная подписка)
- ⚠️ Нет локального кэширования

**Complexity:** Very Low (1 день)

---

### Variant 3: Circuit Breaker Pattern

**Architecture:**
```
┌───────────────────────────────────────────────┐
│         Moltis + Circuit Breaker              │
│                                                │
│  ┌──────────┐   FAIL   ┌──────────────────┐   │
│  │ GLM API  │─────────▶│ Circuit Breaker  │   │
│  │ (Primary)│          │                  │   │
│  └──────────┘          │ State Machine:   │   │
│       │                │ CLOSED → OPEN    │   │
│       │ SUCCESS        │ OPEN → HALF-OPEN │   │
│       ▼                │ HALF-OPEN → ...  │   │
│  ┌──────────┐          └────────┬─────────┘   │
│  │ Continue │                   │ FALLBACK    │
│  │ (Normal) │                   ▼              │
│  └──────────┘          ┌──────────────────┐   │
│                        │ Ollama Sidecar   │   │
│                        │ (Fallback)       │   │
│                        └──────────────────┘   │
└───────────────────────────────────────────────┘
```

**Implementation:**
```bash
# /tmp/moltis-llm-state.json
{
  "current": "glm",
  "failures": 0,
  "last_switch": "2026-03-01T11:00:00Z",
  "circuit_state": "closed"
}

# Health probes (5s interval)
check_glm_health() {
  curl -sf --max-time 5 "${GLM_API_URL}/health" || return 1
}

check_ollama_health() {
  curl -sf "localhost:11434/api/tags" || return 1
}
```

**Pros:**
- ✅ Автоматическое переключение (no manual intervention)
- ✅ Graceful recovery (half-open state)
- ✅ State tracking для observability

**Cons:**
- ⚠️ Требует custom logic в Moltis/health-monitor
- ⚠️ Race conditions при multiple instances
- ⚠️ Testing complexity

**Complexity:** Medium (3-4 дня)

---

### Variant 4: Hybrid Local + Cloud

**Architecture:**
```
┌─────────────────────────────────────────────────┐
│              Moltis Fallback Chain              │
│                                                  │
│  ┌──────────┐   FAIL   ┌──────────────┐  FAIL   │
│  │ GLM API  │─────────▶│ Ollama Local │────────▶│
│  │ (Primary)│          │ (Fast Fallback)         │
│  └──────────┘          └──────────────┘         │
│                              │                   │
│                              │ CLOUD FALLBACK    │
│                              ▼                   │
│                        ┌──────────────┐          │
│                        │ Ollama Cloud │          │
│                        │ (Deep Fallback)        │
│                        └──────────────┘          │
└─────────────────────────────────────────────────┘
```

**Configuration:**
```toml
[providers.openai]
enabled = true
alias = "glm"

[providers.ollama]
enabled = true
base_url = "http://localhost:11434"
model = "llama3.2:3b"  # Local fast fallback
alias = "ollama-local"

[providers.ollama-cloud]
enabled = true
base_url = "https://ollama.com"
api_key = "${OLLAMA_API_KEY}"
model = "gemini-3-flash-preview:cloud"
alias = "ollama-cloud"

[failover]
enabled = true
fallback_models = [
  "ollama-local::llama3.2:3b",
  "ollama-cloud::gemini-3-flash-preview:cloud"
]
```

**Pros:**
- ✅ 3-tier redundancy
- ✅ Local fallback для low latency
- ✅ Cloud fallback для disaster recovery

**Cons:**
- ⚠️ Максимальная сложность конфигурации
- ⚠️ Требует оба: local resources + cloud subscription
- ⚠️ Testing 3 fallback paths

**Complexity:** High (5-7 дней)

---

### Variant 5: API Gateway (Traefik Proxy)

**Architecture:**
```
┌─────────────────────────────────────────────────┐
│              Traefik API Gateway                │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │  Load Balancer + Health Checks           │   │
│  │                                          │   │
│  │  /llm/*  →  GLM API (weight: 100)       │   │
│  │          →  Ollama (weight: 0, fallback)│   │
│  └──────────────────────────────────────────┘   │
│              │                   │               │
│              ▼                   ▼               │
│  ┌──────────────────┐  ┌──────────────────┐     │
│  │ GLM API (Z.ai)   │  │ Ollama Sidecar   │     │
│  └──────────────────┘  └──────────────────┘     │
└─────────────────────────────────────────────────┘
```

**Pros:**
- ✅ Centralized routing
- ✅ Built-in health checks
- ✅ Rate limiting support

**Cons:**
- ⚠️ Traefik не поддерживает external API load balancing (GLM - external)
- ⚠️ Complex routing rules
- ⚠️ Limited LLM-specific features

**Complexity:** High (5-7 дней)

---

## Trade-offs Summary

| Variant | Latency | Cost | Reliability | Complexity |
|---------|---------|------|-------------|------------|
| 1. Sidecar | Medium | Low | High | Low |
| 2. Cloud Direct | High | Medium | Medium | Very Low |
| 3. Circuit Breaker | Low | Low | Very High | Medium |
| 4. Hybrid | Very Low | Medium | Very High | High |
| 5. API Gateway | Medium | Low | High | High |

---

## Consensus

**Agreed Points:**
1. ✅ Ollama sidecar в Docker Compose - оптимальный вариант
2. ✅ Docker secrets для OLLAMA_API_KEY (security)
3. ✅ Health probes для GLM и Ollama (5s interval)
4. ✅ Circuit breaker pattern для automatic fallback
5. ✅ Метрики: `llm_fallback_triggered_total`, `llm_provider_available`
6. ✅ SLI/SLO: Availability 99.5%, Latency P95 < 5s
7. ✅ Backup не нужен для Ollama (кэш)
8. ✅ CI/CD validation в preflight + smoke tests в verify

**Disagreements:**
- ⚠️ **Local vs Cloud Ollama**: iac-expert предлагает sidecar, prometheus-expert требует exporter (дополнительная работа)
- **Resolution:** Начать с sidecar (Variant 1), добавить exporter позже

---

## Final Recommendation

**Recommended Variant: #1 Ollama Sidecar + Circuit Breaker (#3)**

**Rationale:**
1. **Minimal invasion** - добавить 1 сервис в docker-compose.prod.yml
2. **Fast implementation** - 2-3 дня для базовой версии
3. **High reliability** - circuit breaker обеспечивает automatic failover
4. **Low cost** - нет cloud subscription (local inference)
5. **GitOps compliant** - конфигурация в git, secrets через Docker secrets

**Implementation Plan:**
```
Phase 1 (1 день): Ollama sidecar + Docker secrets
Phase 2 (1 день): Health probes + circuit breaker
Phase 3 (1 день): Metrics + Prometheus integration
Phase 4 (1 день): CI/CD validation + smoke tests
```

**Config Changes:**
```toml
# config/moltis.toml
[providers.ollama]
enabled = true
base_url = "http://ollama:11434"
model = "gemini-3-flash-preview:cloud"

[failover]
enabled = true
fallback_models = ["ollama::gemini-3-flash-preview:cloud"]
```

---

## Confidence Level

- **High** (4/5 экспертов согласны, 1 требует доработок)
- **Consensus Strength:** Strong (базовая архитектура одобрена, детали реализации обсуждаются)

---

## Next Steps

1. **Утвердить Variant 1** (Ollama Sidecar) с пользователем
2. **Добавить Ollama сервис** в docker-compose.prod.yml
3. **Настроить Docker secrets** для OLLAMA_API_KEY
4. **Реализовать circuit breaker** в health-monitor.sh
5. **Добавить метрики** для Prometheus
6. **Написать smoke tests** для CI/CD

---

## Appendix: Key Metrics & Alerts

### Prometheus Metrics
```promql
# Request counter
llm_request_total{provider, model, status}

# Latency histogram
llm_request_duration_seconds{provider, model}

# Fallback counter
llm_fallback_triggered_total{from_provider, to_provider, reason}

# Provider availability gauge
llm_provider_available{provider}
```

### Alert Rules
```yaml
# API недоступен (>5 мин)
- alert: GLMAPIUnavailable
  expr: llm_provider_available{provider="glm"} == 0
  for: 5m

# Высокий rate fallback'ов
- alert: HighFallbackRate
  expr: rate(llm_fallback_triggered_total[5m]) > 0.1
  for: 10m

# Высокая latency P95
- alert: LLMLatencyDegraded
  expr: histogram_quantile(0.95, llm_request_duration_seconds) > 10
  for: 5m
```

### SLI/SLO Targets
| Metric | Target | Warning |
|--------|--------|---------|
| Availability | 99.5% | < 99% |
| Latency P95 | < 5s | > 10s |
| Fallback Rate | < 0.5% | > 5% |

---

*Report generated: 2026-03-01*
*Experts consulted: 5/19 (rate limit constraints)*
*Consensus: Strong*
