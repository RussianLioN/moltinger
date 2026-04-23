# GitOps & Infrastructure Roadmap

> **Last Updated**: 2026-04-09
> **Status**: Active Development

---

## 📊 Progress Overview

```
Phase 1 (Foundation)     ████████████ 100% ✅
Phase 2 (Security)       ████████░░░░  75% 🔄
Phase 3 (Observability)  ████░░░░░░░░  30% 🔄
Phase 4 (GitOps 2.0)     ██░░░░░░░░░░  15% 📋
Phase 5 (IaC)            ░░░░░░░░░░░░   0% 📋
```

---

## ✅ Current Priority Repairs

| ID | Task | Status | Notes |
|----|------|--------|-------|
| F0 | Deterministic hermetic PR test foundation | ✅ DONE | `compose.test.yml` now isolates workspace `node_modules`; CI moved to lockfile + `npm ci` |
| F1 | Read-only verification tooling | ✅ DONE | `scripts/scripts-verify.sh` no longer rewrites hash baseline during ordinary verify runs |
| F2 | Test runner/docs contract sync | ✅ DONE | lane group docs, workflow install contract, and test stack guards now match the canonical runner |

---

## ✅ Phase 1: Foundation (DONE)

| ID | Task | Status | Commit |
|----|------|--------|--------|
| P0-1 | ssh/scp в ASK list (settings.json) | ✅ DONE | - |
| P0-2 | Blocking rule в CLAUDE.md | ✅ DONE | - |
| P0-3 | scripts/ в CI/CD sync | ✅ DONE | c74ce8e |
| P0-4 | Fix duplicate `ask` key | ✅ DONE | b9ed51d |
| P0-5 | Sandbox mode enabled | ✅ DONE | 27041d2 |
| P0-6 | Heredoc workaround documented | ✅ DONE | 1b2da3b |
| P0-7 | Context7 MCP in allowlist | ✅ DONE | b9c8db7 |
| P0-8 | SSH/git push в исключениях sandbox | ✅ DONE | 86783ee, cd3c38c |

---

## 🔄 Phase 2: Security Hardening

### In Progress

| ID | Task | Priority | Issue | Status |
|----|------|----------|-------|--------|
| S1 | Remove privileged mode from container | P4 | moltinger-9qh | 🔴 Blocked |
| S2 | Backup encryption key to vault | P4 | moltinger-da0 | 📋 Pending |
| S3 | Replace sed -i with GitOps approach | P4 | moltinger-eml | 📋 Pending |

### Planned

| ID | Task | Priority | Effort |
|----|------|----------|--------|
| S4 | SOPS for encrypted secrets in git | P3 | 2h |
| S5 | Secret rotation automation | P3 | 3h |
| S6 | Container security scanning (Trivy) | P2 | 1h |
| S7 | Network policies (if K8s) | P3 | 2h |

---

## 🔄 Phase 3: Observability & Monitoring

### In Progress (Beads Issues)

| ID | Task | Priority | Issue | Status |
|----|------|----------|-------|--------|
| M1 | Grafana dashboard for Moltis | P4 | moltinger-eb0 | 📋 Pending |
| M2 | AlertManager receivers (Slack/Telegram) | P4 | moltinger-j22 | 📋 Pending |
| M3 | Loki + Promtail for logs | P4 | moltinger-ipo | 📋 Pending |

### Planned (New)

| ID | Task | Priority | Effort | Status |
|----|------|----------|--------|--------|
| M4 | Uptime Kuma deployment | P2 | 30m | 📋 Proposed |
| M5 | Prometheus metrics endpoint | P2 | 1h | 📋 Proposed |
| M6 | Log retention policy (30 days) | P3 | 30m | 📋 Proposed |
| M7 | Health check dashboard | P3 | 1h | 📋 Proposed |

---

## 📋 Phase 4: GitOps 2.0

### In Progress (Beads Issues)

| ID | Task | Priority | Issue | Status |
|----|------|----------|-------|--------|
| G1 | Pre-deployment tests in CI/CD | P4 | moltinger-kpt | 📋 Pending |
| G2 | S3 offsite backup for DR | P4 | moltinger-sjx | 📋 Pending |

### Planned (New)

| ID | Task | Priority | Effort | Status |
|----|------|----------|--------|--------|
| G3 | Pull-based GitOps (cron/systemd) | P2 | 2h | 📋 Proposed |
| G4 | Drift detection script | P2 | 1h | 📋 Proposed |
| G5 | Staging environment | P3 | 2h | 📋 Proposed |
| G6 | Rollback automation tests | P3 | 1h | 📋 Proposed |
| G7 | GitOps compliance verification | P2 | 1h | 📋 Proposed |

---

## 📋 Phase 5: Infrastructure as Code

### Planned (New)

| ID | Task | Priority | Effort | Status |
|----|------|----------|--------|--------|
| I1 | Terraform for server provisioning | P3 | 4h | 📋 Proposed |
| I2 | Ansible for server configuration | P3 | 3h | 📋 Proposed |
| I3 | Disaster recovery documentation | P2 | 2h | 📋 Proposed |
| I4 | Infrastructure tests (Terratest) | P4 | 3h | 📋 Proposed |

---

## 📋 Phase 6: Reliability & Resilience

### In Progress (Beads Issues)

| ID | Task | Priority | Issue | Status |
|----|------|----------|-------|--------|
| R1 | Fallback LLM hardening (Ollama cloud only) | P4 | moltinger-xh7 | 📋 Pending |
| R2 | SearXNG self-hosted search | P4 | moltinger-6ql | 📋 Pending |

### Planned (New)

| ID | Task | Priority | Effort | Status |
|----|------|----------|--------|--------|
| R3 | Circuit breaker for external APIs | P3 | 2h | 📋 Proposed |
| R4 | Rate limiting implementation | P3 | 1h | 📋 Proposed |
| R5 | Graceful degradation mode | P3 | 2h | 📋 Proposed |

---

## 📋 Phase 7: Developer Experience

### Planned (New)

| ID | Task | Priority | Effort | Status |
|----|------|----------|--------|--------|
| D1 | Pre-commit hooks setup | P2 | 30m | 📋 Proposed |
| D2 | Makefile unification | P3 | 1h | 📋 Proposed |
| D3 | Development environment (devcontainer) | P4 | 2h | 📋 Proposed |
| D4 | CI/CD pipeline visualization | P4 | 1h | 📋 Proposed |

---

## 🗓️ Recommended Execution Order

### Week 1: Quick Wins
```
Day 1-2: M4 (Uptime Kuma) + D1 (Pre-commit hooks)
Day 3-4: M1 (Grafana) + M2 (AlertManager)
Day 5: G1 (Pre-deployment tests)
```

### Week 2: Security
```
Day 1-2: S1 (Remove privileged) + S6 (Trivy scanning)
Day 3-4: S4 (SOPS) + S2 (Vault backup)
Day 5: S3 (sed → GitOps)
```

### Week 3: GitOps 2.0
```
Day 1-2: G3 (Pull-based) + G4 (Drift detection)
Day 3-4: G2 (S3 backup) + G5 (Staging)
Day 5: G6 (Rollback tests)
```

### Week 4: IaC Foundation
```
Day 1-3: I1 (Terraform) + I2 (Ansible)
Day 4-5: I3 (DR docs) + R1 (Fallback LLM)
```

---

## 📈 Metrics & KPIs

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| Deployment frequency | On-demand | Daily | 🔄 |
| Lead time for changes | 10 min | 5 min | 🔄 |
| Mean time to recovery | 15 min | 5 min | 📋 |
| Change failure rate | 5% | <2% | 🔄 |
| Monitoring coverage | 30% | 90% | 📋 |
| Test coverage | 0% | 70% | 📋 |

---

## 🔗 Related Documents

- [PENDING-CHANGES.md](./PENDING-CHANGES.md) - Manual changes log
- [LESSONS-LEARNED.md](./LESSONS-LEARNED.md) - Incident analysis
- [SESSION_SUMMARY.md](../SESSION_SUMMARY.md) - Session context
- [deploy.yml](../.github/workflows/deploy.yml) - CI/CD pipeline

---

## 📝 Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Completed |
| 🔄 | In Progress |
| 📋 | Pending/Planned |
| 🔴 | Blocked |
| ⏳ | Waiting |

---

*Generated: 2026-02-27 | Source: Beads + AI Analysis*
