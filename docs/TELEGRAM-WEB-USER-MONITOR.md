# Telegram User Monitor без API_HASH (через Telegram Web)

Если MTProto-вариант с `API_HASH` не работает, используйте этот путь:

- авторизация как обычный пользователь в Telegram Web
- отправка сообщений боту через браузерную сессию
- проверка качества ответа в JSON

## Скрипты

- `scripts/telegram-web-user-login.mjs` — разовая авторизация
- `scripts/telegram-web-user-probe.mjs` — разовый probe и проверка ответа
- `scripts/telegram-web-user-monitor.sh` — обёртка для мониторинга
- `systemd/moltis-telegram-web-user-monitor.service` — optional one-shot сервис проверки
- `systemd/moltis-telegram-web-user-monitor.timer` — optional manual scheduler

## 1) Установка зависимостей

```bash
./scripts/setup-telegram-web-user-monitor.sh --project-dir /opt/moltinger
```

По умолчанию setup ставит только зависимости. Systemd timer больше не включается автоматически.

## 2) Разовая авторизация (интерактивно)

```bash
node scripts/telegram-web-user-login.mjs --state /opt/moltinger/data/.telegram-web-state.json
```

Откроется браузер Telegram Web. Войдите как пользователь (QR/код).

Если на сервере нет GUI:
1. Выполните login-скрипт на локальном ПК (где есть браузер), например:
```bash
node scripts/telegram-web-user-login.mjs --state .telegram-web-state.json
```
2. Скопируйте state-файл на сервер:
```bash
scp .telegram-web-state.json root@ainetic.tech:/opt/moltinger/data/.telegram-web-state.json
```

## 3) Разовая проверка

```bash
node scripts/telegram-web-user-probe.mjs \
  --state /opt/moltinger/data/.telegram-web-state.json \
  --target @moltinger_bot \
  --text "/status"
```

## 4) Периодический режим

Периодический Telegram Web monitor больше не включается в production по умолчанию.
Если он нужен снова, включайте его только явно и вручную.

### Вариант A: systemd timer (manual opt-in)

```bash
cp systemd/moltis-telegram-web-user-monitor.service /etc/systemd/system/
cp systemd/moltis-telegram-web-user-monitor.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now moltis-telegram-web-user-monitor.timer
systemctl status moltis-telegram-web-user-monitor.timer --no-pager
```

Лог:

```bash
/var/log/moltis/telegram-web-user-monitor.log
```

## Probe Profiles

`scripts/telegram-web-user-monitor.sh` поддерживает:

- `TELEGRAM_WEB_PROBE_PROFILE=strict_status` — отправляет `/status` (default)
- `TELEGRAM_WEB_PROBE_PROFILE=echo_ping` — отправляет детерминированный текст (default `ping`)

Пример:

```bash
TELEGRAM_WEB_PROBE_PROFILE=strict_status \
TELEGRAM_WEB_COMPOSER_RETRIES=2 \
TELEGRAM_WEB_QUIET_WINDOW_MS=3000 \
scripts/telegram-web-user-monitor.sh
```

`TELEGRAM_WEB_QUIET_WINDOW_MS` задаёт обязательное окно тишины в чате перед probe.
Если в чате продолжают появляться новые сообщения, probe завершается `fail`, а не засчитывает потенциально чужой ответ за текущий цикл.

JSON output `telegram-web-user-probe.mjs` теперь включает:

- `stage`: `login|search|chat_open|quiet_window|composer|send|wait_reply`
- `retries_used`
- `chat_open_verified`
- `sent_mid`
- `correlation`: `quiet_window_ms`, `quiet_window_wait_ms`, `baseline_max_mid`, `sent_message`, `matched_reply`, `latest_seen_incoming`, `last_pre_send_activity`

## Плюсы/минусы

Плюсы:
- не нужен `API_HASH`
- работает как реальный пользователь

Минусы:
- браузерная автоматизация менее стабильна, чем MTProto
- при logout в Telegram Web нужно снова запускать login-скрипт
