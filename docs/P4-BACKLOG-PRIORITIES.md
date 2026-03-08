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

---

## Task Details

### 1. moltinger-xh7: Fallback LLM Provider

**Problem:** GLM-5 (Z.ai) is the only LLM provider. If API fails → Moltis stops working.

**Solution:** Add Groq (free, fast) or Anthropic as fallback.

**Current State:**
```toml
# config/moltis.toml - only GLM
[providers.openai]
enabled = true
base_url = "https://api.z.ai/api/anthropic"
model = "glm-5"
```

**Implementation:**
1. Add Groq provider configuration
2. Configure fallback chain in Moltis
3. Test fallback behavior

**ROI:** ⭐⭐⭐⭐⭐ Critical for production reliability

---

### 2. moltinger-sjx: S3 Offsite Backup

**Problem:** Backups only stored locally. If server dies → data lost.

**Solution:** Duplicate backups to S3-compatible storage (Wasabi, AWS, Backblaze).

**Current State:**
```bash
# backup-moltis-enhanced.sh already supports S3
S3_ENABLED=false  # ← need to enable
```

**Implementation:**
1. Add S3 credentials to GitHub Secrets
2. Update backup config with S3 settings
3. Enable S3_ENABLED=true
4. Test backup upload

**ROI:** ⭐⭐⭐⭐ Protection of critical data

---

### 3. moltinger-r8r: Traefik Rate Limiting

**Problem:** No abuse/DDoS protection at reverse proxy level.

**Solution:** Configure rate limiting middleware in Traefik.

**Implementation:**
1. Add rateLimit middleware to Traefik config
2. Apply to moltis router
3. Test with curl burst

**ROI:** ⭐⭐⭐ Protection from primitive attacks

---

### 4. moltinger-j22: AlertManager Receivers

**Problem:** AlertManager configured but doesn't send notifications.

**Solution:** Configure receivers for Slack/Telegram.

**Implementation:**
1. Add Slack webhook or Telegram bot config
2. Update alertmanager.yml
3. Test alert delivery

**ROI:** ⭐⭐⭐ Quick incident response

---

### 5. moltinger-eb0: Grafana Dashboard

**Problem:** Prometheus collects metrics but no visualization.

**Solution:** Add Grafana with pre-configured dashboard.

**Implementation:**
1. Add Grafana to docker-compose.prod.yml
2. Configure Prometheus datasource
3. Import Moltis dashboard

**ROI:** ⭐⭐⭐ Monitoring convenience

---

## Low Priority Tasks

### moltinger-ipo: Loki + Promtail
- Log aggregation system
- Requires new infrastructure
- Current ROI: Low (logs available via docker logs)

### moltinger-da0: Backup Encryption Vault
- Secure key storage (HashiCorp Vault or similar)
- Current state: key in /etc/moltis/backup.key
- Current ROI: Low (already working)

### moltinger-6ql: SearXNG Web Search
- Self-hosted web search for Moltis
- Current state: Tavily API working
- Current ROI: Low (alternative already available)

---

## Do Not Do

### moltinger-9qh: Remove Privileged Mode
- **Why not:** Moltis requires privileged mode for Docker-in-Docker sandbox execution
- **Impact:** Would break Moltis core functionality
- **Status:** Closed as "won't fix" - architectural requirement

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
| `tests/integration/test_llm_failover.sh` | ❌ Баг | Неверный `PROJECT_ROOT` путь |
| `tests/e2e/test_full_failover_chain.sh` | ❓ Не проверен | Требует Docker |
| CI/CD integration | ❌ Отсутствует | Только shellcheck/yamllint |

### Bugs Found

**BUG-1**: `tests/integration/test_llm_failover.sh:38`
```bash
# Текущий (неверный):
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")/../.."  # = moltinger/../.. = coding/

# Должен быть:
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")/.."      # = moltinger/tests/.. = moltinger/
```

### Tasks (from spec 003-testing-infrastructure)

#### Phase A: Fix Critical Bugs (P1)
- [ ] **T-TEST-001**: Исправить `PROJECT_ROOT` в `tests/integration/test_llm_failover.sh`
- [ ] **T-TEST-002**: Проверить и исправить пути во всех integration тестах
- [ ] **T-TEST-003**: Добавить pre-flight check на Docker daemon в integration тесты

#### Phase B: CI/CD Integration (P1)
- [ ] **T-TEST-004**: Добавить job `test-unit` в `.github/workflows/deploy.yml`
- [ ] **T-TEST-005**: Добавить job `test-integration` в `.github/workflows/deploy.yml`
- [ ] **T-TEST-006**: Сделать deploy зависимым от успешного прохождения тестов
- [ ] **T-TEST-007**: Добавить upload test results artifact

#### Phase C: Test Coverage for Fallback LLM (P2)
- [ ] **T-TEST-008**: Добавить тест GLM → Ollama failover в `test_llm_failover.sh`
- [ ] **T-TEST-009**: Добавить тест Ollama recovery (HALF-OPEN → CLOSED)
- [ ] **T-TEST-010**: Добавить тест Prometheus metrics при failover
- [ ] **T-TEST-011**: Добавить E2E тест полного цикла failover в `test_full_failover_chain.sh`

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

Следующие задачи из `moltinger-39q` должны быть закрыты после завершения тестирования:
- `moltinger-39q.4.1`: T009 Create scripts/ollama-health.sh → добавить тест
- `moltinger-39q.4.2`: T010 Add GLM health check → добавить тест
- `moltinger-39q.4.3-7`: T011-T015 Circuit breaker → покрыть тестами
- `moltinger-39q.5.1-6`: T016-T021 Prometheus metrics → покрыть тестами

---

## Session Progress

| Date | Completed |
|------|-----------|
| 2026-02-28 | moltinger-hdn (backup cron), moltinger-kpt (pre-deploy tests), moltinger-eml (sed fix) |
| 2026-03-03 | Added Testing Technical Debt section |

---

*Last updated: 2026-03-03*
