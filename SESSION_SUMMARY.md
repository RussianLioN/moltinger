# Session Summary: Moltinger Project

> **⚠️ ОБЯЗАТЕЛЬНОЕ ЧТЕНИЕ** в начале каждой сессии!
> Обновляется после каждой значимой сессии. Последнее обновление: 2026-02-16

---

## 🎯 Project Overview

**Проект**: Moltinger - AI-ассистент Moltis в Docker на сервере ainetic.tech
**Репозиторий**: https://github.com/RussianLioN/moltinger
**Ветка**: `main`
**Issue Tracker**: Beads (prefix: `molt`)

### Технологический стек

| Компонент | Технология |
|-----------|------------|
| **Container** | Docker Compose |
| **AI Assistant** | Moltis (ghcr.io/moltis-org/moltis:latest) |
| **Reverse Proxy** | Traefik (существующий на сервере) |
| **LLM Provider** | GLM (Zhipu AI) via api.z.ai |
| **Auto-updates** | Watchtower |
| **CI/CD** | GitHub Actions |
| **Network** | ainetic_net (shared with n8n, Traefik) |

---

## 📊 Current Status

### Production Endpoints

| Сервис | URL | Статус |
|--------|-----|--------|
| **Moltis** | https://ainetic.tech/moltis | ✅ Работает |
| **n8n** | https://ainetic.tech | ✅ Работает (восстановлен) |
| **Health** | https://ainetic.tech/moltis/health | ✅ HTTP 200 |

### Git Status

```
Branch: main
Remote: up to date with origin
Recent Commits:
- c108e08 fix(traefik): move Moltis to /moltis path to restore n8n
- d3dac5f docs: update SESSION_SUMMARY - GitOps 2.0 complete
- 982c8cd fix(ci): make root path test non-blocking in smoke tests
```

### Container Status

```
Moltis: v0.8.35, healthy, on ainetic_net
Watchtower: Running, auto-updates enabled
Network: ainetic_net (shared with Traefik, n8n)
```

---

## 📁 Key Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Simple deployment config |
| `docker-compose.prod.yml` | Production config with monitoring |
| `.github/workflows/deploy.yml` | CI/CD pipeline |
| `config/moltis.toml` | Moltis configuration (GLM provider) |
| `scripts/deploy.sh` | Deployment automation |

---

## 🚀 User Testing Plan

### Шаг 1: Проверка Moltis (5 минут)

1. Открыть https://ainetic.tech/moltis
2. Авторизоваться с паролем: `aWaH8G8ReQtoE969BNpe5sR5Ky8c0s`
3. Создать новую сессию
4. Отправить тестовое сообщение
5. Проверить что GLM отвечает

### Шаг 2: Проверка n8n (2 минуты)

1. Открыть https://ainetic.tech
2. Убедиться что n8n интерфейс загружается
3. Проверить существующие workflows работают

### Шаг 3: Проверка Health Endpoint (1 минута)

```bash
curl -s https://ainetic.tech/moltis/health
# Ожидается: {"status":"ok","version":"0.8.35",...}
```

---

## 📋 Backlog Items

| ID | Название | Приоритет | Статус |
|----|----------|-----------|--------|
| 002 | Moltis + n8n Integration | Low | Backlog |

---

## 🔧 Recent Fixes

### 2026-02-16: Traefik Routing Fix

**Проблема**: Moltis захватил корневой путь ainetic.tech, сломав n8n

**Решение**:
- Переместил Moltis на `/moltis` path prefix
- Добавил stripprefix middleware
- Подключил к ainetic_net (общая сеть с Traefik)
- Установил priority=100 (выше чем у n8n)

**Commit**: `c108e08 fix(traefik): move Moltis to /moltis path to restore n8n`

---

## ⚠️ Important Notes

### Traefik Configuration

```
Moltis Router:
- Rule: Host(`ainetic.tech`) && PathPrefix(`/moltis`)
- Priority: 100
- Middleware: moltis-stripprefix (removes /moltis prefix)

n8n Router:
- Rule: Host(`ainetic.tech`)
- Priority: 10
```

### Network Architecture

```
ainetic_net (172.18.0.x)
├── Traefik (reverse proxy)
├── n8n (workflow automation)
├── Moltis (AI assistant) ← /moltis path
├── Grafana
├── Prometheus
└── ... other services
```

---

## 📞 Commands Reference

```bash
# Check Moltis health
curl -s https://ainetic.tech/moltis/health

# SSH to server
ssh root@ainetic.tech

# View logs
docker logs moltis -f

# Restart Moltis
cd /opt/moltinger && docker compose restart moltis

# Trigger CI/CD manually
gh workflow run deploy.yml
```

---

*Last updated: 2026-02-16 | Session: Traefik Routing Fix*
