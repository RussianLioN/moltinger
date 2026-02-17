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

*Document created: 2026-02-17*
*Last updated: 2026-02-17*
*Incident resolved: ✅ Tavily MCP working*
