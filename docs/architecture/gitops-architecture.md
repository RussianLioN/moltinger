# Архитектура GitOps 2.0 для Moltis Deployment на ainetic.tech

**Версия:** 1.0
**Дата:** 2025-02-15
**Автор:** Architecture Team

> **Status Note (2026-03-15)**:
> This document contains historical architecture material.
> The current operational contract for Moltis version changes and rollback lives in
> [../version-update.md](../version-update.md)
> and
> [../runbooks/moltis-backup-safe-update.md](../runbooks/moltis-backup-safe-update.md).
> If examples below mention `scripts/rollback.sh`, `restore-moltis.sh`, server-side `sed`,
> or arbitrary tag rollback, treat them as legacy design notes rather than the current runtime contract.
> The same applies to old provider examples such as `GLM_API_KEY`, Z.ai, or Anthropic API-key
> fallback chains: the active contract is `openai-codex::gpt-5.4` via OAuth with optional
> `OLLAMA_API_KEY` only for Ollama cloud fallback models.

---

## 1. Обзор архитектуры

### 1.1 Принципы GitOps 2.0

| Принцип | Описание |
|---------|----------|
| **Декларативность** | Вся инфраструктура описана в Git как код |
| **Иммутабельность** | Конфигурации версионированы и неизменяемы |
| **Автоматическая синхронизация** | Состояние кластера автоматически сходится к желаемому |
| **Непрерывное согласование** | Регулярная проверка drift и автоматическое исправление |

### 1.2 Компоненты архитектуры

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         GITOPS 2.0 ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────┐      ┌───────────────┐      ┌───────────────┐       │
│  │   GitHub Repo │      │  GitHub Actions│      │  ainetic.tech │       │
│  │   (Source of  │──────▶│   (CI/CD)     │──────▶│   (Runtime)   │       │
│  │    Truth)     │      │               │      │               │       │
│  └───────────────┘      └───────────────┘      └───────────────┘       │
│         │                      │                      │                │
│         │                      │                      │                │
│         ▼                      ▼                      ▼                │
│  ┌───────────────┐      ┌───────────────┐      ┌───────────────┐       │
│  │ Config Repo   │      │   Secrets     │      │   Deploy      │       │
│  │ - compose/    │      │   GitHub      │      │   Scripts     │       │
│  │ - config/     │      │   Secrets     │      │   (pull-based)│       │
│  │ - scripts/    │      │               │      │               │       │
│  └───────────────┘      └───────────────┘      └───────────────┘       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Стратегия CI/CD пайплайна

### 2.1 Workflow схема

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CI/CD PIPELINE FLOW                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Push to main ──▶ Validate ──▶ Build ──▶ Test ──▶ Deploy               │
│       │              │            │          │         │                │
│       │              │            │          │         │                │
│       ▼              ▼            ▼          ▼         ▼                │
│  ┌─────────┐   ┌─────────┐  ┌─────────┐ ┌────────┐ ┌─────────┐         │
│  │ Trigger │   │ Lint    │  │ Config  │ │ Health │ │ Staged  │         │
│  │         │   │ docker- │  │ Check   │ │ Check  │ │ Deploy  │         │
│  │         │   │ compose │  │         │ │         │ │         │         │
│  └─────────┘   └─────────┘  └─────────┘ └────────┘ └─────────┘         │
│                                                                         │
│  Environments:                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ staging (optional) ──▶ production (ainetic.tech)                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 GitHub Actions Workflow

**Файл:** `.github/workflows/deploy.yml`

```yaml
name: Deploy Moltis

on:
  push:
    branches: [main]
    paths:
      - 'docker-compose.yml'
      - 'config/**'
      - 'scripts/**'
      - '.github/workflows/deploy.yml'
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deployment environment'
        required: true
        default: 'production'
        type: choice
        options:
          - production
          - staging

env:
  DEPLOY_PATH: /opt/moltinger
  DEPLOY_USER: deploy

jobs:
  # ═══════════════════════════════════════════════════════════════════════
  # STAGE 1: Validation
  # ═══════════════════════════════════════════════════════════════════════
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Validate docker-compose.yml
        run: |
          docker compose config --quiet
          echo "✅ docker-compose.yml is valid"

      - name: Validate TOML syntax
        run: |
          # Install Python TOML validator
          pip install toml
          python3 -c "import toml; toml.load('config/moltis.toml')"
          echo "✅ moltis.toml is valid"

      - name: Check required files exist
        run: |
          test -f docker-compose.yml
          test -f config/moltis.toml
          test -f scripts/backup-moltis.sh
          echo "✅ All required files present"

  # ═══════════════════════════════════════════════════════════════════════
  # STAGE 2: Deploy (Production)
  # ═══════════════════════════════════════════════════════════════════════
  deploy:
    needs: validate
    if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request'
    runs-on: ubuntu-latest
    environment: production

    steps:
      - uses: actions/checkout@v4

      - name: Setup SSH key
        uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.DEPLOY_SSH_KEY }}

      - name: Add server to known hosts
        run: |
          mkdir -p ~/.ssh
          ssh-keyscan -H ainetic.tech >> ~/.ssh/known_hosts

      - name: Create deployment directory
        run: |
          ssh $DEPLOY_USER@ainetic.tech "mkdir -p $DEPLOY_PATH/{config,scripts,data}"

      - name: Sync configuration files
        run: |
          rsync -avz --delete \
            --exclude 'data/' \
            --exclude '.env*' \
            ./docker-compose.yml \
            $DEPLOY_USER@ainetic.tech:$DEPLOY_PATH/

          rsync -avz \
            ./config/ \
            $DEPLOY_USER@ainetic.tech:$DEPLOY_PATH/config/

          rsync -avz --chmod=+x \
            ./scripts/ \
            $DEPLOY_USER@ainetic.tech:$DEPLOY_PATH/scripts/

      - name: Create .env file from secrets
        run: |
          ssh $DEPLOY_USER@ainetic.tech "cat > $DEPLOY_PATH/.env << 'EOF'
          MOLTIS_PASSWORD=${{ secrets.MOLTIS_PASSWORD }}
          OLLAMA_API_KEY=${{ secrets.OLLAMA_API_KEY }}
          EOF"

      - name: Deploy with Docker Compose
        run: |
          ssh $DEPLOY_USER@ainetic.tech << 'ENDSSH'
          set -e
          cd /opt/moltinger

          chmod +x scripts/deploy.sh scripts/backup-moltis-enhanced.sh scripts/moltis-version.sh || true
          ./scripts/moltis-version.sh assert-tracked
          ./scripts/deploy.sh --json moltis deploy
          ENDSSH

      - name: Verify deployment
        run: |
          ssh $DEPLOY_USER@ainetic.tech << 'ENDSSH'
          cd /opt/moltinger

          # Check container is running
          if docker compose ps | grep -q "Up"; then
            echo "✅ Container is running"
          else
            echo "❌ Container failed to start"
            docker compose logs --tail=50
            exit 1
          fi

          # Health check via HTTP
          if curl -sf http://localhost:13131/health > /dev/null; then
            echo "✅ Health check passed"
          else
            echo "❌ Health check failed"
            exit 1
          fi
          ENDSSH

      - name: Notify on success
        if: success()
        run: |
          echo "🎉 Deployment successful!"
          echo "URL: https://ainetic.tech"

      - name: Notify on failure
        if: failure()
        run: |
          echo "❌ Deployment failed!"
          # Add Slack/Discord/Email notification here

  # ═══════════════════════════════════════════════════════════════════════
  # STAGE 3: Rollback (Manual)
  # ═══════════════════════════════════════════════════════════════════════
  rollback:
    if: github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    environment: production

    steps:
      - name: Setup SSH key
        uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.DEPLOY_SSH_KEY }}

      - name: Add server to known hosts
        run: |
          mkdir -p ~/.ssh
          ssh-keyscan -H ainetic.tech >> ~/.ssh/known_hosts

      - name: List available backups
        run: |
          ssh deploy@ainetic.tech "ls -lt /var/backups/moltis/ | head -10"

      - name: Select backup to restore
        run: |
          echo "To restore a backup, run manually:"
          echo "ssh deploy@ainetic.tech 'cd /opt/moltinger && ./scripts/deploy.sh --json moltis rollback'"
```

For Moltis, do not treat `docker compose pull/up`, server-side `sed`, or ad-hoc restarts as the primary rollout path anymore. The tracked compose files in git plus `backup-moltis-enhanced.sh` and `deploy.sh` are the authoritative contract.

---

## 3. Инфраструктура как код (IaC)

### 3.1 Структура директорий

```
moltinger/
├── docker-compose.yml           # Основной compose файл
├── config/
│   └── moltis.toml              # Конфигурация Moltis
├── scripts/
│   ├── backup-moltis-enhanced.sh # Backup + restore-check
│   ├── deploy.sh                # Deploy/rollback helper
│   └── health-check.sh          # Проверка здоровья (NEW)
├── deploy/
│   ├── setup-server.sh          # Начальная настройка сервера (NEW)
│   └── cron-backup              # Cron job для бэкапов (NEW)
├── .github/
│   └── workflows/
│       └── deploy.yml           # CI/CD пайплайн (NEW)
└── docs/
    └── architecture/
        └── gitops-architecture.md  # Этот документ (NEW)
```

### 3.2 Setup Script для сервера

**Файл:** `deploy/setup-server.sh`

```bash
#!/bin/bash
# Initial server setup for Moltis deployment
# Run once on a fresh server

set -e

DEPLOY_PATH="/opt/moltinger"
BACKUP_DIR="/var/backups/moltis"

echo "=== Moltis Server Setup ==="

# Create directories
echo "Creating directories..."
sudo mkdir -p $DEPLOY_PATH/{config,scripts,data}
sudo mkdir -p $BACKUP_DIR

# Set permissions
echo "Setting permissions..."
sudo chown -R $USER:$USER $DEPLOY_PATH
sudo chown -R $USER:$USER $BACKUP_DIR

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
fi

# Install Docker Compose plugin
echo "Ensuring Docker Compose is available..."
docker compose version || sudo apt-get install -y docker-compose-plugin

# Setup backup cron job
echo "Setting up backup cron job..."
(crontab -l 2>/dev/null; echo "0 3 * * * $DEPLOY_PATH/scripts/backup-moltis.sh >> /var/log/moltis-backup.log 2>&1") | crontab -

# Create log directory
sudo mkdir -p /var/log
sudo touch /var/log/moltis-backup.log
sudo chown $USER:$USER /var/log/moltis-backup.log

echo "=== Setup Complete ==="
echo "Next steps:"
echo "1. Copy docker-compose.yml to $DEPLOY_PATH/"
echo "2. Copy config/ to $DEPLOY_PATH/config/"
echo "3. Create .env file with secrets"
echo "4. Run: docker compose up -d"
```

### 3.3 Health Check Script

**Файл:** `scripts/health-check.sh`

```bash
#!/bin/bash
# Health check script for Moltis
# Returns 0 if healthy, 1 if not

set -e

CONTAINER_NAME="moltis"
HEALTH_URL="http://localhost:13131/health"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ Container $CONTAINER_NAME is not running"
    exit 1
fi

# Check HTTP health endpoint
if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
    echo "✅ Moltis is healthy"
    exit 0
else
    echo "❌ Health check failed for $HEALTH_URL"
    docker logs $CONTAINER_NAME --tail=20
    exit 1
fi
```

### 3.4 Restore / Rollback Helper

**Файл:** `scripts/deploy.sh`

```bash
# Roll back Moltis through the tracked helper
cd /opt/moltinger
./scripts/deploy.sh --json moltis rollback
```

The helper reuses the latest tracked backup reference, restore-check evidence, and previous image pointer instead of relying on manual untar/restart steps.

---

## 4. Обработка секретов

### 4.1 Стратегия управления секретами

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SECRETS MANAGEMENT FLOW                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Development          CI/CD               Production                   │
│  ┌─────────┐         ┌─────────┐          ┌─────────┐                  │
│  │.env.    │         │GitHub   │          │Server   │                  │
│  │local    │         │Secrets  │          │.env     │                  │
│  │         │         │         │          │         │                  │
│  │ git-    │         │ Encrypted│─────────▶│ Created │                  │
│  │ ignored │         │ at rest │   SSH    │ on-fly  │                  │
│  └─────────┘         └─────────┘          └─────────┘                  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 GitHub Secrets (Required)

| Secret Name | Description | How to Set |
|-------------|-------------|------------|
| `DEPLOY_SSH_KEY` | Private SSH key for server access | `Settings > Secrets > Actions > New` |
| `MOLTIS_PASSWORD` | Moltis authentication password | Generate: `openssl rand -base64 32` |
| `OLLAMA_API_KEY` | Optional API key for Ollama cloud fallback models | Set only if cloud Ollama fallback is enabled |

### 4.3 Настройка секретов

```bash
# 1. Генерация SSH ключа для деплоя (локально)
ssh-keygen -t ed25519 -C "github-actions@moltinger" -f deploy_key -N ""
cat deploy_key.pub  # Добавить в ~/.ssh/authorized_keys на сервере

# 2. Добавить приватный ключ в GitHub Secrets
# Repository > Settings > Secrets and variables > Actions
# Name: DEPLOY_SSH_KEY
# Value: содержимое deploy_key

# 3. Добавить MOLTIS_PASSWORD
openssl rand -base64 32  # Сгенерировать пароль

# 4. Добавить OLLAMA_API_KEY (опционально, только для cloud fallback)
# Primary GPT-5.4 path использует openai-codex OAuth, а не отдельный API key secret
```

### 4.4 Local Development

```bash
# Скопировать пример
cp .env.example .env.local

# Отредактировать
nano .env.local

# .env.local добавлен в .gitignore
```

---

## 5. Стратегия отката (Rollback)

### 5.1 Rollback Matrix

| Сценарий | Метод | Автоматизация |
|----------|-------|---------------|
| Контейнер не запустился | `docker compose restart` | Автоматически |
| Health check fail | Откат к предыдущему образу | Полуавтоматически |
| Конфигурация сломана | Восстановление из backup | Вручную |
| Критический сбой | Полное восстановление VM | Вручную |

### 5.2 Rollback Workflow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ROLLBACK DECISION TREE                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│                    ┌─────────────────┐                                  │
│                    │   Deployment    │                                  │
│                    │     Failed      │                                  │
│                    └────────┬────────┘                                  │
│                             │                                           │
│              ┌──────────────┼──────────────┐                           │
│              ▼              ▼              ▼                           │
│       ┌──────────┐   ┌──────────┐   ┌──────────┐                       │
│       │ Container│   │  Config  │   │   Data   │                       │
│       │  Issue   │   │  Issue   │   │  Issue   │                       │
│       └────┬─────┘   └────┬─────┘   └────┬─────┘                       │
│            │              │              │                              │
│            ▼              ▼              ▼                              │
│       ┌──────────┐   ┌──────────┐   ┌──────────┐                       │
│       │Rollback  │   │  Revert  │   │  Restore │                       │
│       │  Image   │   │  Config  │   │  Backup  │                       │
│       │          │   │  Commit  │   │          │                       │
│       └──────────┘   └──────────┘   └──────────┘                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Rollback Helper

**Файл:** `scripts/deploy.sh`

```bash
# Roll back Moltis through the tracked helper
# Usage: ./scripts/deploy.sh --json moltis rollback

set -e

DEPLOY_PATH="/opt/moltinger"
cd $DEPLOY_PATH

./scripts/deploy.sh --json moltis rollback

# Wait and verify
echo "Waiting for health check..."
sleep 15
if curl -sf http://localhost:13131/health > /dev/null; then
    echo "✅ Rollback successful"
    env -u MOLTIS_VERSION docker compose -f docker-compose.prod.yml ps
else
    echo "❌ Rollback failed"
    env -u MOLTIS_VERSION docker compose -f docker-compose.prod.yml logs --tail=50
    exit 1
fi
```

### 5.4 Автоматический откат в CI/CD

Добавить в `deploy.yml`:

```yaml
      - name: Automatic rollback on failure
        if: failure()
        run: |
          ssh $DEPLOY_USER@ainetic.tech << 'ENDSSH'
          set -e
          cd /opt/moltinger

          echo "Deployment failed, attempting rollback..."
          ./scripts/deploy.sh --json moltis rollback
          ENDSSH
```

Rollback authority should come from the same tracked evidence path:
- latest fresh backup reference
- matching restore-check evidence
- previous image pointer
- rollback evidence under `data/moltis/audit/rollback-evidence/`

---

## 6. Мониторинг и алертинг

### 6.1 Health Endpoints

| Endpoint | Purpose | Expected Response |
|----------|---------|-------------------|
| `/health` | Container health | `200 OK` |
| `:13131` | Main service | WebSocket/HTTP |
| `:13132` | CA download | HTTP redirect |

### 6.2 Cron Monitoring

```bash
# deploy/cron-backup
# Add to crontab: crontab deploy/cron-backup

# Daily backup at 3 AM
0 3 * * * /opt/moltinger/scripts/backup-moltis.sh >> /var/log/moltis-backup.log 2>&1

# Health check every 5 minutes
*/5 * * * * /opt/moltinger/scripts/health-check.sh >> /var/log/moltis-health.log 2>&1 || echo "ALERT: Moltis unhealthy" | mail -s "Moltis Alert" admin@example.com
```

---

## 7. Безопасность

### 7.1 Security Checklist

- [ ] SSH key authentication only (no passwords)
- [ ] GitHub Secrets для всех credentials
- [ ] `.env` файлы в `.gitignore`
- [ ] Traefik TLS termination с Let's Encrypt
- [ ] Docker socket mounted read-only (if possible)
- [ ] Regular backup rotation (7 days)
- [ ] Audit log for deployments

### 7.2 Network Security

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        NETWORK ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│                    Internet (HTTPS)                                    │
│                         │                                               │
│                         ▼                                               │
│              ┌─────────────────────┐                                   │
│              │      Traefik        │                                   │
│              │   (Port 443/80)     │                                   │
│              │   TLS Termination   │                                   │
│              └──────────┬──────────┘                                   │
│                         │                                               │
│                         ▼                                               │
│              ┌─────────────────────┐                                   │
│              │       Moltis        │                                   │
│              │   (Port 13131)      │                                   │
│              │   Internal Only     │                                   │
│              └─────────────────────┘                                   │
│                                                                         │
│  Firewall Rules:                                                        │
│  - Port 22 (SSH): Restricted IPs                                       │
│  - Port 80/443: Open (Traefik)                                        │
│  - Port 13131: Localhost only                                         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 8. Краткое руководство по внедрению

### 8.1 One-time Setup

```bash
# 1. На сервере ainetic.tech
git clone https://github.com/YOUR_REPO/moltinger.git /opt/moltinger
cd /opt/moltinger
bash deploy/setup-server.sh

# 2. Настроить GitHub Secrets
# Repository > Settings > Secrets > Actions
# - DEPLOY_SSH_KEY
# - MOLTIS_PASSWORD
# - OLLAMA_API_KEY (optional)

# 3. Создать .env на сервере (первичный деплой)
ssh deploy@ainetic.tech
cd /opt/moltinger
cat > .env << EOF
MOLTIS_PASSWORD=$(openssl rand -base64 32)
OLLAMA_API_KEY=your_optional_key_here
EOF

# 4. Запустить первый деплой
docker compose up -d
```

### 8.2 Daily Workflow

```bash
# Локально: внести изменения
vim config/moltis.toml

# Закоммитить и запушить
git add .
git commit -m "chore: update config"
git push

# CI/CD автоматически:
# 1. Валидирует конфигурацию
# 2. Деплоит на ainetic.tech
# 3. Проверяет health check
```

### 8.3 Emergency Rollback

```bash
# Вариант 1: Через GitHub Actions
# Actions > Deploy Moltis > Run workflow > rollback

# Вариант 2: Напрямую на сервере
ssh deploy@ainetic.tech
cd /opt/moltinger
./scripts/deploy.sh --json moltis rollback

# Вариант 3: Восстановление из бэкапа
./scripts/deploy.sh --json moltis rollback
```

---

## 9. Метрики успеха

| Метрика | Target | Measurement |
|---------|--------|-------------|
| Deployment success rate | >95% | GitHub Actions success/fail |
| Mean time to recovery (MTTR) | <15 min | Time from alert to restore |
| Backup success rate | 100% | Cron job logs |
| Configuration drift | 0% | Git vs server diff |

---

## 10. Следующие шаги

1. **Создать файлы инфраструктуры** - добавить предложенные скрипты
2. **Настроить GitHub Actions** - создать `.github/workflows/deploy.yml`
3. **Добавить GitHub Secrets** - DEPLOY_SSH_KEY, MOLTIS_PASSWORD, OLLAMA_API_KEY (optional)
4. **Протестировать деплой** - сделать тестовый пуш в main
5. **Настроить мониторинг** - добавить health check cron job
6. **Документировать runbook** - инструкции для дежурных

---

*Документ создан в рамках анализа архитектуры GitOps 2.0 для Moltis deployment.*
