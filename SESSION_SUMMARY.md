# Session Summary: Moltinger Project

> **⚠️ ОБЯЗАТЕЛЬНОЕ ЧТЕНИЕ** в начале каждой сессии!
> Обновляется после каждой значимой сессии. Последнее обновление: 2026-02-28

---

## 🎯 Project Overview

**Проект**: Moltinger - AI Agent Factory на базе Moltis (OpenClaw)
**Миссия**: Создание AI агентов по методологии ASC AI Fabrique с самообучением
**Репозиторий**: https://github.com/RussianLioN/moltinger
**Ветка**: `main`
**Issue Tracker**: Beads (prefix: `molt`)

### Технологический стек

| Компонент | Технология |
|-----------|------------|
| **Container** | Docker Compose |
| **AI Assistant** | Moltis (ghcr.io/moltis-org/moltis:latest) |
| **Telegram Bot** | @moltinger_bot |
| **LLM Provider** | GLM-5 (Zhipu AI) via api.z.ai |
| **LLM Fallback** | Ollama Sidecar + Gemini-3-flash-preview:cloud |
| **CI/CD** | GitHub Actions |
| **Issue Tracking** | Beads |

---

## 📊 Current Status

### Production Status

```
Server: ainetic.tech
Moltis: Running ✅
URL: https://moltis.ainetic.tech
Telegram Bot: @moltinger_bot ✅
LLM Provider: zai (GLM-5) ✅
LLM Fallback: Ollama Sidecar ✅ (configured, ready to deploy)
Circuit Breaker: Configured ✅
CI/CD: Working ✅
GitOps Compliance: Enforced ✅
```

### Версия

**Current Release**: v1.8.0
**Feature Complete**: 001-docker-deploy-improvements (2026-03-01)

---

## 📁 Key Files

### Конфигурация

| Файл | Назначение |
|------|------------|
| `config/moltis.toml` | Основная конфигурация Moltis |
| `docker-compose.prod.yml` | Docker Compose для продакшена |
| `.github/workflows/deploy.yml` | CI/CD пайплайн с GitOps compliance |
| `.claude/settings.json` | Sandbox и permissions конфигурация |

### GitOps Infrastructure (новое 2026-02-28)

| Файл | Назначение |
|------|------------|
| `.github/workflows/gitops-drift-detection.yml` | Cron drift detection (каждые 6ч) |
| `.github/workflows/gitops-metrics.yml` | SLO metrics collection (каждый час) |
| `.github/workflows/uat-gate.yml` | UAT promotion gate |
| `scripts/gitops-guards.sh` | Guard functions library |
| `scripts/scripts-verify.sh` | Manifest validator |
| `scripts/gitops-metrics.sh` | Metrics collector |
| `scripts/manifest.json` | IaC manifest для scripts |

### Самообучение

| Файл | Назначение |
|------|------------|
| `docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md` | Инструкция для LLM (1360 строк) |
| `docs/research/openclaw-moltis-research.md` | Исследование OpenClaw/Moltis |
| `docs/QUICK-REFERENCE.md` | Быстрая справка (@moltinger_bot и др.) |
| `skills/telegram-learner/SKILL.md` | Skill для мониторинга Telegram |
| `knowledge/` | База знаний (concepts, tutorials, etc.) |

### Планирование

| Файл | Назначение |
|------|------------|
| `docs/plans/parallel-doodling-coral.md` | План трансформации в AI Agent Factory |
| `docs/plans/agent-factory-lifecycle.md` | Полный lifecycle создания агента |
| `docs/LESSONS-LEARNED.md` | Инциденты и уроки |

---

## 🔄 GitHub Secrets

| Secret | Status | Purpose |
|--------|--------|---------|
| `TELEGRAM_BOT_TOKEN` | ✅ | Bot token (@moltinger_bot) |
| `TELEGRAM_ALLOWED_USERS` | ✅ | Allowed user IDs |
| `GLM_API_KEY` | ✅ | LLM API (Zhipu AI) |
| `OLLAMA_API_KEY` | ⚠️ | Ollama Cloud (optional - for cloud models) |
| `SSH_PRIVATE_KEY` | ✅ | Deploy key |
| `MOLTIS_PASSWORD` | ✅ | Auth password |
| `TAVILY_API_KEY` | ✅ | Web search |

---

## 📝 Session History

### 2026-03-01 (продолжение): Fallback LLM with Ollama Sidecar (001-fallback-llm-ollama)

**Завершено**:

#### Consilium Architecture Discussion
- ✅ Запущен консилиум 19 экспертов для обсуждения архитектуры failover
- ✅ Рекомендован вариант: Ollama Sidecar + Circuit Breaker
- ✅ Анализ 5 вариантов развёртывания

#### Speckit Workflow Complete
- ✅ `/speckit.specify` — spec.md с 3 user stories
- ✅ `/speckit.plan` — plan.md, research.md, data-model.md, contracts/
- ✅ `/speckit.tasks` — 32 задачи в 7 фазах
- ✅ `/speckit.tobeads` — Epic moltinger-39q в Beads

#### Implementation (Phase 1-5 Complete)
- ✅ **Phase 1: Setup** — Ollama sidecar в docker-compose.prod.yml (4 CPUs, 8GB RAM)
- ✅ **Phase 2: Foundational** — moltis.toml failover config (GLM → Ollama → Gemini)
- ✅ **Phase 3: US1 MVP** — Circuit Breaker state machine (CLOSED → OPEN → HALF-OPEN)
- ✅ **Phase 4: US2** — Prometheus metrics (llm_provider_available, moltis_circuit_state)
- ✅ **Phase 5: US3** — CI/CD validation (preflight checks, smoke tests)

#### Files Created/Modified
- `docker-compose.prod.yml` — Ollama service + ollama-data volume + ollama_api_key secret
- `config/moltis.toml` — ollama provider enabled + failover chain configured
- `scripts/ollama-health.sh` — Ollama health check script
- `scripts/health-monitor.sh` — Circuit breaker + Prometheus metrics
- `config/prometheus/alert-rules.yml` — LLM failover alerts
- `config/alertmanager/alertmanager.yml` — Alert routing for failover
- `scripts/preflight-check.sh` — Ollama config validation
- `.github/workflows/deploy.yml` — CI/CD validation steps
- `.gitignore` — Explicit ollama_api_key.txt entry

#### Key Technical Decisions
- **Circuit Breaker**: 3 failures → OPEN state → 5 min recovery timeout
- **State File**: `/tmp/moltis-llm-state.json` with flock locking
- **Metrics**: Prometheus textfile exporter for node_exporter
- **Failover Chain**: GLM-5 (Z.ai) → Ollama Gemini → Google Gemini

**Коммиты сессии**:
- `98ec7ba` — feat(fallback-llm): add Ollama sidecar and configure failover
- `5dc8f0b` — feat(fallback-llm): add Ollama health check script (T009)
- `fd06e46` — feat(fallback-llm): add GLM/Ollama health checks (T010)
- `c1b2be5` — feat(fallback-llm): implement circuit breaker state machine (T011-T015)
- `68c6dbb` — feat(fallback-llm): add Prometheus metrics export (T016-T019)
- `cf65a93` — feat(fallback-llm): add Prometheus alerts and AlertManager config (T020-T021)
- `5ee89c2` — feat(fallback-llm): add Ollama validation to preflight (T022-T023)
- `19505b9` — feat(fallback-llm): add CI/CD validation for failover (T024-T026)
- `e4d02b8` — docs(fallback-llm): update SESSION_SUMMARY and .gitignore (T027, T030)
- `88f59df` — docs(fallback-llm): complete Phase 6 - documentation and close epic (T028-T032)

**Feature Complete**: Все 32 задачи выполнены, готово к деплою.
**Beads Epic**: moltinger-39q закрыт

---

### 2026-03-01: Docker Deployment Improvements - Feature Complete

**Завершено**:

#### Epic moltinger-6ys Closed
- ✅ Все 10 фаз реализованы
- ✅ Phase 0: Planning - executors assigned
- ✅ Phase 1: Setup - directories created
- ✅ Phase 2: Foundational - YAML anchors, compose validation
- ✅ Phase 3 (US1): Automated Backup - systemd timer, S3 support, JSON output
- ✅ Phase 4 (US2): Secrets Management - Docker secrets, preflight validation
- ✅ Phase 5 (US3): Reproducible Deployments - pinned versions
- ✅ Phase 6 (US4): GitOps Compliance - no sed, full file sync
- ✅ Phase 7 (US5-US7): P2 Enhancements - JSON output, unified config
- ✅ Phase 8: Polish - docs, alerts, quickstart

**Коммиты сессии**:
- `789fba8` — chore(beads): close Docker Deployment Improvements epic

**Оставшиеся задачи (P4 Backlog)**:
- moltinger-xh7: Fallback LLM provider (CRITICAL)
- moltinger-sjx: S3 Offsite Backup
- moltinger-r8r: Traefik Rate Limiting
- moltinger-j22: AlertManager Receivers
- moltinger-eb0: Grafana Dashboard

---

### 2026-02-28: GitOps Compliance Framework (P0/P1/P2)

**Завершено**:

#### P0 - Критические (Incident #002)
- ✅ Добавлен ssh/scp в ASK list настроек
- ✅ Добавлено SSH/SCP Blocking Rule в CLAUDE.md
- ✅ Добавлен scripts/ sync в deploy.yml

#### P1 - Высокий приоритет
- ✅ **GitOps compliance test в CI** — job `gitops-compliance` сравнивает хеши git ↔ server
- ✅ **Drift detection cron job** — `gitops-drift-detection.yml` каждые 6 часов
- ✅ **Guards в серверные скрипты** — `gitops-guards.sh` библиотека

#### P2 - Средний приоритет
- ✅ **IaC подход для scripts** — `manifest.json` + `scripts-verify.sh`
- ✅ **GitOps SLO и метрики** — `gitops-metrics.yml` + `gitops-metrics.sh`
- ✅ **UAT gate с GitOps checks** — `uat-gate.yml` с 5 gate'ами

#### Sandbox improvements
- ✅ Уточнён deny list: `.env.example` разрешён, реальные секреты заблокированы
- ✅ Разрешены `git push` и `ssh` для автоматизации
- ✅ Добавлен `~/.beads` в write allow list

**Коммиты сессии**:
- `fddfc17` — feat(ci): add GitOps compliance check job (P1-1)
- `dac5a33` — feat(ci): add GitOps drift detection cron job (P1-2)
- `688efee` — feat(scripts): add GitOps guards (P1-3)
- `70b24d5` — feat(iac): add manifest-based scripts management (P2-4)
- `61cd539` — feat(metrics): add GitOps SLO and metrics collection (P2-5)
- `62a08ac` — feat(uat): add UAT gate with GitOps checks (P2-6)
- `b8c9bc4` — chore: update Claude Code config and agents
- `83cff41` — fix(sandbox): add ~/.beads to write allow list

**В работе**:
- ✅ Bug health check завершён — все найденные баги исправлены

**Нерешённые**:
- ❌ Moltis API аутентификация для автоматического тестирования Telegram бота

---

### 2026-02-28 (продолжение 2): Session Automation Framework

**Завершено**:

#### Consilium: Session State Persistence
- ✅ Запущен консилиум 6 экспертов для анализа session state automation
- ✅ Эксперты единогласно рекомендовали Hook-Based Auto-Save
- ✅ GitOps Specialist: Issues ≠ Files (git = source of truth)

#### Session Automation Implementation
- ✅ **Stop Hook** — `.claude/hooks/session-save.sh` (auto-backup)
- ✅ **Issues Mirror** — `.claude/hooks/session-issues-mirror.sh` (visibility)
- ✅ **Pre-Commit** — `.githooks/pre-commit` (incremental logging)
- ✅ **Setup Script** — `scripts/setup-git-hooks.sh` (git config)

#### Bug Fix
- ✅ Исправлен `SESSION_STATE.md` → `SESSION_SUMMARY.md` во всех hook-скриптах

**Коммиты сессии**:
- `7246333` — feat(ci): add scripts/ to GitOps sync (from 001-docker-deploy-improvements)
- `f8dab74` — feat(session): complete session automation framework
- `9d89adb` — fix(hooks): use correct SESSION_SUMMARY.md filename
- `23c40f4` — chore(release): v1.8.0

**Release v1.8.0**: 33 commits (17 features,7 bug fixes, 9 other changes)

---

### 2026-02-28 (продолжение): P4 Tasks

**Завершено**:

#### P4 - Backlog tasks
- ✅ **moltinger-hdn** — Backup verification cron (еженедельная проверка integrity)
- ✅ **moltinger-kpt** — Pre-deployment tests (shellcheck, yamllint, compose validation)
- ✅ **moltinger-eml** — Replace sed -i with MOLTIS_VERSION env var (GitOps compliant)
- ✅ **moltinger-wisp-u7e** — Healthcheck epic закрыт (все баги исправлены)

**Новые файлы**:
- `scripts/cron.d/moltis-backup-verify` — Cron конфигурация

**Изменения в CI/CD**:
- Добавлен `test` job в deploy.yml (shellcheck, yamllint, docker-compose validation)
- Deploy теперь зависит от успешного прохождения тестов
- Добавлен шаг установки cron jobs из scripts/cron.d/

**Коммит**:
- `2aaa763` — feat(ci): add pre-deployment tests and backup verification cron

---

### 2026-02-18/19: AI Agent Factory Transformation

**Завершено**:
- ✅ Исследование OpenClaw/Moltis (1200 строк)
- ✅ Создана инструкция для самообучения LLM (1360 строк)
- ✅ Создан skill `telegram-learner` для мониторинга @tsingular
- ✅ Создана структура knowledge base
- ✅ Обновлена конфигурация moltis.toml (search_paths, auto_load)
- ✅ Деплой на сервер (commit 022ea93)

---

## 🔗 Quick Links

- **Telegram Bot**: @moltinger_bot
- **Web UI**: https://moltis.ainetic.tech
- **Инструкция для LLM**: docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md
- **Быстрая справка**: docs/QUICK-REFERENCE.md
- **GitOps Lessons**: docs/LESSONS-LEARNED.md

---

## 📞 Commands Reference

```bash
# Deploy
git add . && git commit -m "message" && git push

# Check CI/CD
gh run list --repo RussianLioN/moltinger --limit 3

# SSH to server
ssh root@ainetic.tech
docker logs moltis -f

# Health check
curl -I https://moltis.ainetic.tech/health

# Beads
bd ready              # Find available work
bd prime              # Restore context
bd doctor             # Health check

# GitOps
scripts/gitops-metrics.sh json    # Collect metrics
scripts/scripts-verify.sh         # Validate scripts
```

---

## 🎯 Next Steps

1. **P4 Backlog** — 8 задач готовы к работе (см. `bd ready`)
2. **Deploy Fallback LLM** — `git push` + `docker compose up -d`
3. **moltinger-sjx** — HIGH: S3 Offsite Backup
4. Протестировать skill telegram-learner на канале @tsingular
5. Создать навык самообновления инструкции

### P4 Priority Tasks (Recommended Order)

| # | Task | Priority | Why |
|---|------|----------|-----|
| 1 | ~~`moltinger-xh7`~~ | ~~CRITICAL~~ | ✅ DONE: Fallback LLM with Ollama Sidecar |
| 2 | `moltinger-sjx` | HIGH | S3 Offsite Backup - disaster recovery |
| 3 | `moltinger-r8r` | MEDIUM | Traefik Rate Limiting - защита от abuse |
| 4 | `moltinger-j22` | MEDIUM | AlertManager Receivers - уведомления |
| 5 | `moltinger-eb0` | MEDIUM | Grafana Dashboard - визуализация |

> Детали в: `docs/P4-BACKLOG-PRIORITIES.md`

---

## 🏗️ GitOps Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    UAT GATE                                 │
│  Pre-flight → GitOps Check → Smoke Tests → Approval → Deploy│
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                 CI/CD PIPELINE (Updated 2026-02-28)         │
│  gitops-compliance → preflight → test → backup → deploy    │
│                              ↑                              │
│                    Deploy blocked on test failure           │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              SCHEDULED WORKFLOWS                            │
│  • Drift Detection (каждые 6ч) → Issue on drift            │
│  • Metrics Collection (каждый час) → SLO tracking          │
│  • Backup Verification (каждое воскресенье 03:00 MSK)      │
└─────────────────────────────────────────────────────────────┘
```

**SLOs**:
- Compliance Rate: ≥95%
- Deployment Success: ≥99%
- Drift Detection SLA: 6 hours
- Backup Verification: Weekly

---

*Last updated: 2026-03-01 | Session: Fallback LLM with Ollama Sidecar*
