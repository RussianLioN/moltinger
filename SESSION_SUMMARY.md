# Session Summary: Moltinger Project

> **⚠️ ОБЯЗАТЕЛЬНОЕ ЧТЕНИЕ** в начале каждой сессии!
> Обновляется после каждой значимой сессии. Последнее обновление: 2026-03-03

---

## 🎯 Project Overview

**Проект**: Moltinger - AI Agent Factory на базе Moltis (OpenClaw)
**Миссия**: Создание AI агентов по методологии ASC AI Fabrique с самообучения
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
CI/CD: Working ✅ (with test suite)
Test Suite: Integrated ✅ (unit/integration/security/e2e)
GitOps Compliance: Enforced ✅
```

### Версия

**Current Release**: v1.8.0
**Feature Complete**: 001-docker-deploy-improvements (2026-03-02)
**Test Suite**: Added comprehensive CI/CD test integration

---

## 📁 Key Files

### Конфигурация

| Файл | Назначение |
|------|------------|
| `config/moltis.toml` | Основная конфигурация Moltis |
| `docker-compose.prod.yml` | Docker Compose для продакшена |
| `.github/workflows/deploy.yml` | CI/CD пайплайнс GitOps compliance |
| `.github/workflows/test.yml` | Test suite CI/CD workflow (новое!) |
| `.claude/settings.json` | Sandbox и permissions конфигурация |

### GitOps Infrastructure (новое 2026-02-28)

| Файл | Назначение |
|------|------------|
| `.github/workflows/gitops-drift-detection.yml` | Cron drift detection (каждые 6h) |
| `.github/workflows/gitops-metrics.yml` | SLO metrics collection (каждый час) |
| `.github/workflows/uat-gate.yml` | UAT promotion gate |
| `scripts/gitops-guards.sh` | Guard functions library |
| `scripts/scripts-verify.sh` | Manifest validator |
| `scripts/gitops-metrics.sh` | Metrics collector |
| `scripts/manifest.json` | IaC manifest для scripts |

### Test Suite (новое 2026-03-02)

| Файл | Назначение |
|------|------------|
| `tests/run_unit.sh` | Unit test runner |
| `tests/run_integration.sh` | Integration test runner |
| `tests/run_e2e.sh` | E2E test runner |
| `tests/run_security.sh` | Security test runner |
| `tests/lib/test_helpers.sh` | Test helper functions |
| `tests/unit/` | Unit tests (circuit breaker, config, metrics) |
| `tests/integration/` | Integration tests (API, failover, MCP, Telegram) |
| `tests/e2e/` | E2E tests (chat flow, recovery, failover chain) |
| `tests/security/` | Security tests (auth, input validation) |

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
| `docs/plans/agent-factory-lifecycle.md` | Полный lifecycle создания агентов|
| `docs/LESSONS-LEARNED.md` | Инциденты и уроки |

---

## 🔄 GitHub Secrets

| Secret | Status | Purpose |
|--------|--------|---------|
| `TELEGRAM_BOT_TOKEN` | ✅ | Bot token (@moltinger_bot) |
| `TELEGRAM_ALLOWED_USERS` | ✅ | Allowed user IDs |
| `GLM_API_KEY` | ✅ | LLMAPI (Zhipu AI) |
| `OLLAMA_API_KEY` | ✅ | Ollama Cloud (optional - for cloud models) |
| `SSH_PRIVATE_KEY` | ✅ | Deploy key |
| `MOLTIS_PASSWORD` | ✅ | Auth password |
| `TAVILY_API_KEY` | ✅ | Web search |

---

## 📝 Session History

### 2026-03-03: Testing Technical Debt Analysis (Today's Session)

**Статус**: Завершён ✅

#### Анализ Fallback LLM Testing
- ✅ Проверена ветка `001-fallback-llm-ollama` — слита в main
- ✅ Найдена ветка `003-testing-infrastructure` — 1 неслитый коммит (spec)
- ✅ Проанализиров spec `specs/003-testing-infrastructure/` — 56 задач
- ✅ Проверены существующие тесты в `tests/`
- ✅ Найдены баг: `PROJECT_ROOT` в `test_llm_failover.sh`
- ✅ Найдены проблемы с CI/CD интеграцией тестов

#### Проблемы найдены
1. **Баг в пути**: `tests/integration/test_llm_failover.sh:38` — неверный расчёт `PROJECT_ROOT`
2. **CI/CD НЕ запускает тесты**: `deploy.yml` делает только shellcheck/yamllint
3. **Задачи в Beads не закрыты**: ~35 дочерних задач `moltinger-39q` открыты

#### Созданы задачи в Beads
- ✅ **moltinger-esr** — Epic: Testing Technical Debt - Fallback LLM (P1)
- ✅ **moltinger-3y9** — Phase A: Fix Critical Bugs (P1)
- ✅ **moltinger-5vz** — Phase B: CI/CD Integration (P1)
- ✅ **moltinger-76t** — Phase C: Test Coverage (P2)
- ✅ **moltinger-cb2** — Phase D: Documentation (P3)

#### Обновлённые файлы
- ✅ `docs/P4-BACKLOG-PRIORITIES.md` — добавлена секция Testing Technical Debt

#### Git Operations
- ✅ `git add` → commit → push` → всё чист

---

## 🏗️ Next Steps

1. **Работать над Phase A** → исправить баги в тестах (moltinger-3y9)
2. **Работать над Phase B** → интегрировать тесты в CI/CD (moltinger-5vz)
3. **Работать над Phase C** → покрыть тестами fallback LLM (moltinger-76t)
4. **Работать над Phase D** → документация (moltinger-cb2)
