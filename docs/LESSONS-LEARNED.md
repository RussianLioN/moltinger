# Lessons Learned: Moltis Web Search Integration

**Date**: 2026-02-17
**Incident**: Multiple deployment failures during Tavily MCP server integration
**Duration**: ~2 hours, 7+ deployment cycles
**Resolution**: Successfully deployed with correct package name

---

## Timeline of Errors

| # | Error | Root Cause | Time Lost |
|---|-------|------------|-----------|
| 1 | MCP: 0 configured | Config not synced to server | 15 min |
| 2 | TOML parse error line 323 | Duplicate section in config | 20 min |
| 3 | uvx not found | Wrong command (not in container) | 10 min |
| 4 | npm 404 @modelcontextprotocol/server-tavily | Package doesn't exist | 15 min |
| 5 | npm 404 mcp-server-tavily | Wrong package name | 10 min |
| 6 | Success | tavily-mcp@0.1.3 from official docs | — |

---

## Expert Panel Analysis

### 1. 🏗️ Архитектор решения (Solution Architect) — КЛЮЧЕВОЕ МНЕНИЕ

**Диагноз**: Нарушение принципа "Document First, Implement Second"

```
ПРОБЛЕМА: AI-ассистент начал имплементацию без проверки официальной документации.
Модели часто "галлюцинируют" названия пакетов вместо того, чтобы искать истину.

РЕШЕНИЕ: Ввести правило "RTFM First" (Read The Friendly Manual):
1. Перед любой интеграцией — найти и прочитать официальную документацию
2. Проверить существование пакета: npm search, npm view, или веб-поиск
3. Только потом писать конфигурацию
```

**Рекомендация**: Создать чеклист "Pre-Integration Checklist" для всех новых интеграций.

---

### 2. 🐳 Senior Docker Engineer

**Диагноз**: Неполная синхронизация конфигурации в CI/CD

```yaml
# ПРОБЛЕМА: Синхронировался только docker-compose.yml
- name: Sync configuration files
  run: |
    scp docker-compose.yml $SSH_HOST:$DEPLOY_PATH/

# РЕШЕНИЕ: Синхронизировать ВСЕ конфигурационные файлы
- name: Sync configuration files
  run: |
    scp docker-compose.yml $SSH_HOST:$DEPLOY_PATH/
    ssh $SSH_HOST "mkdir -p $DEPLOY_PATH/config"
    scp -r config/* $SSH_HOST:$DEPLOY_PATH/config/
```

**Рекомендация**: Добавить валидацию конфигурации ПЕРЕД деплоем.

---

### 3. 🔧 Unix Script Expert (Мастер Bash/Zsh)

**Диагноз**: Отсутствие валидации синтаксиса конфигурационных файлов

```bash
# ПРОБЛЕМА: TOML с duplicate sections не валидировался

# РЕШЕНИЕ: Добавить pre-commit hook или CI step
validate_toml() {
    python3 -c "import tomllib; tomllib.load(open('$1', 'rb'))" && echo "✅ Valid" || exit 1
}

# Или использовать томл-линтер:
pip install toml-sort
toml-sort --check config/moltis.toml
```

**Рекомендация**: `moltis config check` должен запускаться локально И в CI.

---

### 4. 🚀 DevOps Engineer (Automation & Deployment)

**Диагноз**: Отсутствие smoke test для MCP servers

```bash
# ПРОБЛЕМА: Деплой считался успешным, но MCP не работал

# РЕШЕНИЕ: Добавить MCP health check в smoke tests
verify_mcp_servers() {
    curl -s http://localhost:13131/api/mcp/servers | jq '.[] | select(.status != "running")' && exit 1
    echo "✅ All MCP servers running"
}
```

**Рекомендация**: Smoke tests должны проверять не только HTTP 200, но и функциональность.

---

### 5. 🔄 CI/CD Architect (Pipeline Design)

**Диагноз**: Missing validation gate before deployment

```yaml
# ПРОБЛЕМА: Невалидный конфиг уходил на сервер

# РЕШЕНИЕ: Добавить validation stage
stages:
  - validate    # NEW: Syntax + schema validation
  - build
  - deploy

validate:
  script:
    - python3 -c "import tomllib; tomllib.load(open('config/moltis.toml', 'rb'))"
    - moltis config check --config-dir ./config 2>/dev/null || echo "Moltis not installed, skipping"
```

**Рекомендация**: Fail fast — валидация на этапе PR, не на production.

---

### 6. 📋 GitOps Specialist (GitOps 2.0 Architecture)

**Диагноз**: Configuration drift между git и сервером

```
ПРОБЛЕМА: На сервере был старый конфиг без MCP section.
CI/CD не гарантировал идентичность git ↔ server.

РЕШЕНИЕ: Добавить GitOps compliance check:
1. После деплоя — скачать конфиг с сервера
2. Сравнить с git версией
3. Различия = FAIL с diff output
```

**Рекомендация**: Periodic reconciliation job (cron) для детекции drift.

---

### 7. 🏔️ Infrastructure as Code Expert (IaC Best Practices)

**Диагноз**: No state management for configuration

```
ПРОБЛЕМА: Конфиг — это "unmanaged file", не part of IaC.

РЕШЕНИЕ: Рассмотреть подходы:
1. Конфиг генерируется из шаблонов (Jinja2/Helm)
2. Секреты инжектятся при генерации
3. Финальный конфиг верифицируется схемой
```

**Рекомендация**: JSON Schema для moltis.toml валидации.

---

### 8. 💾 Backup & Disaster Recovery Specialist

**Диагноз**:Backup создаётся, но не верифицируется

```bash
# ПРОБЛЕМА: Бэкап есть, но мы не проверили:
# - Можно ли из него восстановиться?
# - Валиден ли TOML внутри?

# РЕШЕНИЕ: Добавить backup verification
verify_backup() {
    tar -tzf $BACKUP_FILE | grep -q "moltis.toml" || exit 1
    tar -xzf $BACKUP_FILE -O config/moltis.toml | python3 -c "import sys,tomllib; tomllib.load(sys.stdin.buffer)"
}
```

**Рекомендация**: Еженедельный restore drill в staging.

---

### 9. 📊 SRE (Site Reliability Engineer)

**Диагноз**: Missing SLO for deployment success

```
ПРОБЛЕМА: 7 деплоев для одной фичи — это 6too many.
SLO: 95% деплоев должны быть successful с первого раза.

METRICS:
- deployment_attempts_per_change: 7 (target: 1)
- mean_time_to_recovery: ~10 min (acceptable)
- change_failure_rate: 85% (target: <5%)
```

**Рекомендация**: Добавить deployment metrics dashboard.

---

### 10. 🤖 Эксперт по AI IDE (Claude Code и др.)

**Диагноз**: AI не использует доступные инструменты для верификации

```
ПРОБЛЕМА: AI "угадывал" названия пакетов вместо:
1. WebSearch/npm search
2. Чтения официальной документации
3. Проверки существования пакета

ROOT CAUSE: Нет явной инструкции "verify before implement"

РЕШЕНИЕ: Добавить в CLAUDE.md правило:
```

```markdown
## Pre-Integration Checklist (MANDATORY)

Before adding ANY external dependency/integration:

1. [ ] Find official documentation URL
2. [ ] Read installation section completely
3. [ ] Verify package exists: `npm view <package>` or `pip show <package>`
4. [ ] Check version: prefer explicit version over `@latest`
5. [ ] Document source URL in config comments
```

---

### 11. 🎯 Промпт инженер высшего уровня

**Диагноз**: Промпт не содержал инструкции "verify external references"

```
ПРОБЛЕМА: Модель получила задачу "добавить Tavily" без контекста:
- Какой пакет?
- Какая версия?
- Где документация?

IMPROVED PROMPT:
"Добавь Tavily MCP server для web search:
1. Найди официальную документацию Tavily MCP
2. Проверь точное название npm пакета
3. Укажи версию в конфигурации
4. Добавь ссылку на документацию в комментарий"
```

**Рекомендация**: Всегда требовать source URL для внешних интеграций.

---

### 12. 🧪 Test-Driven Development Expert

**Диагноз**: No test for MCP integration before implementation

```
ПРОБЛЕМА: Реализация → Деплой → Ошибка → Повторить
ДОЛЖНО БЫТЬ: Тест → Реализация → Деплой → Успех

# Test first:
def test_tavily_mcp_package_exists():
    result = subprocess.run(["npm", "view", "tavily-mcp", "version"], capture_output=True)
    assert result.returncode == 0, "Package tavily-mcp not found in npm"
```

**Рекомендация**: Integration tests для всех MCP servers.

---

### 13. ✅ User Acceptance Testing Engineer

**Диагноз**: No UAT checklist for deployment verification

```
ПРОБЛЕМА: "Деплой успешен" ≠ "Функциональность работает"

UAT CHECKLIST:
[ ] MCP server status: running
[ ] MCP tools count: expected
[ ] Search query returns results
[ ] No errors in logs after 5 min
```

**Рекомендация**: UAT gate перед закрытием тикета.

---

## Action Items

### Immediate (P0)

| # | Action | Owner | Status |
|---|--------|-------|--------|
| 1 | Add config/ sync to CI/CD workflow | DevOps | ✅ DONE |
| 2 | Add TOML validation step | CI/CD | 📋 TODO |
| 3 | Update CLAUDE.md with Pre-Integration Checklist | Prompt Eng | 📋 TODO |

### Short-term (P1)

| # | Action | Owner | Status |
|---|--------|-------|--------|
| 4 | Add MCP health check to smoke tests | SRE | 📋 TODO |
| 5 | Create JSON Schema for moltis.toml | IaC | 📋 TODO |
| 6 | Add deployment metrics | SRE | 📋 TODO |

### Long-term (P2)

| # | Action | Owner | Status |
|---|--------|-------|--------|
| 7 | Periodic GitOps reconciliation | GitOps | 📋 TODO |
| 8 | Weekly backup restore drill | DR | 📋 TODO |
| 9 | Integration tests for MCP servers | TDD | 📋 TODO |

---

## Key Principles Established

1. **RTFM First** — Always read official documentation before implementation
2. **Verify Package Exists** — `npm view` or `pip show` before adding to config
3. **Explicit Versions** — Pin package versions, avoid `@latest`
4. **Document Sources** — Add URL to docs in config comments
5. **Validate Before Deploy** — Syntax check in CI, not on production
6. **Test Functional** — HTTP 200 ≠ feature works

---

## Quick Reference Card

```
╔══════════════════════════════════════════════════════════════╗
║           PRE-INTEGRATION CHECKLIST (MANDATORY)              ║
╠══════════════════════════════════════════════════════════════╣
║ 1. [ ] Find official documentation URL                        ║
║ 2. [ ] Read installation section completely                   ║
║ 3. [ ] Verify: npm view <package> || pip show <package>       ║
║ 4. [ ] Pin version: package@1.2.3 (not @latest)               ║
║ 5. [ ] Add docs URL to config comment                         ║
║ 6. [ ] Validate config syntax before commit                   ║
╚══════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════════════╗
║        PRE-DEPLOY-CONFIG CHANGE CHECKLIST (Incident #003)                 ║
╠═══════════════════════════════════════════════════════════════════════════╣
║ 1. [ ] Read SESSION_SUMMARY.md — How do secrets work?                    ║
║ 2. [ ] Check server: nproc, free -h, docker network ls, docker images    ║
║ 3. [ ] Read existing workflow — What files are synced?                   ║
║ 4. [ ] Check .env on server — What variables exist?                      ║
║ 5. [ ] Compare with GitHub Secrets: gh secret list                       ║
║ 6. [ ] ONLY THEN make changes                                            ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

## Files Modified During Incident

| File | Change | Commit |
|------|--------|--------|
| `.github/workflows/deploy.yml` | +6 lines (config sync) | 9595de9 |
| `config/moltis.toml` | -6 lines (remove duplicate) | fc4c5b7 |
| `config/moltis.toml` | 2 edits (package name) | dbc31b2, b68bb7e |
| `docs/LESSONS-LEARNED.md` | NEW FILE | — |

---

---

## Incident #002: GitOps Violation - scp Upload (2026-02-27)

**Ситуация**:
Claude Code загрузил скрипт на сервер через `scp` вместо git push.

```bash
# ❌ НЕПРАВИЛЬНО (сделано):
scp /tmp/test-moltis-api.sh root@ainetic.tech:/opt/moltinger/scripts/

# ✅ ПРАВИЛЬНО (надо было):
mv /tmp/test-moltis-api.sh scripts/
git add scripts/test-moltis-api.sh
git commit -m "feat: add Moltis API test script"
git push  # → CI/CD деплоит на сервер
```

**Почему это нарушение**:
- Нет audit trail (кто, когда, зачем)
- Bypass CI/CD validation
- Server state ≠ git state (configuration drift)
- Невозможен автоматический rollback

**Root Cause**:
Claude Code "забыл" о GitOps принципах в момент реализации.

**Prevention (внедрено)**:
1. Добавить в MEMORY.md явное напоминание
2. Перед любой командой ssh/scp — проверять: "Это в git?"

---

### Pre-Flight Check для ssh/scp

```
┌─────────────────────────────────────────────────────────────┐
│                    PRE-FLIGHT CHECK                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Хочу выполнить: ssh/scp команду                            │
│                     │                                        │
│                     ▼                                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Вопрос: Файл уже в git?                              │   │
│  └─────────────────────────────────────────────────────┘   │
│                     │                                        │
│         ┌───────────┴───────────┐                          │
│         ▼                       ▼                          │
│        ДА                      НЕТ                          │
│         │                       │                          │
│         ▼                       ▼                          │
│  Push → CI/CD            Сначала git add/commit            │
│  (автодеплой)            Потом push → CI/CD                │
│                                                             │
│  ⛔ НИКОГДА: scp/ssh для изменения файлов                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Разрешённые ssh операции

| Действие | Разрешено? | Почему |
|----------|------------|--------|
| `ssh server "docker logs"` | ✅ Да | Read-only, не меняет state |
| `ssh server "cat file"` | ✅ Да | Read-only |
| `ssh server "rm file"` | ❌ НЕТ | Меняет state → через git |
| `scp file server:/path/` | ❌ НЕТ | Меняет state → через git |
| `ssh server "git pull"` | ✅ Да | GitOps-compliant |

---

## Incident #003: Self-Inflicted CI/CD Failures (2026-03-02)

**Ситуация**:
~15 CI/CD запусков для деплоя OLLAMA_API_KEY, большинство failed из-за ошибок, созданных самим AI-ассистентом.

**Duration**: ~2.5 часа
**Root Cause**: Нарушение принципа "Understand Before Change" — изменения без понимания существующей архитектуры.

---

### Timeline of Errors

| # | Error | Root Cause | Category |
|---|-------|------------|----------|
| 1 | Shellcheck `-S style` показывал warnings | Неправильный флаг (надо `-S error`) | Syntax |
| 2 | `new-lines: expected \n` | CRLF вместо LF в docker-compose.prod.yml | Encoding |
| 3 | `MOLTIS_NO_TLS contains true, invalid type` | Boolean вместо string в YAML | Typing |
| 4 | `TELEGRAM_ALLOWED_USERS variable is not set` | Нет default value (`${VAR:-}`) | Config |
| 5 | `manifest unknown` для v1.7.0/latest | Тег не существует удалённо | Registry |
| 6 | `secret file does not exist` | File secrets вместо env vars | Architecture |
| 7 | docker-compose.prod.yml не sync | Workflow sync только .yml, не .prod.yml | CI/CD |
| 8 | `docker compose` без `-f` флага | Использовался не тот compose файл | CI/CD |
| 9 | `network traefik_proxy not found` | External сеть не создана | Infrastructure |
| 10 | `CPUs from 0.01 to 2.00` | Limits 4 CPU > server 2 CPU | Resources |

---

### Root Cause Analysis

#### 🔴 КРИТИЧЕСКАЯ ОШИБКА: Не прочитал существующую архитектуру

```
ПРОБЛЕМА: AI начал менять docker-compose.prod.yml (добавил file secrets)
не проверив, как УЖЕ работают секреты в проекте.

ФАКТ: Проект использует GitHub Secrets → .env → docker compose
ПРЕДПОЛОЖЕНИЕ AI: Нужно Docker file secrets

РЕЗУЛЬТАТ: Создал конфигурацию, которая противоречила существующему подходу.
```

#### 🔴 КАСКАДНЫЕ ОШИБКИ: Одно изменение сломало другое

```
Change 1: Добавил secrets section → Требует файлы в ./secrets/
Change 2: Не создал файлы → Deploy failed
Change 3: Убрал secrets → Но файл на сервере старый
Change 4: Workflow sync только docker-compose.yml → prod.yml устарел
Change 5: Deploy использует docker compose без -f → Берёт .yml не .prod.yml
```

---

### Expert Panel Analysis

#### 1. 🏗️ Solution Architect

**Диагноз**: Нарушение принципа "Read Before Write"

```
ПРОБЛЕМА: Изменения вносились без чтения:
- SESSION_SUMMARY.md (как работают секреты?)
- Существующего workflow (как происходит sync?)
- Сервера (какие ресурсы? какие сети?)

ПРАВИЛО: Перед ЛЮБЫМИ изменениями deploy конфигурации:
1. Прочитать SESSION_SUMMARY.md
2. Проверить сервер: docker images, docker network ls, nproc
3. Прочитать существующий workflow
4. Только потом вносить изменения
```

#### 2. 🔐 Security Architect

**Диагноз**: Неправильный выбор механизма секретов

```
ПРОБЛЕМА: Docker file secrets требуют:
- Файлы на сервере в ./secrets/
- Ручное управление файлами
- Нет audit trail

СУЩЕСТВУЮЩИЙ ПОДХОД (правильный):
- GitHub Secrets (зашифрованы)
- CI/CD генерирует .env из secrets
- docker compose читает ${VAR} из .env
- Audit trail в GitHub Actions logs

УРОК: Всегда проверять существующий подход к секретам ПЕРЕД изменениями
```

#### 3. 🐳 Docker Compose Expert

**Диагноз**: Неполная синхронизация конфигурации

```yaml
# ПРОБЛЕМА: Workflow синхронизировал только один файл
- name: Sync configuration files
  run: |
    scp docker-compose.yml server:/path/  # ✅
    # docker-compose.prod.yml ЗАБЫЛИ!     # ❌

# РЕШЕНИЕ: Синхронизировать ВСЕ compose файлы
- name: Sync configuration files
  run: |
    scp docker-compose.yml server:/path/
    scp docker-compose.prod.yml server:/path/  # ✅ Added
```

#### 4. ⚙️ DevOps Engineer

**Диагноз**: Deploy step не указывает правильный compose файл

```bash
# ПРОБЛЕМА: docker compose без -f использует docker-compose.yml
docker compose up -d moltis

# РЕШЕНИЕ: Явно указывать production config
docker compose -f docker-compose.prod.yml up -d moltis
```

#### 5. 🖥️ Infrastructure Engineer

**Диагноз**: Не проверены ресурсы сервера

```bash
# ПРОБЛЕМА: Config требует 4 CPUs, сервер имеет 2
deploy:
  resources:
    limits:
      cpus: '4'  # ❌ Server has only 2!

# ПРОВЕРКА ПЕРЕД ИЗМЕНЕНИЕМ:
ssh server "nproc"  # Should be first step!
```

#### 6. 🌐 Network Engineer

**Диагноз**: External сеть не создана

```yaml
# docker-compose.prod.yml объявляет external сеть
networks:
  traefik_proxy:
    external: true  # Должна существовать!

# ПРОВЕРКА И СОЗДАНИЕ:
ssh server "docker network create traefik_proxy"
```

---

### 📋 Pre-Implementation Checklist (UPDATED)

```
╔═══════════════════════════════════════════════════════════════════════════╗
║        PRE-DEPLOY-CONFIGURATION CHANGE CHECKLIST (MANDATORY)              ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║ 1. [ ] Прочитать SESSION_SUMMARY.md — как работают секреты?               ║
║ 2. [ ] Проверить сервер:                                                  ║
║       - docker images | grep moltis (какой tag?)                          ║
║       - docker network ls (какие сети?)                                   ║
║       - nproc (сколько CPU?)                                              ║
║       - free -h (сколько памяти?)                                         ║
║ 3. [ ] Прочитать существующий workflow — что sync'ится?                   ║
║ 4. [ ] Проверить .env на сервере — какие переменные есть?                 ║
║ 5. [ ] Сравнить с GitHub Secrets: gh secret list                          ║
║ 6. [ ] Только ПОСЛЕ этого вносить изменения                               ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

### 📊 Metrics

| Metric | This Session | Target |
|--------|--------------|--------|
| CI/CD attempts | ~15 | 1 |
| Time to success | ~2.5 hours | <10 min |
| Self-inflicted errors | 10 | 0 |
| SSH rate limits hit | 3+ | 0 |
| Root cause analysis depth | High | - |

---

### 🛡️ Prevention Rules (NEW)

#### Rule #1: Read Before Change
```markdown
## Before modifying ANY deployment configuration:

1. Read SESSION_SUMMARY.md (how do secrets work?)
2. Check server resources (CPU, memory, networks)
3. Read existing workflow (what gets synced?)
4. Verify against GitHub Secrets
```

#### Rule #2: Verify File Sync
```markdown
## When adding new config files:

1. Add to git (git add, git commit)
2. Add to CI/CD sync step (scp to server)
3. Verify in workflow that ALL needed files are synced
```

#### Rule #3: Resource Limits Reality Check
```markdown
## Before setting resource limits:

ssh server "nproc && free -h"
# Then set limits to 50-75% of available resources
```

#### Rule #4: Compose File Consistency
```markdown
## When using multiple compose files:

1. ALL compose files must be synced
2. ALL docker compose commands must use -f flag
3. Validation must check the SAME file as deploy
```

---

### Files Modified During Incident

| File | Change | Reason |
|------|--------|--------|
| `.github/workflows/deploy.yml` | +20 lines | Sync prod.yml, use -f flag |
| `docker-compose.prod.yml` | -26 lines | Remove file secrets, adjust CPU |
| `docker-compose.yml` | Boolean→string | YAML typing fix |
| `docs/LESSONS-LEARNED.md` | +150 lines | This retrospective |

---

### ✅ Resolution

После исправления всех 10 ошибок:
- Deploy to Production: **SUCCESS**
- Moltis container: **Running, Healthy**
- Health check: **200 OK**

---

*Document created: 2026-02-17*
*Last updated: 2026-03-02*
*Incident resolved: ✅ Tavily MCP working*
*New incident added: ⚠️ GitOps violation documented*
*New incident added: 🔴 Self-inflicted CI/CD failures documented*
