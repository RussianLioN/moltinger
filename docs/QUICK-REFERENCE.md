# Moltinger: Quick Reference

**⚠️ ЧИТАТЬ В НАЧАЛЕ КАЖДОЙ СЕССИИ!**

---

## Ключевые артефакты

| Артефакт | Расположение | Назначение |
|----------|--------------|------------|
| **Telegram Bot** | @moltinger_bot | Основной способ взаимодействия |
| **Web UI** | https://moltis.ainetic.tech | Веб-интерфейс |
| **SESSION_SUMMARY.md** | /SESSION_SUMMARY.md | Статус проекта |
| **Инструкция для LLM** | docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md | Самообучение Moltis |
| **Git Topology Registry** | docs/GIT-TOPOLOGY-REGISTRY.md | Актуальные worktree, ветки и cleanup-контекст |

---

## Telegram Integration

```
Bot Username: @moltinger_bot
Status: ✅ WORKING
Token: GitHub Secret (TELEGRAM_BOT_TOKEN)
Allowed Users: GitHub Secret (TELEGRAM_ALLOWED_USERS)
```

### Как отправить сообщение боту

**Вариант 1: Через Telegram клиент**
- Найти @moltinger_bot
- Написать сообщение

**Вариант 2: Через API (для тестирования)**
```bash
TOKEN=$(gh secret get TELEGRAM_BOT_TOKEN)
curl -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d "chat_id=YOUR_CHAT_ID" \
  -d "text=Test message"
```

---

## Skills System

| Skill | Расположение | Назначение |
|-------|--------------|------------|
| telegram-learner | skills/telegram-learner/ | Мониторинг Telegram и извлечение знаний |

### Активные skills (auto_load)
- telegram-learner

---

## Knowledge Base

```
knowledge/
├── concepts/        # Концепции
├── tutorials/       # Туториалы
├── references/      # Справочники
├── troubleshooting/ # Решение проблем
└── patterns/        # Паттерны
```

---

## Deployment (GitOps)

```bash
# Deploy
git add . && git commit -m "message" && git push

# Manual check
make status

# Logs
make logs LOGS_OPTS=-f
```

---

## Secrets (GitHub Secrets)

| Secret | Status | Purpose |
|--------|--------|---------|
| TELEGRAM_BOT_TOKEN | ✅ | Bot token |
| TELEGRAM_ALLOWED_USERS | ✅ | Allowed user IDs |
| GLM_API_KEY | ✅ | LLM API + AI workflows |
| SSH_PRIVATE_KEY | ✅ | Deploy |

Workflow variable:
- `AI_REVIEW_PROVIDER` (`zai` by default, `off` for emergency fallback-only mode)

---

## Текущие задачи

| # | Задача | Статус |
|---|--------|--------|
| 18 | Phase 4: Verification & Deploy | ⏳ pending |
| 20 | Навык самообновления инструкции | 📋 backlog |

---

*Last updated: 2026-03-08*
