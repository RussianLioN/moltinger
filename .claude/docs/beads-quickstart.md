# Beads — Краткий справочник

> **Attribution**: [Beads](https://github.com/steveyegge/beads) — методология [Steve Yegge](https://github.com/steveyegge)

> **Moltinger repo note**: для repo-local Beads команд используй `./scripts/bd-local.sh`, чтобы текущий worktree не проваливался обратно в canonical root tracker.

---

## SESSION CLOSE PROTOCOL (ОБЯЗАТЕЛЬНО!)

**НИКОГДА не говори "готово" без выполнения этих шагов:**

```bash
git status              # 1. Что изменилось?
git add <files>         # 2. Добавить код
./scripts/bd-local.sh sync  # 3. Sync beads
git commit -m "... (PREFIX-xxx)"  # 4. Коммит с ID issue
./scripts/bd-local.sh sync  # 5. Sync новые изменения
git push                # 6. Push в remote
```

**Работа НЕ завершена пока не сделан push!**

---

## Когда что использовать

| Сценарий | Инструмент | Команда |
|----------|------------|---------|
| Большая фича (>1 день) | Spec-kit → Beads | `/speckit.specify` → `/speckit.tobeads` |
| Маленькая фича (<1 день) | Beads | `./scripts/bd-local.sh create -t feature` |
| Баг | Beads | `./scripts/bd-local.sh create -t bug` |
| Tech debt | Beads | `./scripts/bd-local.sh create -t chore` |
| Исследование/spike | Beads formula | `bd mol wisp exploration` |
| Hotfix (срочно!) | Beads formula | `bd mol wisp hotfix` |
| Health check | Workflow | `bd mol wisp healthcheck` |
| Релиз | Workflow | `bd mol wisp release` |

---

## Сессия работы

```bash
# === СТАРТ ===
./scripts/bd-local.sh prime                    # Восстановить контекст
./scripts/bd-local.sh ready                    # Что доступно для работы?

# === РАБОТА ===
./scripts/bd-local.sh update ID --status in_progress   # Взять задачу
# ... делаем работу ...
./scripts/bd-local.sh close ID --reason "Описание"     # Закрыть задачу
/push patch                         # Коммит

# === КОНЕЦ (ОБЯЗАТЕЛЬНО) ===
./scripts/bd-local.sh sync                     # Синхронизация перед выходом
```

---

## Создание задач

### Базовая команда
```bash
./scripts/bd-local.sh create "Заголовок" -t тип -p приоритет -d "описание"
```

### Типы (-t)
| Тип | Когда |
|-----|-------|
| `feature` | Новая функциональность |
| `bug` | Исправление бага |
| `chore` | Tech debt, рефакторинг |
| `docs` | Документация |
| `test` | Тесты |
| `epic` | Группа связанных задач |

### Приоритеты (-p)
| P | Значение |
|---|----------|
| 0 | Критический — блокирует релиз |
| 1 | Критический |
| 2 | Высокий |
| 3 | Средний (по умолчанию) |
| 4 | Низкий / бэклог |

### Примеры
```bash
# Простая задача
./scripts/bd-local.sh create "Добавить кнопку logout" -t feature -p 3

# С описанием
./scripts/bd-local.sh create "DEBT-001: Рефакторинг" -t chore -p 2 -d "Подробнее..."

# Баг с ссылкой на источник
./scripts/bd-local.sh create "Кнопка не работает" -t bug -p 1 --deps discovered-from:PREFIX-abc
```

---

## Зависимости

```bash
# При создании
./scripts/bd-local.sh create "Задача" -t feature --deps ТИП:ID

# Добавить к существующей
bd dep add ISSUE DEPENDS_ON
```

| Тип зависимости | Значение |
|-----------------|----------|
| `blocks:X` | Эта задача блокирует X |
| `blocked-by:X` | Эта задача заблокирована X |
| `discovered-from:X` | Найдена при работе над X |
| `parent:X` | Дочерняя задача для epic X |

---

## Epic и иерархия

```bash
# Создать epic
./scripts/bd-local.sh create "User Authentication" -t epic -p 2

# Добавить дочерние задачи
./scripts/bd-local.sh create "Login form" -t feature --deps parent:PREFIX-epic-id
./scripts/bd-local.sh create "JWT tokens" -t feature --deps parent:PREFIX-epic-id

# Посмотреть структуру
./scripts/bd-local.sh show PREFIX-epic-id --tree
```

---

## Формулы (Workflows)

### Доступные формулы
```bash
bd formula list
```

| Formula | Назначение |
|---------|------------|
| `bigfeature` | Spec-kit → Beads для больших фич |
| `bugfix` | Стандартный процесс исправления |
| `hotfix` | Экстренное исправление |
| `techdebt` | Работа с техническим долгом |
| `healthcheck` | Аудит здоровья кодовой базы |
| `codereview` | Код-ревью с созданием issues |
| `release` | Процесс релиза версии |
| `exploration` | Исследование/spike |

### Запуск
```bash
# Эфемерный (wisp)
bd mol wisp exploration --vars "question=Как сделать X?"

# Постоянный (pour)
bd mol pour bigfeature --vars "feature_name=auth"
```

### Завершение wisp
```bash
bd mol squash WISP_ID  # Сохранить результат
bd mol burn WISP_ID    # Удалить без следа
```

---

## Exclusive Lock (multi-session)

```bash
# Терминал 1: захватил lock
./scripts/bd-local.sh update PREFIX-abc --status in_progress

# Терминал 2: найти незалоченные
./scripts/bd-local.sh list --unlocked
```

---

## Emergent work

```bash
# Нашёл баг во время работы
./scripts/bd-local.sh create "Найден баг: ..." -t bug --deps discovered-from:PREFIX-current

# Понял что нужна ещё одна задача
./scripts/bd-local.sh create "Также нужно..." -t feature --deps blocks:PREFIX-current
```

---

## Поиск и фильтрация

```bash
./scripts/bd-local.sh ready                    # Готовые к работе
./scripts/bd-local.sh list                     # Все открытые
./scripts/bd-local.sh list --all               # Включая закрытые
./scripts/bd-local.sh list -t bug              # Только баги
./scripts/bd-local.sh list -p 1                # Только P1
./scripts/bd-local.sh show ID                  # Детали задачи
./scripts/bd-local.sh show ID --tree           # С иерархией
```

---

## Управление задачами

```bash
# Изменить статус
./scripts/bd-local.sh update ID --status in_progress
./scripts/bd-local.sh update ID --status blocked
./scripts/bd-local.sh update ID --status open

# Изменить приоритет
./scripts/bd-local.sh update ID --priority 1

# Добавить метку
./scripts/bd-local.sh update ID --add-label security

# Закрыть
./scripts/bd-local.sh close ID --reason "Готово"
./scripts/bd-local.sh close ID1 ID2 ID3 --reason "Batch done"
```

---

## Диагностика

```bash
./scripts/bd-local.sh doctor     # Проверка здоровья
./scripts/bd-local.sh info       # Статус проекта
./scripts/bd-local.sh prime      # Контекст workflow
```

---

## Шпаргалка

```
┌──────────────────────────────────────────────────┐
│ СТАРТ     ./scripts/bd-local.sh prime / ready    │
│ ВЗЯТЬ     ./scripts/bd-local.sh update ID ...    │
│ СОЗДАТЬ   ./scripts/bd-local.sh create "..."     │
│ ЗАКРЫТЬ   ./scripts/bd-local.sh close ID ...     │
├──────────────────────────────────────────────────┤
│ КОНЕЦ СЕССИИ (ВСЕ 6 ШАГОВ!)                      │
│   1. git status                                  │
│   2. git add <files>                             │
│   3. ./scripts/bd-local.sh sync                  │
│   4. git commit -m "... (PREFIX-xxx)"            │
│   5. ./scripts/bd-local.sh sync                  │
│   6. git push                                    │
├──────────────────────────────────────────────────┤
│ WORKFLOWS bd formula list                        │
│           bd mol wisp NAME --vars "k=v"          │
│           bd mol squash/burn WISP_ID             │
└──────────────────────────────────────────────────┘
```

---

## Ссылки

- [Beads GitHub](https://github.com/steveyegge/beads)
- [CLI Reference](https://github.com/steveyegge/beads/blob/main/docs/CLI_REFERENCE.md)
- [Molecules Guide](https://github.com/steveyegge/beads/blob/main/docs/MOLECULES.md)

---

*Beads — методология Steve Yegge. Адаптировано для Claude Code Orchestrator Kit.*
