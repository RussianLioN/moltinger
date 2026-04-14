---
name: telegram-chat-probe
description: Быстрый one-command тест Telegram бота через real_user с возвратом ответа бота в тот же чат-цикл.
telegram_summary: быстро показывает, что именно ответил Telegram-бот на конкретное сообщение через sanctioned real_user probe path.
value_statement: Полезен, когда нужно проверить живой ответ бота и сразу получить краткую диагностику без ручного многошагового запуска.
source_priority: Сначала использует tracked wrapper `scripts/telegram-chat-probe.sh`, который агрегирует contract поверх `telegram-user-probe.py`; при расхождении верить tracked script/test contract, а не устным воспоминаниям.
telegram_safe_note: В Telegram-safe или operator-limited surface я не обещаю скрытый live probe без доступного real_user runtime; вместо этого честно сообщаю про preconditions или operator boundary.
---

# Telegram Chat Probe

## Когда использовать

Используй этот skill, когда нужно быстро проверить:

- что ответит бот на конкретное сообщение;
- проходит ли real_user путь без ручного многошагового запуска;
- какая диагностика при timeout, missing preconditions или upstream ошибке.

## Канонический entrypoint

```bash
scripts/telegram-chat-probe.sh \
  --message '/status' \
  --target '@moltinger_bot' \
  --timeout-sec 45 \
  --json-out /tmp/telegram-chat-probe.json
```

Этот wrapper является source-of-truth для skill contract и делегирует в `scripts/telegram-user-probe.py`.

## Обязательные предпосылки

- Настроены `TELEGRAM_TEST_API_ID`, `TELEGRAM_TEST_API_HASH`, `TELEGRAM_TEST_SESSION`.
- Доступны `python3` и `jq`.
- Запуск идёт из tracked checkout репозитория.

## Параметры

- `--message` (required): текст, отправляемый боту
- `--target` (optional): username/link/id; по умолчанию `@moltinger_bot` или `TELEGRAM_TEST_BOT_USERNAME`
- `--timeout-sec` (optional): ожидание ответа; по умолчанию `45`
- `--json-out` (optional): путь для сохранения агрегированного JSON
- `--verbose` (optional): печатать stderr-диагностику wrapper-а

## Контракт результата

Ожидаемые `status`:

- `completed`
- `timeout`
- `precondition_failed`
- `upstream_failed`

Skill должен вернуть:

1. `message` и `target`
2. `status`
3. `observed_reply` или краткую причину отсутствия ответа
4. `next_action` для remediation

## Шаблон ответа

```markdown
## Telegram Probe Result
- target: <target>
- message: <message>
- status: <status>
- observed_reply: <text-or-none>
- next_action: <short remediation>
```

## Failure playbook

- `precondition_failed`: проверить env и при необходимости заново bootstrap-нуть real_user session
- `timeout`: увеличить timeout или проверить prompt вручную
- `upstream_failed`: проверить валидность Telegram session, target и stderr helper-а

## Границы

- Никогда не выводить raw `TELEGRAM_TEST_SESSION`.
- Это только on-demand verification path; skill не включает постоянный test mode и не меняет production runtime сам по себе.
- Для более широкого Telegram E2E/remote-UAT использовать canonical handbook `docs/telegram-e2e-on-demand.md`.
