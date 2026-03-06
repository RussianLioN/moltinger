# Telegram Webhook + CLI (Standalone, без Moltis)

Этот набор скриптов работает напрямую с Telegram API и не зависит от режима каналов Moltis.

## 1) Управление webhook бота

Скрипт: `scripts/telegram-webhook-control.sh`

```bash
# (опционально) поднять минимальный webhook endpoint за Traefik
./scripts/setup-telegram-webhook-echo.sh \
  --domain moltis.ainetic.tech \
  --path /telegram-webhook

# Проверить токен и бота
./scripts/telegram-webhook-control.sh get-me

# Текущий webhook
./scripts/telegram-webhook-control.sh webhook-info

# Установить webhook
./scripts/telegram-webhook-control.sh webhook-set \
  --url "https://YOUR_DOMAIN/YOUR_WEBHOOK_PATH" \
  --secret "YOUR_SECRET" \
  --drop-pending true \
  --allowed-updates "message,edited_message,callback_query"

# Удалить webhook (вернуться к getUpdates)
./scripts/telegram-webhook-control.sh webhook-delete --drop-pending true
```

Переменные:
- `TELEGRAM_BOT_TOKEN` (обязательно)
- `MOLTIS_ENV_FILE` (опционально, по умолчанию `.env`)

## 2) Отправка сообщений из CLI как бот

Скрипт: `scripts/telegram-bot-send.sh`

```bash
./scripts/telegram-bot-send.sh \
  --chat-id 262872984 \
  --text "/status"
```

Опции:
- `--parse-mode HTML|MarkdownV2`
- `--disable-notification`
- `--reply-to <message_id>`

## 3) Отправка сообщений из CLI как пользователь (MTProto)

Скрипт: `scripts/telegram-user-send.py`

Требуется `Telethon`:

```bash
python3 -m pip install telethon
```

Переменные:
- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`
- `TELEGRAM_SESSION` (опционально, по умолчанию `.telegram-user`)

Пример:

```bash
./scripts/telegram-user-send.py \
  --to @some_bot_or_chat \
  --text "/start"
```

На первом запуске Telethon запросит код подтверждения и, при необходимости, 2FA-пароль.

## Важно

- Bot API не умеет отправлять сообщения "от имени пользователя". Для этого нужен MTProto (Telethon/TDLib).
- Для webhook Telegram нужен публичный HTTPS endpoint, доступный из интернета.
- Для постоянной проверки ответов бота как пользователь: `docs/TELEGRAM-USER-MONITOR.md`.
