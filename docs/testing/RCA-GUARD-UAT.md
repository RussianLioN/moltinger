# UAT: Боевые пользовательские тесты RCA Guard

## Цель

Проверить «боевое» поведение guard-механизмов:

- `pre-push` блокирует push с `RCA-only` изменениями
- `pre-push` пропускает push, когда есть обновление инструкций
- `pre-commit`/`pre-push` учитывают session guard

## Обязательная изоляция контекста

### 1) Отдельная тестовая ветка

```bash
git checkout 001-rca-skill-upgrades
git pull --rebase
export UAT_BRANCH="test/rca-guard-uat-$(date +%Y%m%d-%H%M)"
git checkout -b "$UAT_BRANCH"
```

### 2) Отдельный тред в Codex/Claude

Создайте новый тред с заголовком:
`UAT RCA Guard: <дата-время>`

Стартовый промпт для треда:

```text
Выполняем только UAT по инструкции docs/testing/RCA-GUARD-UAT.md
в ветке $UAT_BRANCH.
Не трогаем другие задачи/файлы вне UAT.
После каждого кейса фиксируем: PASS/FAIL + фактический вывод команды.
```

## Подготовка окружения

```bash
scripts/setup-git-hooks.sh
scripts/git-session-guard.sh --refresh
git config --get core.hooksPath
```

Ожидаемо:
- `core.hooksPath` = `.githooks`
- `scripts/git-session-guard.sh --status` показывает `status=ok`

## Кейс UAT-01: Push без RCA должен пройти

```bash
mkdir -p uat
echo "uat-allow $(date -u +%FT%TZ)" > uat/01-allow-no-rca.txt
git add uat/01-allow-no-rca.txt
git commit -m "test(uat): allow push without rca files"
git push -u origin "$UAT_BRANCH"
```

Ожидаемо:
- commit успешен
- push успешен

## Кейс UAT-02: RCA-only push должен блокироваться

```bash
RCA_FILE="docs/rca/$(date +%F)-uat-rca-only.md"
cat > "$RCA_FILE" <<'EOF'
# UAT RCA-only

Проверка блокировки pre-push при изменении только RCA файла.
EOF

git add "$RCA_FILE"
git commit -m "test(uat): rca-only should be blocked"
git push
```

Ожидаемо:
- push отклонен
- в выводе есть: `incomplete RCA protocol`

## Кейс UAT-03: Добавили инструкцию — push проходит

```bash
mkdir -p docs/rules
RULE_FILE="docs/rules/$(date +%F)-uat-rca-guard.md"
cat > "$RULE_FILE" <<'EOF'
# UAT rule for RCA guard

Если в истории push есть docs/rca/*.md, в той же истории должно быть
обновление инструкций (AGENTS.md, CLAUDE.md или docs/rules/*.md).
EOF

git add "$RULE_FILE"
git commit -m "test(uat): add instruction update for rca guard"
git push
```

Ожидаемо:
- push успешен

## Кейс UAT-04 (опционально): Проверка session drift

```bash
scripts/git-session-guard.sh --refresh
git checkout -b "${UAT_BRANCH}-drift"
scripts/git-session-guard.sh --status
```

Ожидаемо:
- `status=drift` (так как branch изменился после refresh)

Вернуться:

```bash
git checkout "$UAT_BRANCH"
scripts/git-session-guard.sh --refresh
scripts/git-session-guard.sh --status
```

Ожидаемо:
- `status=ok`

## Фиксация результатов для обратной связи

Соберите в ответе:

1. PASS/FAIL по каждому кейсу (`UAT-01..UAT-03`, `UAT-04` если запускали)
2. Ключевые строки вывода ошибок/блокировок
3. Commit SHA тестовой ветки
4. Что было неочевидно в инструкции

## Завершение

Тестовую ветку не смешивать с основной разработкой.

Если ветка больше не нужна:

```bash
git checkout 001-rca-skill-upgrades
git branch -D "$UAT_BRANCH"
git push origin --delete "$UAT_BRANCH"
```
