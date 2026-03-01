# План клонирования Moltinger → OpenClaw проект

**Дата**: 2026-03-01
**Статус**: Планирование

---

## 1. Цель проекта

Создать **новый проект** на базе OpenClaw (TypeScript) для развертывания **семейного универсального ассистента** на сервере ainetic.tech.

### Ключевые отличия от Moltinger:

| Аспект | Moltinger (текущий) | Новый проект (OpenClaw) |
|--------|---------------------|-------------------------|
| **Движок** | Moltis (Rust) | OpenClaw (TypeScript/Node.js) |
| **Config** | TOML (`moltis.toml`) | JSON (`openclaw.json`) |
| **Порт** | 13131 | 18789 |
| **Runtime** | Single binary (44MB) | Node.js 22+ |
| **Цель** | DevOps-ассистент | Семейный универсальный ассистент |
| **Пользователи** | Один разработчик | Многопользовательский (семья) |

---

## 2. Название проекта

**Предлагаемые варианты:**

| # | Название | Описание | Домен |
|---|----------|----------|-------|
| 1 | **kruzh-claw** | "Кружок" - семейный круг + claw | `kruzh-claw.ainetic.tech` |
| 2 | **family-claw** | Прямое указание на семейность | `family-claw.ainetic.tech` |
| 3 | **nest-claw** | "Гнездо" - уютный семейный дом | `nest-claw.ainetic.tech` |
| 4 | **hive-claw** | "Улей" - многопользовательская колония | `hive-claw.ainetic.tech` |
| 5 | **hub-claw** | "Хаб" - центр семейных коммуникаций | `hub-claw.ainetic.tech` |
| 6 | **den-claw** | "Логово" - уютное пространство | `den-claw.ainetic.tech` |

**Рекомендация**: `kruzh-claw` или `nest-claw`

---

## 3. LLM стратегия

### 3.1 Provider Chain

```
┌─────────────────────────────────────────────────────────────┐
│                    LLM FAILOVER CHAIN                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. PRIMARY: Gemini 3 Flash Preview (Google API)           │
│     Provider: google                                        │
│     Model: google/gemini-3-flash-preview                   │
│     Auth: GEMINI_API_KEY                                    │
│     Reason: Быстрый, дешёвый, хороший для семьи            │
│                                                             │
│  2. FALLBACK 1: GLM-4.7 (Z.AI)                             │
│     Provider: zai                                           │
│     Model: zai/glm-4.7                                      │
│     Auth: ZAI_API_KEY                                       │
│     Reason: Надёжный fallback, уже используем              │
│                                                             │
│  3. FALLBACK 2: OpenRouter (модель TBD)                    │
│     Provider: openrouter                                    │
│     Model: openrouter/anthropic/claude-sonnet-4-5          │
│     Auth: OPENROUTER_API_KEY                                │
│     Reason: Universal fallback с множеством моделей        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Конфигурация OpenClaw

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/gemini-3-flash-preview",
        "fallbacks": [
          "zai/glm-4.7",
          "openrouter/anthropic/claude-sonnet-4-5"
        ]
      }
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://localhost:11434"
      },
      "zai": {
        "apiKey": "${ZAI_API_KEY}",
        "baseUrl": "https://api.z.ai/api/coding/paas/v4"
      },
      "openrouter": {
        "apiKey": "${OPENROUTER_API_KEY}",
        "baseUrl": "https://openrouter.ai/api/v1"
      }
    }
  }
}
```

---

## 4. Структура нового проекта

```
kruzh-claw/                           # Новое название проекта
├── docker-compose.yml                # Development config
├── docker-compose.prod.yml           # Production config
├── Dockerfile                        # OpenClaw Docker image
├── .env.example                      # Environment variables template
├── Makefile                          # Команды управления
├── config/
│   └── openclaw.json                 # OpenClaw configuration (JSON!)
├── scripts/
│   ├── deploy.sh                     # Deployment script
│   ├── preflight-check.sh            # Validation before deploy
│   ├── backup-kruzh-claw.sh          # Backup system
│   ├── health-monitor.sh             # Health monitoring
│   └── gitops-guards.sh              # GitOps guards
├── systemd/
│   ├── kruzh-claw-backup.service     # Systemd service
│   └── kruzh-claw-backup.timer       # Systemd timer
├── .github/workflows/
│   ├── deploy.yml                    # Main CI/CD pipeline
│   ├── gitops-drift-detection.yml    # Cron drift detection
│   └── gitops-metrics.yml            # SLO metrics
├── data/                             # Persistent data (gitignored)
├── secrets/                          # Docker secrets (gitignored)
├── docs/
│   ├── QUICK-REFERENCE.md
│   ├── SECRETS-MANAGEMENT.md
│   └── knowledge/
│       └── FAMILY-ASSISTANT-GUIDE.md
├── .gitignore
├── CLAUDE.md                         # Agent instructions
└── README.md                         # Project overview
```

---

## 5. Docker конфигурация

### 5.1 Dockerfile (для OpenClaw)

```dockerfile
# Build stage
FROM node:22-bookworm AS builder

RUN corepack enable
WORKDIR /app

# Cache dependencies
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

# Build
COPY . .
RUN pnpm build

# Runtime stage
FROM node:22-bookworm

RUN addgroup -g 1001 -S openclaw && \
    adduser -S -D -H -u 1001 -s /sbin/nologin -G openclaw openclaw

WORKDIR /app
COPY --from=builder --chown=openclaw:openclaw /app/node_modules ./node_modules
COPY --from=builder --chown=openclaw:openclaw /app/dist ./dist
COPY --from=builder --chown=openclaw:openclaw /app/package.json ./

USER openclaw
EXPOSE 18789

CMD ["node", "dist/index.js"]
```

### 5.2 docker-compose.yml

```yaml
services:
  openclaw:
    build: .
    image: kruzh-claw:latest
    container_name: kruzh-claw
    restart: unless-stopped
    privileged: true  # Для sandbox execution

    networks:
      - traefik_proxy

    ports:
      - "18789:18789"

    volumes:
      - ./config:/home/node/.openclaw
      - ./data:/home/node/.openclaw-data
      - /var/run/docker.sock:/var/run/docker.sock

    environment:
      - NODE_ENV=production
      - GEMINI_API_KEY=${GEMINI_API_KEY}
      - ZAI_API_KEY=${ZAI_API_KEY}
      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
      - TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}

    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.kruzh-claw.rule=Host(`kruzh-claw.ainetic.tech`)"
      - "traefik.http.routers.kruzh-claw.entrypoints=websecure"
      - "traefik.http.routers.kruzh-claw.tls.certresolver=letsencrypt"
      - "traefik.http.services.kruzh-claw.loadbalancer.server.port=18789"

    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:18789/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  traefik_proxy:
    external: true
```

---

## 6. Изоляция от Moltinger

### 6.1 Порты

| Проект | Основной порт | Описание |
|--------|---------------|----------|
| Moltinger | 13131 | Moltis gateway |
| **kruzh-claw** | **18789** | OpenClaw gateway |

### 6.2 Пути на сервере

| Проект | Путь | Volume |
|--------|------|--------|
| Moltinger | `/opt/moltinger` | `moltis-data` |
| **kruzh-claw** | `/opt/kruzh-claw` | `kruzh-claw-data` |

### 6.3 Secrets

| Проект | Секреты |
|--------|---------|
| Moltinger | `moltis_password`, `telegram_bot_token`, `glm_api_key` |
| **kruzh-claw** | `kruzh_claw_password`, `telegram_bot_token_kruzh`, `gemini_api_key`, `zai_api_key`, `openrouter_api_key` |

### 6.4 Домены

| Проект | Домен |
|--------|-------|
| Moltinger | `moltis.ainetic.tech` |
| **kruzh-claw** | `kruzh-claw.ainetic.tech` |

---

## 7. Этапы клонирования

### Phase 1: Подготовка (1-2 часа)
- [ ] Выбрать название проекта
- [ ] Создать GitHub репозиторий
- [ ] Клонировать Moltinger как базу
- [ ] Удалить Moltis-специфичные файлы

### Phase 2: Docker setup (2-3 часа)
- [ ] Создать Dockerfile для OpenClaw
- [ ] Адаптировать docker-compose.yml
- [ ] Настроить Traefik labels
- [ ] Протестировать локально

### Phase 3: Конфигурация (2-3 часа)
- [ ] Создать openclaw.json конфигурацию
- [ ] Настроить LLM провайдеры (Gemini → GLM → OpenRouter)
- [ ] Настроить Telegram бота
- [ ] Настроить многопользовательский режим

### Phase 4: Скрипты и CI/CD (2-3 часа)
- [ ] Адаптировать deploy.sh
- [ ] Адаптировать preflight-check.sh
- [ ] Адаптировать backup скрипты
- [ ] Адаптировать GitHub Actions

### Phase 5: Документация (1-2 часа)
- [ ] Создать README.md
- [ ] Создать CLAUDE.md для нового проекта
- [ ] Создать FAMILY-ASSISTANT-GUIDE.md
- [ ] Обновить .env.example

### Phase 6: Деплой (1-2 часа)
- [ ] Создать secrets на сервере
- [ ] Запустить preflight checks
- [ ] Деплой на ainetic.tech
- [ ] Smoke tests
- [ ] Настроить systemd backup timer

---

## 8. Secrets для создания

```bash
# На сервере ainetic.tech
cd /opt/kruzh-claw/secrets

# Gemini API key (основная модель)
echo "your-gemini-api-key" > gemini_api_key.txt

# Z.AI API key (fallback 1)
echo "your-zai-api-key" > zai_api_key.txt

# OpenRouter API key (fallback 2)
echo "your-openrouter-api-key" > openrouter_api_key.txt

# Telegram bot token (новый бот)
echo "your-telegram-bot-token" > telegram_bot_token.txt

# Password для Control UI
openssl rand -base64 32 > kruzh_claw_password.txt

# Set permissions
chmod 600 *.txt
```

---

## 9. Многопользовательский режим

### 9.1 Telegram конфигурация

```json
{
  "channels": {
    "telegram": {
      "token": "${TELEGRAM_BOT_TOKEN}",
      "allowedUsers": [123456789, 987654321],
      "groups": {
        "*": {
          "requireMention": true
        }
      }
    }
  }
}
```

### 9.2 Agent Identity (семейный ассистент)

```json
{
  "identity": {
    "name": "Кружок",
    "emoji": "🏠",
    "vibe": "friendly",
    "soul": "Ты - Кружок, семейный универсальный ассистент. Помогаешь всем членам семьи с повседневными задачами, учёбой, работой и досугом. Отвечаешь дружелюбно и понятно для всех возрастов."
  }
}
```

---

## 10. Следующие шаги

1. **Выбрать название** - пользователь выбирает из 6 вариантов
2. **Создать GitHub репозиторий** - новый repo для проекта
3. **Получить API ключи**:
   - Gemini API key (Google AI Studio)
   - OpenRouter API key
   - Новый Telegram bot token
4. **Начать клонирование** - поэтапно по плану выше

---

## Источники

- **OpenClaw GitHub**: https://github.com/openclaw/openclaw
- **OpenClaw Docs**: https://docs.openclaw.ai/
- **Docker Setup**: https://docs.openclaw.ai/install/docker
- **Model Failover**: https://docs.openclaw.ai/concepts/model-failover
- **Model Providers**: https://docs.openclaw.ai/concepts/model-providers
- **Moltinger Project**: /Users/rl/coding/moltinger/
