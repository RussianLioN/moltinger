# Тотальное ревью развертывания asc-demo

## Executive Summary

**Общая оценка: ⚠️ ТРЕБУЕТ ДОРАБОТКИ перед production**
Система развертывания asc-demo имеет базовую функциональность, но содержит критические пробелы в автоматизации, безопасности и observability.

---

## 1. Архитектура развертывания

### 1.1 Текущая схема

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              TRAEFIK (ainetic.tech)                          │
│                        (SSL, Let's Encrypt, Routing)                         │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           demo.ainetic.tech                                  │
│                              asc-demo                                        │
│                    (Python 3.12 + agent-factory-web-adapter)                 │
│                              Port 18791                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Конфигурационные файлы

| Файл | Назначение | Статус |
|------|------------|--------|
| `docker-compose.asc.yml` | Compose-конфигурация asc-demo | ✅ Есть |
| `scripts/deploy.sh` | Скрипт развертывания (поддерживает asc-demo) | ✅ Есть |
| `scripts/preflight-check.sh` | Pre-flight валидация | ❌ **Нет поддержки asc-demo** |
| `.github/workflows/deploy-asc-demo.yml` | CI/CD пайплайн | ❌ **Отсутствует** |
| `.env.asc` | Файл переменных окружения | ❌ **Отсутствует** |
| `asc-demo/.env.example` | Пример env для Node.js версии | ✅ Есть (устарел) |

---

## 2. Критические проблемы (P0 - Блокирующие)

### 2.1 Отсутствие CI/CD пайплайна для asc-demo

**Проблема:** Нет dedicated GitHub workflow для автоматического развертывания asc-demo.

**Где:** `.github/workflows/deploy-asc-demo.yml` — отсутствует

**Последствия:**
- Развертывание только вручную через `scripts/deploy.sh asc-demo deploy`
- Нет автоматической валидации перед деплоем
- Нет интеграции с GitOps

**Рекомендация:** Создать workflow аналогичный `deploy-clawdiy.yml`.

---

### 2.2 Preflight-check не поддерживает asc-demo

**Проблема:** `scripts/preflight-check.sh` имеет только `moltis` и `clawdiy` targets.

**Где:** Строки 134-184 в `scripts/preflight-check.sh`

```bash
case "$TARGET" in
    moltis)
        REQUIRED_SECRETS=(...)
        ...
    clawdiy)
        REQUIRED_SECRETS=(...)
        ...
    *)
        echo "Unsupported target: $TARGET" >&2
        exit 1
        ;;
esac
```

**Последствия:**
- Нет валидации перед деплоем asc-demo
- Нет проверки секретов asc-demo
- CI/CD не может валидировать конфигурацию

**Рекомендация:** Добавить target `asc-demo` в `configure_target()`.

---

### 2.3 Отсутствие документации секретов asc-demo

**Проблема:** Неизвестно какие GitHub Secrets требуются для asc-demo.

**Где:** `docs/SECRETS-MANAGEMENT.md` — нет раздела для asc-demo

**Требуемые переменные (из `docker-compose.asc.yml`):**
- `ASC_DEMO_DOMAIN`
- `ASC_DEMO_PUBLIC_BASE_URL`
- `ASC_DEMO_ACCESS_MODE`
- `ASC_DEMO_SHARED_TOKEN_HASH`
- `ASC_DEMO_OPERATOR_LABEL`
- `ASC_DEMO_INTERNAL_PORT`

**Рекомендация:** Добавить раздел в `docs/SECRETS-MANAGEMENT.md`.

---

## 3. Средние проблемы (P1 - Важные)

### 3.1 Python-образ без Node.js для web-адаптера

**Проблема:** `docker-compose.asc.yml` использует `python:3.12-slim`, но сервис запускает Python-скрипт.

**Где:** Строка 23 `docker-compose.asc.yml`
```yaml
image: ${ASC_DEMO_IMAGE:-python:3.12-slim}
```

**Команда запуска:**
```yaml
command:
  - /bin/sh
  - -lc
  - >
    python3 scripts/agent-factory-web-adapter.py serve
    --host 0.0.0.0
    --port ${ASC_DEMO_INTERNAL_PORT:-18791}
```

**Анализ:** На самом деле это корректно — `agent-factory-web-adapter.py` — это Python-приложение, не Node.js. Но название `asc-demo` путает, так как есть также `asc-demo/server.js` (Node.js) который НЕ используется в этом deployment.

**Рекомендация:** Добавить комментарий в docker-compose.asc.yml объясняющий архитектуру.

---

### 3.2 Нет интеграции с системой бэкапов

**Проблема:** `scripts/backup-moltis-enhanced.sh` не включает данные asc-demo.

**Где:** Данные asc-demo хранятся в `data/agent-factory/web-demo/`, `data/agent-factory/discovery/`, `data/agent-factory/concepts/`

**Рекомендация:** Добавить пути `data/agent-factory/` в backup script.

---

### 3.3 Нет health check эндпоинта в web-adapter

**Проблема:** Docker health check пытается достучаться до `/health`, но `agent-factory-web-adapter.py` может не иметь этого endpoint.

**Где:** Строки 11-19 `docker-compose.asc.yml`
```yaml
x-asc-demo-healthcheck: &asc-demo-healthcheck
  test:
    [
      "CMD-SHELL",
      "python3 -c \"... urllib.request.urlopen(f'http://127.0.0.1:${ASC_DEMO_INTERNAL_PORT:-18791}{path}'..."
    ]
```

**Риск:** Health check может всегда возвращать unhealthy.

**Рекомендация:** Проверить наличие `/health` endpoint в `agent-factory-web-adapter.py`.

---

### 3.4 Сетевая конфигурация может конфликтовать

**Проблема:** `docker-compose.asc.yml` использует сети `traefik-net`, `fleet-internal`, `monitoring` как external.

**Где:** Строки 127-135
```yaml
networks:
  traefik-net:
    external: true
  fleet-internal:
    name: ${FLEET_INTERNAL_NETWORK:-fleet-internal}
    external: true
  monitoring:
    name: ${MONITORING_NETWORK:-moltinger_monitoring}
    external: true
```

**Риск:** Если сети не существуют (например, первый deploy), деплой упадет.

**Рекомендация:**
1. Или создавать сети автоматически через `ensure_required_networks` в `deploy.sh` (уже есть!)
2. Или добавить документацию о предварительном создании сетей

---

## 4. Мелкие проблемы (P2 - Улучшения)

### 4.1 Нет мониторинга для asc-demo

**Проблема:** Prometheus scraping настроен, но нет специфичных алертов.

**Где:**
```yaml
labels:
  - "prometheus.io/scrape=true"
  - "prometheus.io/port=${ASC_DEMO_INTERNAL_PORT:-18791}"
  - "prometheus.io/path=/metrics"
```

**Рекомендация:** Добавить alert rules для asc-demo в `config/prometheus/`.

---

### 4.2 Нет graceful shutdown handling

**Проблема:** Нет обработки сигналов SIGTERM для graceful shutdown.

**Где:** `docker-compose.asc.yml` — нет `stop_grace_period` или `healthcheck` для shutdown.

---

### 4.3 Volume mounts могут иметь проблемы с правами

**Где:** Строки 58-65
```yaml
volumes:
  - type: bind
    source: .
    target: /workspace
    read_only: true
```

**Риск:** Если UID в контейнере не совпадает с хостом, могут быть проблемы с доступом.

---

## 5. Что работает хорошо ✅

### 5.1 Deploy script поддерживает asc-demo

`scripts/deploy.sh` корректно настроен для asc-demo:
- Target configuration (строки 311-332)
- Runtime paths (функция `ensure_asc_demo_runtime_paths`)
- Force recreate для перезагрузки кода (строки 652-659)

### 5.2 Traefik labels корректны

Все необходимые labels для Traefik присутствуют:
- HTTPS redirect
- Let's Encrypt TLS
- Proxy headers
- Load balancer health check

### 5.3 Security hardening

```yaml
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
```

### 5.4 Logging configuration

```yaml
logging:
  driver: json-file
  options:
    max-size: "20m"
    max-file: "5"
```

---

## 6. Рекомендуемые действия

### Immediate (P0):
1. Создать `.github/workflows/deploy-asc-demo.yml`
2. Добавить `asc-demo` target в `scripts/preflight-check.sh`
3. Документировать требуемые секреты asc-demo

### Short-term (P1):
4. Проверить `/health` endpoint в `agent-factory-web-adapter.py`
5. Добавить данные asc-demo в backup script
6. Добавить специфичные alert rules

### Long-term (P2):
7. Рассмотреть возможность использования Node.js версии (asc-demo/server.js) как отдельный сервис
8. Добавить graceful shutdown handling
9. Настроить CI/CD staging environment для asc-demo

---

## 7. Проверочный список для production

- [ ] GitHub workflow для asc-demo создан и протестирован
- [ ] Preflight-check поддерживает asc-demo target
- [ ] Все секреты добавлены в GitHub Secrets
- [ ] Health check endpoint работает корректно
- [ ] Backup script включает данные asc-demo
- [ ] Мониторинг и алерты настроены
- [ ] Документация обновлена
- [ ] Тестовый деплой выполнен успешно

---

## 8. Сравнение с другими сервисами

| Аспект | Moltis | Clawdiy | ASC-Demo |
|--------|--------|---------|----------|
| CI/CD Workflow | ✅ Есть | ✅ Есть | ❌ Нет |
| Preflight-check | ✅ Есть | ✅ Есть | ❌ Нет |
| Backup integration | ✅ Есть | ✅ Частично | ❌ Нет |
| Monitoring | ✅ Есть | ✅ Есть | ⚠️ Базовое |
| Secrets documented | ✅ Есть | ✅ Есть | ❌ Нет |
| Rollback support | ✅ Есть | ✅ Есть | ✅ Есть |

---

*Ревью составлено: 2026-03-18*
*Ревьювер: Claude Code*
*Ветка: 024-web-factory-demo-adapter*
