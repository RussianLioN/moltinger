# Монитор upstream-обновлений Codex CLI

`codex-cli-upstream-watcher.sh` следит за официальными upstream-источниками Codex CLI и не требует локально установленного `codex` на сервере Moltinger.

Он отвечает на три простых вопроса:

- появилось ли новое состояние upstream?
- это уже известное состояние или новое?
- нужно ли отправлять одно Telegram-уведомление или надо промолчать?

Этот watcher намеренно смотрит только на upstream. Он не решает сам, нужно ли менять текущий репозиторий локально.

## Ручной запуск

```bash
mkdir -p .tmp/current

./scripts/codex-cli-upstream-watcher.sh \
  --mode manual \
  --json-out .tmp/current/codex-upstream-watcher-report.json \
  --summary-out .tmp/current/codex-upstream-watcher-summary.md \
  --stdout summary
```

Что получает оператор:

- короткий понятный summary в терминале
- детерминированный JSON-отчёт
- сохранённое состояние в `.tmp/current/codex-cli-upstream-watcher-state.json`

Важно:

- summary и Telegram-текст теперь формируются только на русском
- исходные формулировки из официального changelog сохраняются в JSON-отчёте как данные источника и могут оставаться на английском

Понятные итоги:

- `deliver`: найден новый upstream fingerprint
- `suppress`: этот fingerprint уже встречался раньше
- `investigate`: основной changelog недоступен или повреждён
- `retry`: Telegram-отправка сломалась, позже нужно повторить

## Advisory issue signals

Дополнительные issue signals добавляют контекст, но не заменяют официальный changelog как главный источник истины.

```bash
./scripts/codex-cli-upstream-watcher.sh \
  --mode manual \
  --include-issue-signals \
  --issue-signals-url "https://api.github.com/repos/openai/codex/issues?state=open&per_page=20"
```

Issue signals влияют на заметки и контекст, но сами по себе не переопределяют решение по релизу.

## Scheduler и Telegram

Режим scheduler предназначен для запуска на стороне Moltinger.

```bash
./scripts/codex-cli-upstream-watcher.sh \
  --mode scheduler \
  --include-issue-signals \
  --telegram-enabled \
  --telegram-env-file /opt/moltinger/.env \
  --json-out /opt/moltinger/.tmp/current/codex-upstream-watcher-report.json \
  --summary-out /opt/moltinger/.tmp/current/codex-upstream-watcher-summary.md \
  --stdout none
```

Как ведёт себя Telegram:

- новый upstream fingerprint даёт одно уведомление
- тот же самый fingerprint повторно не отправляется
- при ошибке Telegram run получает статус `retry` и остаётся пригодным для повторной попытки

Если `--telegram-chat-id` не указан, watcher пытается определить адресата так:

1. `CODEX_UPSTREAM_WATCHER_TELEGRAM_CHAT_ID` from the env file
2. first id from `TELEGRAM_ALLOWED_USERS` in the env file

Так feature остаётся совместимым с уже существующим Moltinger bot runtime.

## Cron-установка

GitOps-managed cron-файл:

- `scripts/cron.d/moltis-codex-upstream-watcher`

Он ставится через `.github/workflows/deploy.yml` вместе с остальными файлами из `scripts/cron.d/`.

Что делает cron-задача:

- пишет логи в `/var/log/moltis/codex-upstream-watcher.log`
- хранит state в `/opt/moltinger/.tmp/current/`
- берёт Telegram credentials из `/opt/moltinger/.env`

## Что именно выдаёт инструмент

Верхние поля отчёта:

- `checked_at`
- `snapshot`
- `fingerprint`
- `decision`
- `state`
- `telegram_target`
- `notes`

Важная семантика:

- `snapshot.release_status` показывает, upstream это `new`, `known`, `investigate` или `unavailable`
- `decision.status` показывает, что делать сейчас: `deliver`, `suppress`, `retry` или `investigate`
- `state.last_delivered_fingerprint` обновляется только после успешной Telegram-отправки

## Как это выглядит для пользователя

Пример 1: ручная проверка увидела новый релиз

- summary говорит, что появилась новая upstream-версия Codex
- решение будет `deliver`
- Telegram не отправляется, потому что запуск был ручной

Пример 2: scheduler снова увидел тот же уже отправленный релиз

- summary и отчёт говорят, что fingerprint уже известен
- решение будет `suppress`
- Telegram повторно не вызывается

Пример 3: официальный changelog временно сломался

- summary и отчёт показывают `investigate`
- прошлый доставленный fingerprint сохраняется
- если потом вернётся тот же fingerprint, повторной отправки не будет
