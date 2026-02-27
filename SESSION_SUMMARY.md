# Session Summary: Moltinger Project

> **⚠️ ОБЯЗАТЕЛЬНОЕ ЧТЕНИЕ** в начале каждой сессии!
> Обновляется после каждой значимой сессии. Последнее обновление: 2026-02-19

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
```

### Стратегический Pivot (2026-02-18/19)

**Новая миссия**: Moltinger → AI Agent Factory
- Создание агентов по методологии ASC (7 метаблоков, 3 фазы, 62 термина)
- Самообучение через мониторинг Telegram @tsingular
- Генерация спецификаций, архитектур, презентаций

---

## 📁 Key Files

### Конфигурация

| Файл | Назначение |
|------|------------|
| `config/moltis.toml` | Основная конфигурация Moltis |
| `docker-compose.prod.yml` | Docker Compose для продакшена |
| `.github/workflows/deploy.yml` | CI/CD пайплайн |

### Самообучение (новое)

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

### 2026-02-18/19: AI Agent Factory Transformation

**Завершено**:
- ✅ Исследование OpenClaw/Moltis (1200 строк)
- ✅ Создана инструкция для самообучения LLM (1360 строк)
- ✅ Создан skill `telegram-learner` для мониторинга @tsingular
- ✅ Создана структура knowledge base
- ✅ Обновлена конфигурация moltis.toml (search_paths, auto_load)
- ✅ Деплой на сервер (commit 022ea93)

**В работе**:
- ⏳ Тестирование Telegram Webhook (@moltinger_bot)
- ⏳ Извлечение первого знания из @tsingular

**Бэклог**:
- 📋 Навык самообновления инструкции (Task #20)

---

## 🔗 Quick Links

- **Telegram Bot**: @moltinger_bot
- **Web UI**: https://moltis.ainetic.tech
- **Инструкция для LLM**: docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md
- **Быстрая справка**: docs/QUICK-REFERENCE.md

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
```

---

## 🎯 Next Steps

1. Решить вопрос безопасного взаимодействия с Telegram без раскрытия API ключей
2. Протестировать skill telegram-learner на канале @tsingular
3. Создать навык самообновления инструкции

---

*Last updated: 2026-02-19 | Session: AI Agent Factory Transformation*
