# Feature Specification: Moltis Docker Deployment on ainetic.tech

**Feature Branch**: `001-moltis-docker-deploy`
**Created**: 2026-02-14
**Status**: Research Complete
**Research Report**: [docs/reports/moltis-deployment-research.md](../../docs/reports/moltis-deployment-research.md)
**Input**: User description: "Проанализиуй документацию по адресу https://docs.moltis.org/docker.html и все остальные документы по адресу https://docs.moltis.org/ для составления спецификации на развертывание moltis в контейнере на удаленном сервере ainetic.tech"

## Clarifications

### Session 2026-02-14

- Q: Какой reverse proxy использовать? → A: **Traefik** (уже развёрнут на сервере)
- Q: Какой LLM провайдер использовать? → A: **GLM (Zhipu AI)** через OpenAI-compatible endpoint `https://api.z.ai/api/coding/paas/v4`
- Q: Как обновлять контейнер Moltis? → A: **Watchtower** для автоматических обновлений
- Q: Нужна ли стратегия backup для volumes? → A: **Cron backup** — ежедневное резервирование с rotation 7 дней
- Q: Что НЕ входит в scope? → A: **Базовый out-of-scope** — кластеризация, multi-region, SLA guarantees

## Out of Scope

Следующее **НЕ входит** в scope данного развертывания:

| Area | Excluded Items | Rationale |
|------|----------------|-----------|
| **High Availability** | Кластеризация, failover, load balancing | Single-server deployment |
| **Multi-region** | Geo-distribution, CDN integration | Not required for current use case |
| **SLA Guarantees** | Uptime commitments, formal SLA | Personal/team use, not production SLA |
| **Advanced Monitoring** | Grafana dashboards, Prometheus, alerting | Basic `/health` endpoint sufficient |
| **Log Aggregation** | ELK stack, centralized logging | Container logs sufficient |
| **Custom MCP Servers** | Custom MCP integrations | Use built-in tools first |

**Future Considerations** (deferred to later phases):
- OpenTelemetry integration (User Story 9 - P3)
- Passkey authentication (User Story 8 - P2)
- API key management for CI/CD (User Story 7 - P2)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Container Deployment (Priority: P1)

Как DevOps-инженер, я хочу развернуть Moltis в Docker-контейнере на удаленном сервере ainetic.tech, чтобы получить собственный AI-ассистент с Web UI, доступный через HTTPS.

**Why this priority**: Это основная функциональность - без работающего контейнера недоступны все остальные возможности Moltis.

**Independent Test**: Можно проверить успешность развертывания, открыв Web UI по адресу https://ainetic.tech и убедившись в возможности начать чат после настройки LLM-провайдера.

**Acceptance Scenarios**:

1. **Given** сервер ainetic.tech с установленным Docker, **When** запускается docker compose up -d, **Then** контейнер Moltis успешно стартует и доступен на порту 13131
2. **Given** запущенный контейнер Moltis, **When** пользователь открывает https://ainetic.tech в браузере, **Then** отображается Web UI с запросом на настройку LLM-провайдера
3. **Given** контейнер с примонтированными volumes, **When** контейнер перезапускается, **Then** все настройки и данные сохраняются

---

### User Story 2 - Secure Remote Access (Priority: P1)

Как администратор, я хочу настроить защищенный доступ к Moltis через reverse proxy с TLS, чтобы пользователи могли безопасно подключаться из интернета.

**Why this priority**: Безопасность критична при暴露 сервиса в интернет - это обязательное требование для продакшн-развертывания.

**Independent Test**: Можно проверить работу TLS, открыв https://ainetic.tech и убедившись в валидности SSL-сертификата.

**Acceptance Scenarios**:

1. **Given** настроенный reverse proxy (Traefik), **When** пользователь подключается к ainetic.tech, **Then** соединение защищено TLS
2. **Given** Moltis запущен с флагом --no-tls, **When** reverse proxy терминирует TLS, **Then** Moltis корректно обрабатывает проксированные запросы
3. **Given** установлена переменная MOLTIS_BEHIND_PROXY=true, **When** запрос приходит через proxy, **Then** Moltis корректно определяет реальный IP клиента

---

### User Story 3 - Authentication Setup (Priority: P1)

Как администратор, я хочу настроить аутентификацию для удаленного доступа, чтобы только авторизованные пользователи могли использовать AI-ассистент.

**Why this priority**: Аутентификация обязательна для удаленного доступа - без неё сервис уязвим для несанкционированного использования.

**Independent Test**: Можно проверить аутентификацию, попытавшись войти с правильным и неправильным паролем.

**Acceptance Scenarios**:

1. **Given** первый запуск Moltis на удаленном сервере, **When** пользователь подключается извне, **Then** требуется ввод setup code из логов контейнера
2. **Given** установлена переменная MOLTIS_PASSWORD, **When** пользователь открывает Web UI, **Then** требуется авторизация с предустановленным паролем
3. **Given** настроенная аутентификация, **When** неверные учетные данные введены 5 раз за минуту, **Then** возвращается ошибка 429 Too Many Requests

---

### User Story 4 - Persistent Data Storage (Priority: P2)

Как пользователь, я хочу, чтобы мои сессии, настройки и память AI сохранялись между перезапусками контейнера, чтобы не терять контекст conversations.

**Why this priority**: Сохранение данных важно для пользовательского опыта, но технически возможно работать и без персистентности.

**Independent Test**: Можно проверить персистентность, создав сессию, перезапустив контейнер и убедившись, что сессия доступна.

**Acceptance Scenarios**:

1. **Given** примонтированные volumes config и data, **When** контейнер перезапускается, **Then** файл moltis.toml сохраняется
2. **Given** примонтированный volume data, **When** контейнер перезапускается, **Then** базы данных сессий и memory files сохраняются
3. **Given** примонтированный volume config, **When** настраиваются LLM провайдеры, **Then** credentials.json сохраняется

---

### User Story 5 - Sandboxed Command Execution (Priority: P2)

Как пользователь, я хочу, чтобы AI мог выполнять shell-команды в изолированной sandbox-среде, чтобы автоматизировать рутинные задачи безопасно.

**Why this priority**: Sandbox расширяет возможности AI, но требует доступа к Docker socket и не критичен для базового чата.

**Independent Test**: Можно проверить sandbox, попросив AI выполнить простую команду (например, ls) и убедившись, что она выполняется в контейнере.

**Acceptance Scenarios**:

1. **Given** примонтированный /var/run/docker.sock, **When** AI выполняет shell-команду, **Then** команда выполняется в изолированном контейнере
2. **Given** настроенный sandbox, **When** AI выполняет команду, **Then** базовый образ ubuntu:25.10 используется с предустановленными пакетами
3. **Given** отключенный sandbox (без socket mount), **When** AI пытается выполнить команду, **Then** команда выполняется напрямую в контейнере Moltis

---

### User Story 6 - Health Monitoring (Priority: P3)

Как DevOps-инженер, я хочу иметь health check endpoint для мониторинга состояния сервиса, чтобы интегрировать Moltis в систему мониторинга.

**Why this priority**: Мониторинг важен для production, но не критичен для базового развертывания.

**Independent Test**: Можно проверить health check, выполнив GET запрос на /health и получив статус 200.

**Acceptance Scenarios**:

1. **Given** запущенный контейнер Moltis, **When** выполняется GET /health, **Then** возвращается HTTP 200
2. **Given** настроенный Docker healthcheck, **When** контейнер unhealthy, **Then** Docker помечает контейнер как unhealthy

---

### User Story 7 - API Key Management (Priority: P2)

Как администратор, я хочу создавать API keys с минимальными scopes для программного доступа к Moltis, чтобы интегрировать AI-ассистент в автоматизированные workflows.

**Why this priority**: API keys нужны для CI/CD и автоматизации, но не критичны для базового использования через Web UI.

**Independent Test**: Можно проверить API key, отправив запрос с заголовком `Authorization: Bearer mk_xxx` и получив корректный ответ.

**Acceptance Scenarios**:

1. **Given** авторизованная сессия, **When** создаётся API key с scope `operator.read`, **Then** key может только читать статус и историю
2. **Given** API key без scopes, **When** используется для аутентификации, **Then** запрос отклоняется (keys без scopes denied)
3. **Given** API key с scope `operator.admin`, **When** используется для запроса, **Then** предоставляются все permissions

---

### User Story 8 - Passkey Authentication (Priority: P2)

Как пользователь, я хочу использовать hardware security key (YubiKey) или platform authenticator (Touch ID, Windows Hello) для аутентификации, чтобы повысить безопасность доступа.

**Why this priority**: Passkeys обеспечивают более высокий уровень безопасности, но password достаточен для базовой защиты.

**Independent Test**: Можно проверить passkey, подключив YubiKey и убедившись, что аутентификация проходит успешно.

**Acceptance Scenarios**:

1. **Given** авторизованная сессия, **When** регистрируется passkey, **Then** passkey сохраняется в базе
2. **Given** зарегистрированный passkey, **When** пользователь логинится, **Then** Touch ID/WebAuthn диалог появляется
3. **Given** несколько passkeys, **When** просматриваются в Settings, **Then** отображается список всех зарегистрированных passkeys

---

### User Story 9 - OpenTelemetry Monitoring (Priority: P3)

Как DevOps-инженер, я хочу экспортировать метрики и трейсы в OpenTelemetry collector, чтобы интегрировать Moltis в существующую observability stack.

**Why this priority**: Observability важна для production, но не критична для базового развертывания.

**Independent Test**: Можно проверить интеграцию, настроив OTLP endpoint и убедившись, что метрики поступают в collector.

**Acceptance Scenarios**:

1. **Given** настроенный `[telemetry] otlp_endpoint`, **When** Moltis запускается, **Then** метрики отправляются в collector
2. **Given** работающая интеграция, **When** выполняются запросы, **Then** traces записываются с правильными spans

---

### Edge Cases

- Что происходит при нехватке дискового пространства в volumes?
- Как система обрабатывает потерю соединения с Docker socket?
- Что происходит при попытке доступа без TLS с флагом MOLTIS_BEHIND_PROXY=true?
- Как обрабатываются одновременные подключения множества пользователей?
- Что происходит при истечении срока действия TLS-сертификата reverse proxy?
- **Docker socket loss**: Что происходит при потере Docker socket во время runtime?
- **Setup code loss**: Как регенерировать setup code без потери данных?
- **Certificate expiry**: Что происходит при истечении self-signed CA сертификата?
- **Provider auth failures**: Как обрабатывается истечение OAuth токена провайдера?
- **Volume permissions**: Что происходит при неправильных permissions (UID 1000)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Система ДОЛЖНА запускать Moltis как Docker-контейнер из образа ghcr.io/moltis-org/moltis:latest
- **FR-002**: Система ДОЛЖНА предоставлять Web UI на порту 13131 (HTTP/WebSocket)
- **FR-003**: Система ДОЛЖНА поддерживать персистентное хранение данных через Docker volumes или bind mounts
- **FR-004**: Система ДОЛЖНА конфигурироваться через переменные окружения и/или moltis.toml
- **FR-005**: Система ДОЛЖНА поддерживать работу за reverse proxy с TLS-терминацией
- **FR-006**: Система ДОЛЖНА требовать аутентификацию при удаленном доступе
- **FR-007**: Система ДОЛЖНА поддерживать предустановку пароля через MOLTIS_PASSWORD
- **FR-008**: Система ДОЛЖНА предоставлять health check endpoint на /health
- **FR-009**: Система ДОЛЖНА поддерживать sandboxed выполнение команд при наличии Docker socket
- **FR-010**: Система ДОЛЖНА корректно определять реальный IP клиента при MOLTIS_BEHIND_PROXY=true
- **FR-011**: Система ДОЛЖНА применять rate limiting для аутентификационных endpoints

### Key Entities

- **Moltis Container**: Docker-контейнер с AI-ассистентом, включает Web UI, WebSocket gateway, agent loop, provider registry
- **Configuration Volume**: Персистентное хранилище для moltis.toml, credentials.json, mcp-servers.json (путь: /home/moltis/.config/moltis)
- **Data Volume**: Персистентное хранилище для баз данных, сессий, memory files, логов (путь: /home/moltis/.moltis)
- **Docker Socket**: Unix socket для доступа к Docker daemon, необходим для sandboxed выполнения команд
- **Reverse Proxy**: Traefik (уже развёрнут на сервере) для TLS-терминации и маршрутизации трафика
- **LLM Provider**: GLM (Zhipu AI) через OpenAI-compatible endpoint `https://api.z.ai/api/coding/paas/v4`
- **Credentials**: Пароли (Argon2id хеш), passkeys (WebAuthn), API keys (SHA-256 хеш), session cookies

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Контейнер Moltis запускается и становится доступным в течение 30 секунд после docker compose up
- **SC-002**: Web UI загружается и отвечает на запросы пользователя менее чем за 2 секунды
- **SC-003**: Все данные (конфигурация, сессии, память) сохраняются после перезапуска контейнера с нулевой потерей данных
- **SC-004**: Health check endpoint (/health) отвечает HTTP 200 менее чем за 100ms
- **SC-005**: Система поддерживает не менее 10 одновременных WebSocket-соединений без деградации производительности
- **SC-006**: Rate limiting корректно блокирует после 5 неудачных попыток входа в течение 60 секунд
- **SC-007**: TLS-соединение устанавливается с рейтингом A или выше на SSL Labs
- **SC-008**: Sandbox команды выполняются в изолированном контейнере в течение 5 секунд для простых операций

## Assumptions

- На сервере ainetic.tech уже установлен Docker и Docker Compose
- На сервере развёрнут Traefik с валидным TLS-сертификатом для домена ainetic.tech
- DNS запись ainetic.tech указывает на IP-адрес сервера
- У администратора есть SSH-доступ к серверу для управления контейнером
- Используется официальный Docker-образ от ghcr.io/moltis-org/moltis
- Для sandbox выполнения команд будет примонтирован Docker socket (опционально)
- Сервер имеет минимум 2GB RAM и 10GB свободного дискового пространства

## Security Warnings ⚠️

### Docker Socket Mount

> **CRITICAL**: Mount `/var/run/docker.sock` gives the container **full access to Docker daemon**. This is equivalent to **root access on the host** for practical purposes.
>
> **ONLY run Moltis containers from trusted sources** — use official images from `ghcr.io/moltis-org/moltis`.

**If socket cannot be mounted**:
- Sandbox execution is **disabled**
- Agent works for chat-only interactions
- Shell commands **fail** or execute directly in Moltis container (no isolation)

### Unauthenticated Exposure

> **NEVER expose an unauthenticated Moltis instance to the internet.**
>
> Without credentials configured, remote connections can only access onboarding flow, but this still exposes the service.

---

## Environment Variables Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `MOLTIS_CONFIG_DIR` | Override config directory | `~/.config/moltis` | No |
| `MOLTIS_DATA_DIR` | Override data directory | `~/.moltis` | No |
| `MOLTIS_PORT` | Gateway port | 13131 | No |
| `MOLTIS_HOST` | Listen address | `0.0.0.0` | No |
| `MOLTIS_NO_TLS` | Disable TLS (for reverse proxy) | (not set) | Yes, if behind proxy |
| `MOLTIS_BEHIND_PROXY` | Force remote connection treatment | (not set) | **Yes, if behind proxy** |
| `MOLTIS_DEPLOY_PLATFORM` | Cloud platform identifier | (not set) | No |
| `MOLTIS_PASSWORD` | Pre-set initial password | (not set) | Recommended for cloud |
| `MOLTIS_TLS__HTTP_REDIRECT_PORT` | Port for HTTP redirect server | gateway_port + 1 | No |

---

## Authentication Architecture

### Three-Tier Authentication Model

| Tier | Condition | Behaviour |
|------|-----------|-----------|
| **1 — Full auth** | Password or passkey configured | Auth **ALWAYS** required (any IP) |
| **2 — Local dev** | No credentials + direct local connection | Full access (dev convenience) |
| **3 — Remote setup** | No credentials + remote/proxied connection | Setup flow only |

### Local Connection Detection

A connection is classified as **local** ONLY when **ALL FOUR** checks pass:

1. `MOLTIS_BEHIND_PROXY` env var is **NOT** set
2. No proxy headers present (`X-Forwarded-For`, `X-Real-IP`, `CF-Connecting-IP`, `Forwarded`)
3. The `Host` header resolves to a loopback address (or is absent)
4. The TCP source IP is loopback (`127.0.0.1`, `::1`)

**If ANY check fails**, connection is treated as remote.

### Credential Types

| Type | Storage | Use Case |
|------|---------|----------|
| **Password** | Argon2id hash | Primary authentication |
| **Passkey** | WebAuthn serialized data | Hardware keys (YubiKey, Touch ID) |
| **Session Cookie** | HTTP-only, SameSite=Strict | Browser sessions (30-day expiry) |
| **API Key** | SHA-256 hash (prefix `mk_`) | Programmatic access |

### API Key Scopes

| Scope | Permissions |
|-------|-------------|
| `operator.read` | View status, list jobs, read history |
| `operator.write` | Send messages, create jobs, modify config |
| `operator.admin` | All permissions (superset) |
| `operator.approvals` | Handle command approval requests |
| `operator.pairing` | Manage device/node pairing |

---

## Rate Limiting Details

**Requests bypass IP throttling when**:
- Request is already authenticated (session or API key)
- Auth is not enforced (`auth_disabled = true`)
- Setup is incomplete and request is allowed by local Tier-2 access

| Endpoint | Limit |
|----------|-------|
| `POST /api/auth/login` | **5 requests / 60 seconds** |
| Other `/api/auth/*` | 120 requests / 60 seconds |
| Other `/api/*` | 180 requests / 60 seconds |
| `/ws` upgrade | 30 requests / 60 seconds |

**When limit exceeded**: Returns `429 Too Many Requests` with `Retry-After` header.

---

## Reverse Proxy Configuration (Traefik)

### Traefik Labels для docker-compose.yml

```yaml
services:
  moltis:
    # ... existing config ...
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.moltis.rule=Host(`ainetic.tech`)"
      - "traefik.http.routers.moltis.entrypoints=websecure"
      - "traefik.http.routers.moltis.tls.certresolver=letsencrypt"
      - "traefik.http.services.moltis.loadbalancer.server.port=13131"
      # WebSocket support
      - "traefik.http.middlewares.moltis-ws.headers.customrequestheaders.X-Forwarded-Proto=https"
```

### Required Headers (автоматически от Traefik)

- `X-Forwarded-For` — client IP
- `X-Forwarded-Proto` — original protocol
- `X-Real-IP` — real client address
- `Host` — original host header

---

## Sandbox Configuration

### Backend Priority (auto mode)

| Priority | Backend | Platform | Isolation |
|----------|---------|----------|-----------|
| 1 | Apple Container | macOS | VM (Virtualization.framework) |
| 2 | Docker | any | Linux namespaces / cgroups |
| 3 | none (host) | any | **no isolation** |

### Resource Limits

```toml
[tools.exec.sandbox.resource_limits]
memory_limit = "512M"
cpu_quota = 1.0
pids_max = 256
```

### Cloud Deployment Limitation

> **WARNING**: Most cloud providers (Fly.io, DigitalOcean App Platform, Render) do **NOT** support Docker-in-Docker. Sandboxed command execution **will not work** on these platforms.

---

## Backup Strategy

### Cron Backup Script

Ежедневное резервирование config и data volumes с retention 7 дней.

```bash
#!/bin/bash
# /usr/local/bin/backup-moltis.sh

BACKUP_DIR="/var/backups/moltis"
CONFIG_DIR="/path/to/moltinger/config"
DATA_DIR="/path/to/moltinger/data"
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

# Create timestamped backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
tar -czf "$BACKUP_DIR/moltis_$TIMESTAMP.tar.gz" \
    -C "$(dirname $CONFIG_DIR)" "$(basename $CONFIG_DIR)" \
    -C "$(dirname $DATA_DIR)" "$(basename $DATA_DIR)"

# Rotate old backups
find "$BACKUP_DIR" -name "moltis_*.tar.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: moltis_$TIMESTAMP.tar.gz"
```

### Cron Schedule

```cron
# /etc/cron.d/moltis-backup
0 3 * * * root /usr/local/bin/backup-moltis.sh >> /var/log/moltis-backup.log 2>&1
```

### What's Backed Up

| Directory | Contents | Priority |
|-----------|----------|----------|
| `config/` | moltis.toml, credentials.json, provider_keys.json | Critical |
| `data/` | Sessions DB, memory files, logs | High |

### Recovery

```bash
# Restore through the tracked rollback helper
./scripts/deploy.sh --json moltis rollback
```

---

## Container Updates (Git-Tracked Rollout)

### Configuration

Moltis version updates must come from git-tracked compose changes plus a fresh backup-safe rollout. Watchtower may exist as an auxiliary container, but it must not be the authority that advances the Moltis image version.

```yaml
# Добавить в docker-compose.yml
services:
  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true          # Удалять старые образы
      - WATCHTOWER_POLL_INTERVAL=86400   # Проверка раз в 24 часа
      - WATCHTOWER_LABEL_ENABLE=true     # Только контейнеры с label
    restart: unless-stopped

  moltis:
    # ... existing config ...
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
```

### Behavior

- Проверяет `ghcr.io/moltis-org/moltis:latest` каждые 24 часа
- При обнаружении новой версии: graceful shutdown → pull → restart
- Старые образы автоматически удаляются (`WATCHTOWER_CLEANUP=true`)

---

## LLM Provider Configuration (GLM)

### Endpoint

**Base URL**: `https://api.z.ai/api/coding/paas/v4`

**Auth**: API Key (хранится в `provider_keys.json`)

### Configuration (moltis.toml)

```toml
[providers]
default = "glm-coding"

[providers.glm-coding]
enabled = true
# OpenAI-compatible endpoint для GLM
base_url = "https://api.z.ai/api/coding/paas/v4"
model = "glm-4-plus"  # или другая модель из линейки
```

### API Key Setup

API key для GLM устанавливается через Web UI при первом запуске или напрямую в `~/.config/moltis/provider_keys.json`.

---

## References

- **Docker Deployment**: https://docs.moltis.org/docker.html
- **Configuration**: https://docs.moltis.org/configuration.html
- **Authentication**: https://docs.moltis.org/authentication.html
- **Cloud Deployment**: https://docs.moltis.org/cloud-deploy.html
- **Sandbox**: https://docs.moltis.org/sandbox.html
- **Research Report**: [docs/reports/moltis-deployment-research.md](../../docs/reports/moltis-deployment-research.md)
