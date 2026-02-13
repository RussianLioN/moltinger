# Feature Specification: Moltis Docker Deployment on ainetic.tech

**Feature Branch**: `001-moltis-docker-deploy`
**Created**: 2026-02-14
**Status**: Draft
**Input**: User description: "Проанализиуй документацию по адресу https://docs.moltis.org/docker.html и все остальные документы по адресу https://docs.moltis.org/ для составления спецификации на развертывание moltis в контейнере на удаленном сервере ainetic.tech"

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

1. **Given** настроенный reverse proxy (Nginx/Caddy), **When** пользователь подключается к ainetic.tech, **Then** соединение защищено TLS
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

### Edge Cases

- Что происходит при нехватке дискового пространства в volumes?
- Как система обрабатывает потерю соединения с Docker socket?
- Что происходит при попытке доступа без TLS с флагом MOLTIS_BEHIND_PROXY=true?
- Как обрабатываются одновременные подключения множества пользователей?
- Что происходит при истечении срока действия TLS-сертификата reverse proxy?

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
- **Reverse Proxy**: Внешний сервис (Nginx/Caddy) для TLS-терминации и маршрутизации трафика
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
- На сервере настроен reverse proxy (Nginx/Caddy) с валидным TLS-сертификатом для домена ainetic.tech
- DNS запись ainetic.tech указывает на IP-адрес сервера
- У администратора есть SSH-доступ к серверу для управления контейнером
- Используется официальный Docker-образ от ghcr.io/moltis-org/moltis
- Для sandbox выполнения команд будет примонтирован Docker socket (опционально)
- Сервер имеет минимум 2GB RAM и 10GB свободного дискового пространства
