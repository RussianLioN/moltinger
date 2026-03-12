# On-Demand Telegram E2E Harness

Контур ручного E2E-тестирования для сценария "сообщение пользователя -> ответ Moltis" без переключения прод-бота в постоянный test mode.

## Назначение

- Запуск по требованию (из Codex/локального shell или через `workflow_dispatch`).
- Фиксация фактического ответа и тех. метаданных.
- Ручной verdict по содержимому ответа.

## CLI

Скрипт: `scripts/telegram-e2e-on-demand.sh`

```bash
export MOLTIS_PASSWORD='***'

./scripts/telegram-e2e-on-demand.sh \
  --mode synthetic \
  --message '/status' \
  --timeout-sec 30 \
  --output /tmp/telegram-e2e-result.json \
  --moltis-url 'https://moltis.ainetic.tech' \
  --verbose
```

### Аргументы

- `--mode synthetic|real_user` (обязательно)
- `--message "<text>"` (обязательно)
- `--timeout-sec <int>` (по умолчанию `30`)
- `--output <path>` (по умолчанию `telegram-e2e-result.json`)
- `--moltis-url <url>` (по умолчанию `http://localhost:13131`)
- `--moltis-password-env <ENV_NAME>` (по умолчанию `MOLTIS_PASSWORD`)
- `--verbose`

Примечание по зависимостям:

- для `synthetic`: `curl`, `jq`
- для `real_user`: `python3` + пакет `telethon` (`python3 -m pip install telethon`)

### Exit codes

- `0`: `status=completed`
- `2`: `precondition_failed`
- `3`: `timeout`
- `4`: `upstream_failed`

## GitHub Workflow

Workflow: `.github/workflows/telegram-e2e-on-demand.yml`

Запуск:

```bash
gh workflow run telegram-e2e-on-demand.yml \
  -f mode=synthetic \
  -f message='/status' \
  -f timeout_sec=30 \
  -f moltis_url='https://moltis.ainetic.tech' \
  -f artifact_name='telegram-e2e-result' \
  -f verbose=true
```

Секреты:

- `MOLTIS_PASSWORD` (обязателен для `synthetic`)
- `TELEGRAM_TEST_API_ID` (обязателен для `real_user`)
- `TELEGRAM_TEST_API_HASH` (обязателен для `real_user`)
- `TELEGRAM_TEST_SESSION` (обязателен для `real_user`, StringSession тестового Telegram-пользователя)
- `TELEGRAM_TEST_BOT_USERNAME` (опционально, default `@moltinger_bot`)

Артефакты:

- `telegram-e2e-result.json`
- `telegram-e2e.log`

## Result JSON Schema (v1)

Поля:

- `run_id`
- `mode`
- `trigger_source` (`cli` | `workflow_dispatch`)
- `message`
- `started_at`
- `finished_at`
- `duration_ms`
- `transport`
- `observed_response`
- `status` (`completed` | `timeout` | `precondition_failed` | `upstream_failed`)
- `error_code`
- `error_message`
- `context`

## MVP Boundary

- `mode=synthetic`: рабочий транспорт через `/api/auth/login` + `/api/v1/chat`.
- `mode=real_user`: рабочая отправка через MTProto (Telethon) от тестового пользователя к боту.
- Штатный режим прод-бота не меняется.

## Codex-specific acceptance path

После feature `017-codex-telegram-consent-routing` для сценария `alert -> consent -> recommendations` появился отдельный acceptance helper:

```bash
./scripts/codex-telegram-consent-e2e.sh \
  --mode hermetic \
  --output .tmp/current/codex-telegram-consent-e2e-report.json
```

Или коротко:

```bash
make codex-consent-e2e
```

Что именно он проверяет:

1. watcher отправляет consent-capable alert;
2. consent request сохраняется в shared store;
3. authoritative router принимает tokenized action;
4. второе сообщение с рекомендациями уходит сразу;
5. degraded one-way alert не обещает сломанный follow-up.

Простыми словами:

- общий `telegram-e2e-on-demand` harness остаётся полезным для transport/runtime smoke;
- но именно Codex consent UX теперь принимается через отдельный helper, а не через ручную интерпретацию `/status` или случайных ответов.

## Что уже можно проверять после feature 017

Через component/runtime validation и новый acceptance helper уже можно проверить:

- watcher создаёт authoritative consent request;
- Telegram alert несёт tokenized fallback command;
- router умеет разобрать command fallback и callback payload;
- shared store фиксирует решение и expiry;
- immediate follow-up уходит сразу после `accept`;
- degraded one-way alert не задаёт сломанный вопрос.

Если нужен именно live user-side smoke после деплоя, текущий harness по-прежнему годится для простых probe-сценариев:

```bash
./scripts/telegram-e2e-on-demand.sh \
  --mode real_user \
  --message '/status' \
  --timeout-sec 45 \
  --output /tmp/telegram-e2e-real-user.json \
  --verbose
```

## Real User Example

```bash
export TELEGRAM_TEST_API_ID='123456'
export TELEGRAM_TEST_API_HASH='your_api_hash'
export TELEGRAM_TEST_SESSION='your_string_session'
export TELEGRAM_TEST_BOT_USERNAME='@moltinger_bot'

./scripts/telegram-e2e-on-demand.sh \
  --mode real_user \
  --message '/status' \
  --timeout-sec 45 \
  --output /tmp/telegram-e2e-real-user.json \
  --verbose
```

## Bootstrap TELEGRAM_TEST_SESSION (one-time)

`TELEGRAM_TEST_SESSION` получается локально через OTP и потом кладется в GitHub Secret.

```bash
python3 -m pip install --upgrade telethon

# If you omit --code, script will prompt OTP interactively.
bootstrap_json="$(
  python3 scripts/telegram-real-user-bootstrap.py \
    --api-id "$TELEGRAM_TEST_API_ID" \
    --api-hash "$TELEGRAM_TEST_API_HASH" \
    --phone "+79991234567" \
    --session-out /tmp/telegram-test.session \
    --code "12345"
)"

echo "$bootstrap_json" | jq .

# Save to GitHub Secret (repo example)
gh secret set TELEGRAM_TEST_SESSION --repo RussianLioN/moltinger < /tmp/telegram-test.session
```

Если у аккаунта включен Telegram 2FA:

```bash
export TELEGRAM_TEST_2FA_PASSWORD='your-password'
```
