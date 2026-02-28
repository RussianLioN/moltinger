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
CI/CD: Working ✅
GitOps Compliance: Enforced ✅
```

### Версия

**Current Release**: v1.7.0

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
| `SSH_PRIVATE_KEY` | ✅ | Deploy key |
| `MOLTIS_PASSWORD` | ✅ | Auth password |
| `TAVILY_API_KEY` | ✅ | Web search |

---

## 📝 Session History

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
- 🔄 Bug health check (`/health-bugs`) — wisp: `moltinger-wisp-u7e`

**Нерешённые**:
- ❌ Moltis API аутентификация для автоматического тестирования Telegram бота

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

1. ~~Решить вопрос безопасного взаимодействия с Telegram~~ → GitOps framework готов
2. **Moltis API аутентификация** — исследовать WebSocket API или Traefik конфигурацию
3. Протестировать skill telegram-learner на канале @tsingular
4. Создать навык самообновления инструкции

---

## 🏗️ GitOps Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    UAT GATE                                 │
│  Pre-flight → GitOps Check → Smoke Tests → Approval → Deploy│
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                 CI/CD PIPELINE                              │
│  gitops-compliance → backup → deploy → verify              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              SCHEDULED WORKFLOWS                            │
│  • Drift Detection (каждые 6ч) → Issue on drift            │
│  • Metrics Collection (каждый час) → SLO tracking          │
└─────────────────────────────────────────────────────────────┘
```

**SLOs**:
- Compliance Rate: ≥95%
- Deployment Success: ≥99%
- Drift Detection SLA: 6 hours

---

*Last updated: 2026-02-28 | Session: GitOps Compliance Framework*
