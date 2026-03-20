# Telegram User Monitor без API_HASH (через Telegram Web)

Если MTProto-вариант с `API_HASH` не работает, используйте этот путь:

- авторизация как обычный пользователь в Telegram Web
- отправка сообщений боту через браузерную сессию
- проверка качества ответа в JSON

## Скрипты

- `scripts/telegram-web-user-login.mjs` — разовая авторизация
- `scripts/telegram-web-user-probe.mjs` — разовый probe и проверка ответа
- `scripts/telegram-web-user-monitor.sh` — обёртка для мониторинга
- `systemd/moltis-telegram-web-user-monitor.service` — one-shot сервис проверки
- `systemd/moltis-telegram-web-user-monitor.timer` — primary scheduler (каждые 10 минут)
- `scripts/cron.d/moltis-telegram-web-user-monitor` — fallback scheduler (optional)

## 1) Установка зависимостей

```bash
./scripts/setup-telegram-web-user-monitor.sh --project-dir /opt/moltinger-active
```

По умолчанию setup также устанавливает и включает systemd timer:
`moltis-telegram-web-user-monitor.timer`.

## 2) Разовая авторизация (интерактивно)

```bash
node scripts/telegram-web-user-login.mjs --state /opt/moltinger-active/data/.telegram-web-state.json
```

Откроется браузер Telegram Web. Войдите как пользователь (QR/код).

Если на сервере нет GUI:
1. Выполните login-скрипт на локальном ПК (где есть браузер), например:
```bash
node scripts/telegram-web-user-login.mjs --state .telegram-web-state.json
```
2. Скопируйте state-файл на сервер:
```bash
scp .telegram-web-state.json root@ainetic.tech:/opt/moltinger-active/data/.telegram-web-state.json
```

## 3) Разовая проверка

```bash
node scripts/telegram-web-user-probe.mjs \
  --state /opt/moltinger-active/data/.telegram-web-state.json \
  --target @moltinger_bot \
  --text "test2"
```

## 4) Постоянный режим

### Вариант A (рекомендуется): systemd timer

```bash
cp systemd/moltis-telegram-web-user-monitor.service /etc/systemd/system/
cp systemd/moltis-telegram-web-user-monitor.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now moltis-telegram-web-user-monitor.timer
systemctl status moltis-telegram-web-user-monitor.timer --no-pager
```

### Вариант B (fallback): cron

```bash
cp scripts/cron.d/moltis-telegram-web-user-monitor /etc/cron.d/
chmod 644 /etc/cron.d/moltis-telegram-web-user-monitor
```

Лог:

```bash
/var/log/moltis/telegram-web-user-monitor.log
```

## Probe Profiles

`scripts/telegram-web-user-monitor.sh` поддерживает:

- `TELEGRAM_WEB_PROBE_PROFILE=strict_status` — отправляет `/status` (default)
- `TELEGRAM_WEB_PROBE_PROFILE=echo_ping` — отправляет детерминированный текст (default `test2`)

Пример:

```bash
TELEGRAM_WEB_PROBE_PROFILE=echo_ping \
TELEGRAM_WEB_MESSAGE=test2 \
TELEGRAM_WEB_COMPOSER_RETRIES=2 \
scripts/telegram-web-user-monitor.sh
```

JSON output `telegram-web-user-probe.mjs` теперь включает:

- `stage`: `login|search|chat_open|composer|send|wait_reply`
- `retries_used`
- `chat_open_verified`

## Плюсы/минусы

Плюсы:
- не нужен `API_HASH`
- работает как реальный пользователь

Минусы:
- браузерная автоматизация менее стабильна, чем MTProto
- при logout в Telegram Web нужно снова запускать login-скрипт
