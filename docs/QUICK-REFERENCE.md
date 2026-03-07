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

### Постоянный мониторинг webhook/качества ответов

```bash
# Одноразовый запуск (JSON отчёт)
./scripts/telegram-webhook-monitor.sh --json

# Server-side cron (GitOps): scripts/cron.d/moltis-telegram-webhook-monitor
# CI schedule: .github/workflows/telegram-webhook-monitor.yml
```

### Standalone Telegram CLI (без Moltis)

```bash
# User-level UAT probe (главный режим)
./scripts/telegram-user-monitor.sh --env-file .env

# Альтернатива без API_HASH: Telegram Web
./scripts/setup-telegram-web-user-monitor.sh --project-dir /opt/moltinger
node scripts/telegram-web-user-login.mjs --state /opt/moltinger/data/.telegram-web-state.json
TELEGRAM_WEB_PROBE_PROFILE=echo_ping TELEGRAM_WEB_MESSAGE=test2 ./scripts/telegram-web-user-monitor.sh

# Primary scheduler (systemd timer)
systemctl enable --now moltis-telegram-web-user-monitor.timer

# Поднять webhook endpoint (Traefik + echo)
./scripts/setup-telegram-webhook-echo.sh --domain moltis.ainetic.tech --path /telegram-webhook

# Управление webhook напрямую через Bot API
./scripts/telegram-webhook-control.sh webhook-info
./scripts/telegram-webhook-control.sh webhook-set --url "https://YOUR_DOMAIN/HOOK"

# Отправка как бот
./scripts/telegram-bot-send.sh --chat-id 262872984 --text "/status"

# Отправка как пользователь (MTProto)
./scripts/telegram-user-send.py --to @some_bot --text "/start"
```

Подробно: `docs/TELEGRAM-WEBHOOK-CLI.md`
User-monitor: `docs/TELEGRAM-USER-MONITOR.md`
No-API_HASH monitor: `docs/TELEGRAM-WEB-USER-MONITOR.md`
Clean deploy runbook: `docs/CLEAN-DEPLOY-TELEGRAM-WEB-USER-MONITOR.md`

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
| GLM_API_KEY | ✅ | LLM API |
| SSH_PRIVATE_KEY | ✅ | Deploy |

---

## Текущие задачи

| # | Задача | Статус |
|---|--------|--------|
| 18 | Phase 4: Verification & Deploy | ⏳ pending |
| 20 | Навык самообновления инструкции | 📋 backlog |

---

*Last updated: 2026-03-06*
