---
name: codex-update
description: Remote-safe Moltis skill for Codex CLI update status. Use when a
  user asks about new Codex versions, their importance, or recommended next
  steps in Russian.
---

# Codex Update

## Когда использовать

Используй этот skill, когда пользователь пишет что-то вроде:

- `Проверь обновления Codex CLI`
- `Есть ли новые версии Codex CLI?`
- `Что нового в Codex CLI и насколько это важно?`
- `Что умеет codex-update?`
- `Какая последняя версия Codex CLI у тебя зафиксирована?`
- `Что сейчас лежит в state/fingerprint codex-update?`

Подробный runtime/runbook-контракт описан в `docs/moltis-codex-update-skill.md`.

## Главное правило: сначала определи surface

### 1. Remote user-facing surface

Это Telegram, DM или другая sandboxed user-facing сессия, где `/server`, host paths и writable runtime state не доказаны явно.

На такой surface:

- считай `codex-update` advisory/notification-only capability;
- не запускай `make codex-update`, `bash /server/scripts/moltis-codex-update-run.sh` и похожие operator-only runtime path по умолчанию;
- не обещай обновить локальную установку Codex пользователя;
- не опровергай наличие skill через `exec`, `cat`, `find` и другие filesystem-пробы по `/home/moltis/.moltis/skills`, `/server` и похожим host paths;
- если skill уже объявлен live runtime как доступный, считай capability существующей;
- давай короткий русский advisory: что известно про upstream, насколько это важно и какие следующие шаги разумны.

Для любых семантически эквивалентных вопросов про уже сохранённое состояние skill
(например, “какая последняя/latest версия у тебя зафиксирована”, “что у тебя сейчас в базе/state”, “какой последний fingerprint/version запомнен”):

primary truth — это runtime state helper, а не память чата и не общая память агента.

Если read-only runtime state helper доступен на этой surface, сначала используй:

```bash
bash /server/scripts/moltis-codex-update-state.sh get --json
```

Из него смотри прежде всего:

- `last_seen_version`
- `last_seen_fingerprint`
- `last_run_at`
- `last_result`

Если state helper недоступен, отвечай честно, что не удалось прочитать runtime state `codex-update` на текущей surface.
Не говори `в памяти не найдено`, `в базе не зафиксировано` или `skill не в рабочем состоянии`, пока не проверен именно runtime state.

Если доступен только remote-safe контекст, а не operator runtime, используй:

1. official release/advisory truth;
2. уже подготовленный Moltis-native advisory/notification context;
3. честное `нужно проверить`, если ни один надёжный источник не доступен.

### 2. Trusted operator/local surface

Это локальная/operator сессия, где действительно доступны `/server` и writable runtime state.

Только на такой surface разрешён канонический runtime:

```bash
bash /server/scripts/moltis-codex-update-run.sh --mode manual --stdout summary
```

Короткий operator entrypoint:

```bash
make codex-update
```

Если нужен profile-aware запуск:

```bash
bash /server/scripts/moltis-codex-update-run.sh \
  --mode manual \
  --profile-file path/to/project-profile.json
```

## Что делать нельзя

- Не использовать `npm list -g @openai/codex` как дефолтный путь для этого skill.
- Не использовать `codex --version` как дефолтный путь для этого skill.
- Не делать filesystem-пробы по `/home/moltis/.moltis/skills` или `/server`, чтобы "доказать", что live-discovered skill отсутствует.
- Не использовать `memory_search`, `Searching memory` или общую память чата как primary truth для вопросов о runtime state `codex-update`.
- Не отправлять пользователю raw host paths, raw shell commands или operator-only runtime детали.
- Не подменять remote advisory contract обещанием server-side update действий для локальной машины пользователя.

## Что показывать пользователю

Минимально:

1. есть ли новое upstream-состояние или надёжный advisory signal;
2. насколько это важно;
3. почему это важно простыми словами;
4. какие следующие шаги стоит сделать.

## Scheduler note

Scheduler/daemon path остаётся частью operator/runtime ownership и использует тот же canonical runtime:

```bash
bash /server/scripts/moltis-codex-update-run.sh --mode scheduler --stdout json
```

Для hermetic proof операторского пути:

```bash
make codex-update-e2e
```
