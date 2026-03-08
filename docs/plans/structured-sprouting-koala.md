# Plan: Comprehensive Automated Tests for Moltis Agent

> Historical note: Этот план фиксирует pre-lane taxonomy (`tests/unit`, `tests/integration`, `tests/security`, `tests/e2e`). Текущий authoritative baseline для тестов описан в `tests/README.md` и `specs/001-docker-deploy-improvements/contracts/test-lanes.md`.

## Context

**Problem**: Moltis агент развёрнут в production, но отсутствуют комплексные автоматические тесты для проверки работоспособности. Существующие тесты (test-moltis-api.sh, smoke tests) покрывают только базовые сценарии.

**Goal**: Создать 3-уровневую систему тестирования (Unit → Integration → E2E) для автоматической валидации всех критических компонентов Moltis.

**Key Components to Test**:
- API endpoints (/health, /login, /api/v1/chat, /metrics)
- LLM Providers (GLM-5 primary, Ollama fallback, Gemini secondary)
- Circuit Breaker state machine (CLOSED → OPEN → HALF-OPEN)
- MCP Servers (Context7, Sequential Thinking, Supabase, Playwright, Shadcn, Serena)
- Telegram Bot (@moltinger_bot)
- Health Monitoring & Prometheus metrics

---

## Test Architecture

```
tests/
├── unit/           # Level 1: <30s, isolated components
├── integration/    # Level 2: <2min, component interactions
├── e2e/            # Level 3: <5min, full scenarios
├── security/       # Auth & input validation
└── lib/            # Shared test utilities
```

---

## Phase 1: Unit Tests (P0 Critical)

### 1.1 Circuit Breaker State Machine
**File**: `tests/unit/test_circuit_breaker.sh`

Tests:
- CLOSED → OPEN transition (after 3 failures)
- OPEN → HALF-OPEN transition (after 300s recovery)
- HALF-OPEN → CLOSED transition (after 2 successes)
- HALF-OPEN → OPEN transition (on failure)

**Reuse**: Logic from `scripts/health-monitor.sh`

### 1.2 Configuration Validation
**File**: `tests/unit/test_config_validation.sh`

Tests:
- TOML syntax for `config/moltis.toml`
- YAML syntax for `docker-compose.yml`
- Required secrets presence
- Environment variable substitution

**Reuse**: Patterns from `scripts/preflight-check.sh`

### 1.3 Prometheus Metrics Format
**File**: `tests/unit/test_prometheus_metrics.sh`

Tests:
- Metric naming conventions
- Expected metrics present:
  - `llm_provider_available{provider="glm"}`
  - `llm_provider_available{provider="ollama"}`
  - `moltis_circuit_state`
  - `llm_fallback_triggered_total`

---

## Phase 2: Integration Tests (P0-P1)

### 2.1 LLM Provider Failover (P0)
**File**: `tests/integration/test_llm_failover.sh`

| Scenario | Expected Result |
|----------|-----------------|
| GLM healthy | circuit: CLOSED |
| GLM down, Ollama up | circuit: OPEN |
| Both down | Alert triggered |
| Recovery | circuit: CLOSED |

**Reuse**: Functions from `scripts/health-monitor.sh` and `scripts/ollama-health.sh`

### 2.2 API Endpoints (P0)
**File**: `tests/integration/test_api_endpoints.sh`

| Endpoint | Method | Auth | Expected |
|----------|--------|------|----------|
| `/health` | GET | No | 200 |
| `/login` | POST | Password | 200/302 |
| `/api/v1/chat` | POST | Cookie | 200 |
| `/metrics` | GET | No | 200 |
| `/api/mcp/servers` | GET | Cookie | 200 |

**Reuse**: Patterns from `scripts/test-moltis-api.sh`

### 2.3 MCP Servers Connectivity (P1)
**File**: `tests/integration/test_mcp_servers.sh`

Tests for each MCP server:
- Process running check
- Tools list availability via API

Servers: Context7, Sequential Thinking, Supabase, Playwright, Shadcn, Serena

### 2.4 Telegram Bot Integration (P1)
**File**: `tests/integration/test_telegram_integration.sh`

Tests:
- Bot token validity (getMe API)
- Webhook configuration
- Message send/receive flow

---

## Phase 3: E2E Tests (P0-P2)

### 3.1 Complete Chat Flow (P0)
**File**: `tests/e2e/test_chat_flow.sh`

Flow:
1. POST /login → Session cookie
2. POST /api/v1/chat {"message": "Hello"}
3. Poll for response (timeout: 30s)
4. Verify response content
5. Follow-up question → Verify context maintained

### 3.2 Full Failover Chain (P0)
**File**: `tests/e2e/test_full_failover_chain.sh`

Flow:
1. All providers healthy → GLM-5 responds
2. Block GLM API → Ollama responds
3. Block Ollama → Gemini responds
4. Restore GLM → Automatic recovery

### 3.3 Deployment Recovery (P1)
**File**: `tests/e2e/test_deployment_recovery.sh`

Flow:
1. Record session state
2. `docker restart moltis`
3. Wait for health check
4. Verify session restored

### 3.4 Rate Limiting (P2)
**File**: `tests/e2e/test_rate_limiting.sh`

Tests:
- Concurrent requests handling
- Response time metrics (P50, P95, P99)
- Rate limit (HTTP 429) handling

---

## Phase 4: Security Tests (P0-P1)

### 4.1 Authentication (P0)
**File**: `tests/security/test_authentication.sh`

Tests:
- Invalid password rejection
- Session expiration
- Unauthenticated access blocked

### 4.2 Input Validation (P1)
**File**: `tests/security/test_input_validation.sh`

Tests:
- Message size limits
- Special character handling
- Sandbox isolation

---

## Test Infrastructure

### Helper Library
**File**: `tests/lib/test_helpers.sh`

Functions:
- `assert_eq(expected, actual, message)`
- `assert_http_code(expected, url)`
- `mock_glm_failure()` / `restore_glm()`
- `generate_report()`

### CI/CD Integration
**File**: `.github/workflows/test.yml`

Jobs:
1. `unit-tests` - Run on every PR
2. `integration-tests` - Run on PR (with Moltis container)
3. `e2e-tests` - Manual trigger or before deploy

### Makefile Targets
```makefile
test-unit:        ./tests/run_unit.sh
test-integration: ./tests/run_integration.sh
test-e2e:         ./tests/run_e2e.sh
test-all:         test-unit test-integration test-e2e
```

---

## Implementation Order (Full Suite)

| Week | Tests | Priority |
|------|-------|----------|
| 1 | Circuit breaker, API endpoints, Chat flow, Auth | P0 |
| 2 | LLM failover, Full failover chain, Config validation, MCP servers | P0-P1 |
| 3 | Prometheus metrics, **Telegram (CI/CD + secrets)**, Deployment recovery, Input validation | P1 |
| 4 | Session storage, Rate limiting, WebSocket, Performance benchmarks | P2 |

**Scope**: Full Suite (все тесты P0-P2)
**Telegram**: Интеграция в CI/CD с использованием GitHub Secrets (TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS)

---

## Critical Files to Reuse

| File | Patterns to Reuse |
|------|-------------------|
| `scripts/health-monitor.sh` | Circuit breaker logic, LLM health checks |
| `scripts/preflight-check.sh` | Config validation patterns |
| `scripts/test-moltis-api.sh` | API authentication flow |
| `scripts/ollama-health.sh` | Ollama health check logic |
| `config/prometheus/alert-rules.yml` | Metrics to validate |

---

## Verification

After implementation:
1. Run `make test-unit` → All P0 tests pass
2. Run `make test-integration` → All integration tests pass
3. Run `make test-e2e` → E2E scenarios complete <5min
4. CI/CD pipeline includes test gates before deploy
5. Test results visible in GitHub Actions

---

## Summary

**Total Tests**: 15 test files
**Estimated Duration**: Unit (30s) + Integration (2min) + E2E (5min) = ~8min
**Coverage**: API, LLM failover, Circuit breaker, MCP, Telegram, Security
