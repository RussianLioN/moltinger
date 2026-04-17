# Data Model: Fallback LLM with Ollama Cloud

**Feature**: 001-fallback-llm-ollama
**Date**: 2026-03-01

## Entity Overview

```
┌─────────────────┐     ┌─────────────────────┐
│  LLM Provider   │     │  Circuit Breaker    │
│  (2 instances)  │────▶│  State              │
│  - openai-codex │     │  (1 instance)       │
│  - ollama       │     └─────────────────────┘
└────────┬────────┘              │
         │                       │
         │                       ▼
         │              ┌─────────────────────┐
         └─────────────▶│  Failover Event     │
                        │  (N instances)      │
                        └─────────────────────┘
```

## Entity Definitions

### 1. LLM Provider

Represents an LLM API provider (primary or fallback).

**Fields**:

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| name | string | Provider identifier | "openai-codex", "ollama" |
| type | enum | Provider type | "primary", "fallback" |
| status | enum | Current availability | "available", "unavailable", "degraded" |
| base_url | string | API endpoint | "http://localhost:11434" |
| model | string | Model identifier | "gpt-5.4", "gemini-3-flash-preview:cloud" |
| latency_p95 | number | 95th percentile latency (ms) | 2500, 12000 |
| error_count | number | Consecutive errors | 0, 3 |
| last_check | timestamp | Last health check time | "2026-03-01T12:00:00Z" |

**Validation Rules**:
- `name` must be unique across providers
- `status` must transition: available ↔ unavailable (no direct to degraded)
- `error_count` resets to 0 on successful health check

**State Transitions**:
```
available ──(3 failures)──▶ unavailable
unavailable ──(success)──▶ available
available ──(high latency)──▶ degraded
degraded ──(success)──▶ available
```

---

### 2. Circuit Breaker State

Manages failover state machine.

**Fields**:

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| state | enum | Circuit breaker state | "closed", "open", "half-open" |
| current_provider | string | Active provider | "openai-codex", "ollama" |
| failure_count | number | Consecutive failures | 0, 3 |
| success_count | number | Consecutive successes (half-open) | 0, 2 |
| last_failure | timestamp | Last failure time | "2026-03-01T12:00:00Z" |
| last_success | timestamp | Last success time | "2026-03-01T12:00:05Z" |
| last_switch | timestamp | Last provider switch | "2026-03-01T11:55:00Z" |
| open_since | timestamp | When circuit opened | null, "2026-03-01T11:55:00Z" |

**Validation Rules**:
- `failure_count` max = 3 (then circuit opens)
- `success_count` required in half-open state
- `open_since` required when state = "open"

**State Transitions**:
```
┌───────────────────────────────────────────────────────┐
│                                                       │
│   CLOSED ◀───────────────────────────────────────┐   │
│      │                                            │   │
│      │ (3 failures)                               │   │
│      ▼                                            │   │
│   OPEN ───(60s timeout)──▶ HALF-OPEN              │   │
│      ▲                        │                   │   │
│      │                        │ (success)         │   │
│      │                        ▼                   │   │
│      │               (2 successes) ───────────────┘   │
│      │                        │                       │
│      │                        │ (failure)             │
│      └────────────────────────┘                       │
│                                                       │
└───────────────────────────────────────────────────────┘
```

---

### 3. Failover Event

Records provider switches for observability.

**Fields**:

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| timestamp | timestamp | Event time | "2026-03-01T11:55:00Z" |
| from_provider | string | Previous provider | "openai-codex" |
| to_provider | string | New provider | "ollama" |
| reason | enum | Switch reason | "health_check_failure", "manual", "recovery" |
| failure_count | number | Failures that triggered switch | 3 |
| recovery_time_ms | number | Time to recover (if applicable) | 15000 |

**Validation Rules**:
- `from_provider` ≠ `to_provider`
- `reason` must match state transition

**Event Types**:
| Reason | Trigger | Expected Frequency |
|--------|---------|-------------------|
| health_check_failure | 3 consecutive failures | Rare (< 1/month) |
| recovery | Primary provider restored after outage | Rare |
| manual | Admin intervention | Very rare |

---

## Configuration Schema (TOML)

### Moltis Provider Configuration

```toml
[providers.openai-codex]
enabled = true
model = "gpt-5.4"
alias = "openai-codex"
models = ["gpt-5.4"]

[providers.ollama]
enabled = true
base_url = "http://ollama:11434"
model = "gemini-3-flash-preview:cloud"
alias = "ollama"
# Optional: api_key for cloud models
api_key = "${OLLAMA_API_KEY}"

[chat]
allowed_models = [
  "openai-codex::gpt-5.4",
  "ollama::gemini-3-flash-preview:cloud"
]
priority_models = [
  "openai-codex::gpt-5.4",
  "ollama::gemini-3-flash-preview:cloud"
]

[failover]
enabled = true
fallback_models = [
  "ollama::gemini-3-flash-preview:cloud"
]
health_check_interval = "5s"
failure_threshold = 3
recovery_timeout = "60s"
```

---

## Storage Locations

| Entity | Location | Format | Persistence |
|--------|----------|--------|-------------|
| Circuit Breaker State | /tmp/moltis-llm-state.json | JSON | Ephemeral (RAM) |
| Failover Events | Prometheus metrics | Time series | 15 days |
| Provider Config | config/moltis.toml | TOML | Git (versioned) |
| API Keys | Docker secrets | File | Docker managed |

---

## Metrics Export

### Prometheus Metrics

```
# Provider availability (gauge)
llm_provider_available{provider="openai-codex"} 1
llm_provider_available{provider="ollama"} 1

# Failover counter
llm_fallback_triggered_total{from="openai-codex",to="ollama",reason="health_check_failure"} 2

# Circuit breaker state
moltis_circuit_state{provider="openai-codex"} 0  # 0=closed, 1=open, 2=half-open

# Provider latency
llm_request_duration_seconds{provider="openai-codex",quantile="0.95"} 2.5
```

---

## Data Retention

| Data Type | Retention | Reason |
|-----------|-----------|--------|
| Circuit Breaker State | Ephemeral | Recreated on restart |
| Prometheus Metrics | 15 days | Standard retention |
| Failover Events | 15 days | Via Prometheus |
| Config History | Forever | Git versioned |
