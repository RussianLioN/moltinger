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
| **Git Topology Registry** | docs/GIT-TOPOLOGY-REGISTRY.md | Generated snapshot актуальных worktree, веток и cleanup-контекста |

---

## Git Topology Registry

```bash
# Короткая команда-обёртка
/git-topology

# Проверить, что registry не устарел
scripts/git-topology-registry.sh check

# Обновить committed snapshot после topology mutation
scripts/git-topology-registry.sh refresh --write-doc

# Посмотреть текущее состояние без записи файлов
scripts/git-topology-registry.sh status
```

Использовать перед cleanup worktree/branch и после create/remove/switch flow.

### Как пользоваться

**Обычный сценарий**
1. Создавайте и убирайте worktree через `/worktree`
2. Перед handoff или cleanup запускайте `/git-topology check`
3. Если topology менялась через managed flow, registry обычно обновится сам
4. Если topology менялась вручную через raw `git`, запускайте recovery flow

**Recovery flow после ручных git-операций**
```bash
# Построить recovery draft без изменения committed registry
scripts/git-topology-registry.sh doctor --prune

# Посмотреть draft
cat .git/topology-registry/registry.draft.md

# Если draft корректен, применить reconcile
scripts/git-topology-registry.sh doctor --prune --write-doc
```

**Где хранить ручные пометки**
- Редактировать только `docs/GIT-TOPOLOGY-INTENT.yaml`
- Не редактировать вручную `docs/GIT-TOPOLOGY-REGISTRY.md`

### Что происходит автоматически

- `/worktree start` и `/worktree cleanup` обновляют registry после topology mutation
- `/session-summary` использует registry как session-boundary reconcile point
- `pre-push` блокирует push, если registry stale
- `post-checkout`, `post-merge`, `post-rewrite` ничего молча не переписывают, только сигналят о stale-state

### Что под капотом

- Источник правды: live `git`, а не markdown
- Скрипт читает:
  - `git worktree list --porcelain`
  - `git for-each-ref ... refs/heads`
  - `git for-each-ref ... refs/remotes/origin`
- Потом он:
  - нормализует worktree/branch topology
  - подмешивает reviewed intent из `docs/GIT-TOPOLOGY-INTENT.yaml`
  - рендерит deterministic snapshot в `docs/GIT-TOPOLOGY-REGISTRY.md`
- Recovery artifacts живут в `.git/topology-registry/`:
  - `registry.draft.md`
  - `backups/`

### Полезные ссылки

- User/merge handoff: `specs/006-git-topology-registry/quickstart.md`
- Live committed registry: `docs/GIT-TOPOLOGY-REGISTRY.md`
- Reviewed intent sidecar: `docs/GIT-TOPOLOGY-INTENT.yaml`

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
