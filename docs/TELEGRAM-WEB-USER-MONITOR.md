# Telegram User Monitor без API_HASH (через Telegram Web)

Если MTProto-вариант с `API_HASH` не работает, используйте этот путь:

- авторизация как обычный пользователь в Telegram Web
- отправка сообщений боту через браузерную сессию
- проверка качества ответа в JSON

## Скрипты

- `scripts/telegram-web-user-login.mjs` — разовая авторизация
- `scripts/telegram-web-user-probe.mjs` — разовый probe и проверка ответа
- `scripts/telegram-web-user-monitor.sh` — обёртка для cron
- `scripts/cron.d/moltis-telegram-web-user-monitor` — периодический запуск

## 1) Установка зависимостей

```bash
./scripts/setup-telegram-web-user-monitor.sh --project-dir /opt/moltinger
```

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

## 4) Постоянный режим

```bash
cp scripts/cron.d/moltis-telegram-web-user-monitor /etc/cron.d/
chmod 644 /etc/cron.d/moltis-telegram-web-user-monitor
```

Лог:

```bash
/var/log/moltis/telegram-web-user-monitor.log
```

## Плюсы/минусы

Плюсы:
- не нужен `API_HASH`
- работает как реальный пользователь

Минусы:
- браузерная автоматизация менее стабильна, чем MTProto
- при logout в Telegram Web нужно снова запускать login-скрипт
