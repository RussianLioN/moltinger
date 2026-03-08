# P4 Backlog Priorities

> Created: 2026-02-28
> Status: Planning
> Context: AI Agent Factory reliability improvements

---

## Priority Matrix

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    VALUE FOR AI AGENT FACTORY                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  CRITICAL        moltinger-xh7: Fallback LLM Provider                  │
│  (blocks work)   → If GLM-5 fails, Moltis continues                    │
│                  → Groq (free) or Anthropic as backup                  │
│                                                                         │
│  HIGH            moltinger-sjx: S3 Offsite Backup                      │
│  (data safety)   → Disaster recovery                                   │
│                  → Backup duplication to cloud                          │
│                                                                         │
│  MEDIUM          moltinger-eb0: Grafana Dashboard                      │
│  (operations)    moltinger-j22: AlertManager Receivers                 │
│                  moltinger-r8r: Traefik Rate Limiting                  │
│                                                                         │
│  LOW             moltinger-ipo: Loki + Promtail                        │
│  (nice to have)  moltinger-da0: Backup Encryption Vault                │
│                  moltinger-6ql: SearXNG Web Search                     │
│                                                                         │
│  DO NOT DO       moltinger-9qh: Remove Privileged Mode                 │
│                  → Moltis requires for Docker-in-Docker sandbox        │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Recommended Implementation Order

| # | Task ID | Task | Time | Dependencies | Why |
|---|---------|------|------|--------------|-----|
| **1** | `moltinger-xh7` | Fallback LLM Provider | 30-60m | API key for Groq/Anthropic | Critical - Moltis doesn't work without LLM |
| **2** | `moltinger-sjx` | S3 Offsite Backup | 45-60m | S3 credentials | Data protection - disaster recovery |
| **3** | `moltinger-r8r` | Traefik Rate Limiting | 20-30m | None | Quick win - abuse protection |
| **4** | `moltinger-j22` | AlertManager Receivers | 30-45m | Slack webhook / Telegram bot | Operations - incident notifications |
| **5** | `moltinger-eb0` | Grafana Dashboard | 1-2h | Prometheus (already running) | Improvement - metrics visualization |
| **6** | `moltinger-esr` | Testing Technical Debt - Fallback LLM | 4-6h | None | Tests exist but not integrated in CI/CD |

---

## Testing Technical Debt (Fallback LLM)

> **Source**: Ветка `003-testing-infrastructure` (1 неслитый коммит), spec `specs/003-testing-infrastructure/`
> **Context**: Тесты написаны, но НЕ интегрированы в CI/CD и имеют баги
> **Historical note**: Ниже перечислены pre-lane пути (`tests/unit`, `tests/integration`, `tests/security`, `tests/e2e`). Canonical test model теперь описан в `tests/README.md` и `specs/001-docker-deploy-improvements/contracts/test-lanes.md`.

### Current State

| Компонент | Статус | Проблема |
|-----------|--------|----------|
| `tests/unit/test_circuit_breaker.sh` | ✅ Работает | 10 тестов проходят |
| `tests/unit/test_prometheus_metrics.sh` | ✅ Работает | - |
| `tests/unit/test_config_validation.sh` | ✅ Работает | - |
| `tests/integration/test_llm_failover.sh` | ❌ Баг | Неверный `PROJECT_ROOT` путь |
| `tests/e2e/test_full_failover_chain.sh` | ❓ Не проверен | Требует Docker |
| CI/CD integration | ❌ Отсутствует | Только shellcheck/yamllint в deploy.yml |

### Bugs Found

**BUG-1**: `tests/integration/test_llm_failover.sh:38`
```bash
# Текущий (неверный):
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")/../.."  # = moltinger/../.. = coding/

# Должен быть:
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")/.."      # = moltinger/tests/..
```

### Tasks (from spec 003-testing-infrastructure)

#### Phase A: Fix Critical Bugs (P1)
- [ ] **T-TEST-001**: Исправить `PROJECT_ROOT` в `tests/integration/test_llm_failover.sh`
- [ ] **T-TEST-002**: Audit all integration test paths (blocked by: moltinger-3y9)
- [ ] **T-TEST-003**: Добав Docker daemon pre-flight check (blocked by: moltinger-3y9)

#### Phase B: CI/CD Integration (P1)
- [ ] **T-TEST-004**: Добав job `test-unit` в `.github/workflows/deploy.yml`
- [ ] **T-TEST-005**: Добав job `test-integration` в `.github/workflows/deploy.yml`
- [ ] **T-TEST-006**: Сделать deploy зависимым от успеш tests (blocked by: moltinger-39q.6)
- [ ] **T-TEST-007**: Добав upload test results artifact

#### Phase C: Test Coverage for Fallback LLM (P2)
- [ ] **T-TEST-008**: Добавить тест GLM →Ollama failover в `test_llm_failover.sh`
- [ ] **T-TEST-009**: Добавить тест Ollama recovery (HALF-OPEN → CLOSED)
- [ ] **T-TEST-010**: Добавить тест Prometheus metrics при failover
- [ ] **T-TEST-011**: Добавить E2E тест полного failover chain в `test_full_failover_chain.sh`

#### Phase D: Documentation (P3)
- [ ] **T-TEST-012**: Обновить `tests/README.md` с инструкциями для CI/CD
- [ ] **T-TEST-013**: Добавить test coverage badge в README.md
- [ ] **T-TEST-014**: Документировать как добавлять новые тесты

### Estimated Effort

| Phase | Tasks | Time |
|-------|-------|------|
| Phase A: Bugs | 3 | 30m |
| Phase B: CI/CD | 4 | 1-2h |
| Phase C: Coverage | 4 | 2-3h |
| Phase D: Docs | 3 | 30m |
| **Total** | **14** | **4-6h** |

### Related Beads Tasks (to close)

Следующие задачи из `moltinger-39q` должны быть закры после заверш тестирования:
- `moltinger-39q.4.1`: T009 Create scripts/ollama-health.sh → добавить тест
- `moltinger-39q.4.2`: T010 Add GLM health check → покрыть тестами
- `moltinger-39q.4.3-7`: T011-T015 Circuit breaker → покрыть тестами

### Related Beads Tasks (to close)

Следующие задачи из `moltinger-39q` должны быть закры after заверш тестирования:
- `moltinger-39q.5.1-6`: T016-T021 Prometheus metrics → покрыть тестами
