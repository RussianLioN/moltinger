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
