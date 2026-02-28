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

## Session Progress

| Date | Completed |
|------|-----------|
| 2026-02-28 | moltinger-hdn (backup cron), moltinger-kpt (pre-deploy tests), moltinger-eml (sed fix) |

---

*Last updated: 2026-02-28*
