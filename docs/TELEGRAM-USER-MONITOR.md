# Telegram User Monitor (постоянная проверка ответов бота)

Фокус: отправка сообщений **как пользователь** и автоматическая проверка ответов бота.

## Что используется

- `scripts/telegram-user-send.py` — ручная отправка как пользователь (MTProto)
- `scripts/telegram-user-probe.py` — одноразовый probe + валидация ответа
- `scripts/telegram-user-monitor.sh` — обёртка для cron/systemd
- `scripts/cron.d/moltis-telegram-user-monitor` — периодический запуск каждые 10 минут

## Обязательные переменные

В `.env`:

```bash
TELEGRAM_API_ID=...
TELEGRAM_API_HASH=...
TELEGRAM_SESSION=/opt/moltinger/data/.telegram-user
TELEGRAM_MONITOR_TARGET=@moltinger_bot
TELEGRAM_MONITOR_MESSAGE=/status
```

## Инициализация сессии пользователя (1 раз)

```bash
./scripts/telegram-user-send.py --to @moltinger_bot --text "/start" --env-file .env
```

На первом запуске Telethon запросит код из Telegram и (если включено) 2FA-пароль.

## Разовый прогон проверки

```bash
./scripts/telegram-user-monitor.sh --env-file .env
```

Скрипт вернёт JSON:
- `status=pass|fail`
- `reply_text`
- `checks` (минимальная длина, отсутствие error/sensitive сигнатур)

## Постоянный мониторинг

Cron-файл:

```bash
scripts/cron.d/moltis-telegram-user-monitor
```

Лог:

```bash
/var/log/moltis/telegram-user-monitor.log
```
