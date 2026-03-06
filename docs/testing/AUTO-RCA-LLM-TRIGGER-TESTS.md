# UAT: Auto-RCA Trigger Tests (LLM Mistake/Self-Reflection)

## Цель

Проверить, что RCA-протокол запускается автоматически и начинается саморефлексия, когда:

1. возникает ошибка выполнения команды (`exit code != 0`)
2. пользователь явно сообщает об ошибке понимания

Тестируем через runtime-обертку:
`scripts/auto-rca-wrapper.sh`

## Изоляция контекста (обязательно)

```bash
cd /Users/rl/coding/moltinger
git checkout 001-rca-skill-upgrades
git pull --rebase
export UAT_BRANCH="test/auto-rca-trigger-$(date +%Y%m%d-%H%M)"
git checkout -b "$UAT_BRANCH"
scripts/setup-git-hooks.sh
scripts/git-session-guard.sh --refresh
```

Далее откройте **новый тред** и в первом сообщении зафиксируйте:

```text
Контекст UAT: branch=$UAT_BRANCH, цель=проверка AUTO-RCA, scope=только этот тест.
```

## Критерии успеха

После триггера ответ агента должен содержать блок:

```text
AUTO-RCA TRIGGERED
Trigger: ...
Symptom: ...
Q1 Why: ...
Q2 Why: ...
Q3 Why: ...
Q4 Why: ...
Q5 Why: ...
Root cause: ...
Immediate fix: ...
Preventive fix: ...
RCA artifact: docs/rca/YYYY-MM-DD-<topic>.md
```

## Тест-кейсы

## TRG-01: Гарантированный `exit code != 0`

Отправьте в новый тред:

```text
Выполни в терминале:
scripts/auto-rca-wrapper.sh -- false
```

Ожидаемо:
- агент фиксирует ошибку выполнения
- немедленно запускает AUTO-RCA блок

## TRG-02: Ошибка из-за отсутствующего файла

Отправьте:

```text
Выполни буквально эту команду и покажи результат:
scripts/auto-rca-wrapper.sh -- sed -n '1,20p' /tmp/definitely-missing-auto-rca-file.txt
```

Ожидаемо:
- команда падает
- запускается AUTO-RCA блок

## TRG-02b: Эскалация в L2 (полный RCA)

```text
Выполни в терминале:
scripts/auto-rca-wrapper.sh --always-full -- false
```

Ожидаемо:
- AUTO-RCA с `Mode: L2`
- создан файл в `docs/rca/YYYY-MM-DD-auto-rca-*.md`

## TRG-03: Триггер по пользовательской обратной связи

Шаг 1 (любой короткий запрос):

```text
Проверь текущую ветку и напиши ее имя.
```

Шаг 2 (сразу следующим сообщением):

```text
Ты не понял задачу, это ошибка. Запусти AUTO-RCA сейчас.
```

Ожидаемо:
- AUTO-RCA запускается даже без shell-ошибки
- Trigger указывает на пользовательский сигнал об ошибке понимания

## Что вернуть после теста

Сформируйте обратную связь:

1. `TRG-01`: PASS/FAIL + ключевая строка вывода
2. `TRG-02`: PASS/FAIL + ключевая строка вывода
3. `TRG-03`: PASS/FAIL + ключевая строка вывода
4. Путь к созданному RCA-артефакту (если создан)
5. Где формат саморефлексии не сработал/сработал не полностью

## Завершение тестовой ветки

```bash
git checkout 001-rca-skill-upgrades
git branch -D "$UAT_BRANCH"
```

Если ветка уже была опубликована:

```bash
git push origin --delete "$UAT_BRANCH"
```
