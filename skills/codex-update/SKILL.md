---
name: codex-update
description: Полностью Moltis-native навык для проверки обновлений Codex CLI.
  Использовать, когда пользователь просит простым текстом проверить новые версии,
  понять их важность и получить рекомендации на русском.
---

# Codex Update

## Когда использовать

Используй этот skill, когда пользователь пишет что-то вроде:

- `Проверь обновления Codex CLI`
- `Есть ли новые версии Codex CLI?`
- `Что нового в Codex CLI и насколько это важно?`
- `Нужны ли нам действия из-за новых версий Codex CLI?`

## Цель

Этот skill делает Moltis каноническим владельцем сценария:

1. читает официальный changelog Codex CLI;
2. по желанию дополняет контекст issue signals;
3. сравнивает новое состояние с уже увиденным fingerprint;
4. отвечает пользователю по-русски;
5. при наличии project profile уточняет рекомендации для конкретного проекта.

## Канонический порядок действий

Когда этот skill срабатывает по обычному пользовательскому запросу:

1. Сразу запускай канонический runtime:

```bash
bash /server/scripts/moltis-codex-update-run.sh --mode manual --stdout summary
```

2. Если нужен project profile, добавляй `--profile-file ...`.
3. Строй ответ по summary этого runtime, а не по отдельным ad-hoc shell-проверкам.

## Что делать нельзя

- Не запускай `npm list -g @openai/codex` для этого навыка.
- Не запускай `codex --version` для этого навыка.
- Не проверяй локально установленный Codex CLI, если пользователь не попросил именно про локальную установку.
- Не подменяй канонический runtime старым repo-side watcher/advisor flow.

Простое правило:

- `Проверь обновления Codex CLI` => сразу `moltis-codex-update-run.sh`
- `Какая у меня локальная версия Codex CLI?` => отдельный локальный сценарий

## Основной runtime

Канонический операторский entrypoint:

```bash
make codex-update
```

Прямой runtime entrypoint:

```bash
bash /server/scripts/moltis-codex-update-run.sh --mode manual
```

Если нужен project profile:

```bash
bash /server/scripts/moltis-codex-update-run.sh \
  --mode manual \
  --profile-file path/to/project-profile.json
```

## Правила ответа

- Отвечай только по-русски.
- Не отправляй пользователя к старым `repo-side` `/codex_*` flow.
- Для обычного запроса про обновления сразу используй канонический runtime этого skill, а не промежуточные shell-пробы.
- Если upstream недоступен, говори честно `нужно проверить`, а не угадывай.
- Если профиль проекта отсутствует, всё равно дай полезный общий advisory.
- Не отправляй пользователя к legacy migration-only target-ам, если достаточно `make codex-update`.

## Что показывать пользователю

Минимально:

1. есть ли новое upstream-состояние;
2. насколько это важно;
3. почему это важно простыми словами;
4. какие следующие шаги стоит сделать.

## Scheduler path

Для scheduler/daemon path используется тот же runtime:

```bash
bash /server/scripts/moltis-codex-update-run.sh --mode scheduler --stdout json
```

Scheduler уже умеет:

- проверять upstream по расписанию;
- подавлять дубль по тому же fingerprint;
- отправлять одно Telegram-уведомление для нового состояния;
- писать state и audit trail.

Для hermetic proof полного пути используй:

```bash
make codex-update-e2e
```
