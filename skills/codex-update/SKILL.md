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

## Основной runtime

Канонический entrypoint:

```bash
bash scripts/moltis-codex-update-run.sh --mode manual
```

Если нужен project profile:

```bash
bash scripts/moltis-codex-update-run.sh \
  --mode manual \
  --profile-file path/to/project-profile.json
```

## Правила ответа

- Отвечай только по-русски.
- Не отправляй пользователя к старым `repo-side` `/codex_*` flow.
- Если upstream недоступен, говори честно `нужно проверить`, а не угадывай.
- Если профиль проекта отсутствует, всё равно дай полезный общий advisory.

## Что показывать пользователю

Минимально:

1. есть ли новое upstream-состояние;
2. насколько это важно;
3. почему это важно простыми словами;
4. какие следующие шаги стоит сделать.

## Scheduler path

Для scheduler/daemon path используется тот же runtime:

```bash
bash scripts/moltis-codex-update-run.sh --mode scheduler --stdout json
```

На текущем implementation slice scheduler ещё не является production-final delivery path.
Он подготовлен как canonical Moltis-native runtime основа; duplicate suppression и delivery
закрываются следующим implementation slice.
