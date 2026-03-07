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

### Exit codes

- `0`: `status=completed`
- `2`: `precondition_failed` или `deferred_real_user`
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
- `TELEGRAM_TEST_API_ID` (reserved для будущего `real_user`)
- `TELEGRAM_TEST_API_HASH` (reserved для будущего `real_user`)
- `TELEGRAM_TEST_SESSION` (reserved для будущего `real_user`)

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
- `status` (`completed` | `timeout` | `precondition_failed` | `upstream_failed` | `deferred_real_user`)
- `error_code`
- `error_message`
- `context`

## MVP Boundary

- `mode=synthetic`: рабочий транспорт через `/api/auth/login` + `/api/v1/chat`.
- `mode=real_user`: в MVP только контракт/guards, без реальной отправки в Telegram.
- Штатный режим прод-бота не меняется.
