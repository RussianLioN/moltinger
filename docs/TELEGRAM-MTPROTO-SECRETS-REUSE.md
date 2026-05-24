# Telegram MTProto: переиспользование тестовой авторизации

Документ описывает действующий проектный способ переиспользовать уже заведенные секреты `TELEGRAM_TEST_API_ID`, `TELEGRAM_TEST_API_HASH` и `TELEGRAM_TEST_SESSION` для чтения Telegram-каналов через MTProto.

## Короткий вывод

В проекте уже есть рабочая методика хранения MTProto-авторизации: значения лежат в GitHub Secrets и передаются в запускаемый вручную рабочий процесс GitHub Actions как переменные окружения. Для чтения канала нужно не заводить новый способ хранения, а переиспользовать тот же набор:

- `TELEGRAM_TEST_API_ID` - Telegram API id приложения.
- `TELEGRAM_TEST_API_HASH` - Telegram API hash приложения.
- `TELEGRAM_TEST_SESSION` - сериализованная Telethon `StringSession` пользовательского аккаунта.

`TELEGRAM_TEST_SESSION` является полноценной авторизацией Telegram-аккаунта. Любой код с этим значением может читать то, что доступно этому аккаунту, и выполнять действия от его имени. Поэтому сессия должна храниться как секрет, не выводиться в логи и не попадать в артефакты.

## Где это уже используется

Проектные источники:

- [`.github/workflows/telegram-e2e-on-demand.yml`](../.github/workflows/telegram-e2e-on-demand.yml) - передает `TELEGRAM_TEST_API_ID`, `TELEGRAM_TEST_API_HASH`, `TELEGRAM_TEST_SESSION` и `TELEGRAM_TEST_BOT_USERNAME` из GitHub Secrets в удаленный UAT-запуск.
- [`scripts/telegram-real-user-bootstrap.py`](../scripts/telegram-real-user-bootstrap.py) - один раз создает Telethon `StringSession` через OTP-вход.
- [`scripts/telegram-real-user-e2e.py`](../scripts/telegram-real-user-e2e.py) - использует `StringSession` для пользовательской MTProto-сессии и проверки ответов бота.
- [`specs/004-telegram-e2e-harness/quickstart.md`](../specs/004-telegram-e2e-harness/quickstart.md) - описывает запуск `real_user` режима.
- [`docs/SECRETS-MANAGEMENT.md`](SECRETS-MANAGEMENT.md) - фиксирует GitHub Secrets как единственный источник истины для проектных секретов.

Проверка наличия секретов:

```bash
gh secret list --repo RussianLioN/moltinger
```

Команда показывает имена и дату обновления секретов, но не раскрывает значения. Это ожидаемое поведение: значения GitHub Secrets нельзя прочитать обратно через `gh secret list`.

## Как происходит авторизация

1. Telegram-приложение регистрируется в `my.telegram.org` и получает пару `api_id` / `api_hash`.
2. Пользовательский аккаунт проходит вход через Telethon: номер телефона, код из Telegram, при необходимости пароль двухфакторной защиты.
3. Telethon сохраняет результат входа как `StringSession`.
4. В проекте эта строка кладется в GitHub Secret `TELEGRAM_TEST_SESSION`.
5. Рабочий процесс GitHub Actions передает `TELEGRAM_TEST_API_ID`, `TELEGRAM_TEST_API_HASH` и `TELEGRAM_TEST_SESSION` в среду выполнения.
6. Код создает `TelegramClient(StringSession(session), api_id, api_hash)` и работает как уже авторизованный пользователь.

Ключевой момент: `api_id` и `api_hash` идентифицируют Telegram-приложение, а `TELEGRAM_TEST_SESSION` содержит авторизацию конкретного Telegram-аккаунта.

## Безопасное создание или ротация сессии

Создавать новую сессию нужно только при первичной настройке, ротации, отзыве старой сессии или смене Telegram-аккаунта.

```bash
python3 scripts/telegram-real-user-bootstrap.py \
  --api-id "$TELEGRAM_TEST_API_ID" \
  --api-hash "$TELEGRAM_TEST_API_HASH" \
  --phone "+<telegram_phone>" \
  --session-out /tmp/telegram-test.session
```

Скрипт записывает сессию в файл и выставляет права `600`. Не используйте `--print-session` в общих терминалах, CI-логах и чатах.

После проверки файл можно сохранить в GitHub Secrets:

```bash
gh secret set TELEGRAM_TEST_SESSION \
  --repo RussianLioN/moltinger \
  < /tmp/telegram-test.session
```

Для полной ротации обновляются все три значения, если менялось Telegram-приложение:

```bash
gh secret set TELEGRAM_TEST_API_ID --repo RussianLioN/moltinger
gh secret set TELEGRAM_TEST_API_HASH --repo RussianLioN/moltinger
gh secret set TELEGRAM_TEST_SESSION --repo RussianLioN/moltinger < /tmp/telegram-test.session
```

После ротации нужно удалить временный файл:

```bash
rm -f /tmp/telegram-test.session
```

Если есть подозрение на утечку `TELEGRAM_TEST_SESSION`, нужно отозвать активную сессию в официальном Telegram-клиенте и затем создать новую.

## Переиспользование для чтения канала

Для чтения канала нужен пользовательский аккаунт, которому этот канал доступен. Если канал приватный, аккаунт должен быть участником. Если канал публичный, достаточно доступа по имени или ссылке.

Минимальный шаблон кода:

```python
import asyncio
import os

from telethon import TelegramClient
from telethon.sessions import StringSession


async def main() -> None:
    api_id = int(os.environ["TELEGRAM_TEST_API_ID"])
    api_hash = os.environ["TELEGRAM_TEST_API_HASH"]
    session = os.environ["TELEGRAM_TEST_SESSION"]
    channel = os.environ["TELEGRAM_CHANNEL"]

    async with TelegramClient(
        StringSession(session),
        api_id,
        api_hash,
        device_model="moltis-channel-reader",
    ) as client:
        if not await client.is_user_authorized():
            raise RuntimeError("Telegram session is not authorized")

        entity = await client.get_entity(channel)
        async for message in client.iter_messages(entity, limit=50):
            text = message.raw_text or ""
            print(
                {
                    "id": message.id,
                    "date": message.date.isoformat() if message.date else None,
                    "text_preview": text[:300],
                    "text_length": len(text),
                }
            )


if __name__ == "__main__":
    asyncio.run(main())
```

Для проектной интеграции этот код лучше вынести в отдельный сборщик только для чтения:

- входы: `TELEGRAM_TEST_API_ID`, `TELEGRAM_TEST_API_HASH`, `TELEGRAM_TEST_SESSION`, `TELEGRAM_CHANNEL`;
- выход: обезличенный JSON/NDJSON или агрегированная сводка;
- запрет: не писать `TELEGRAM_TEST_SESSION`, `api_hash`, полный дамп приватных сообщений или вложения в логи и артефакты;
- ограничение: использовать малые лимиты и понятную частоту запусков, чтобы не создавать подозрительную активность Telegram API.

## Как передавать секреты в GitHub Actions

Схема совпадает с уже существующим `telegram-e2e-on-demand.yml`:

```yaml
env:
  TELEGRAM_TEST_API_ID: ${{ secrets.TELEGRAM_TEST_API_ID }}
  TELEGRAM_TEST_API_HASH: ${{ secrets.TELEGRAM_TEST_API_HASH }}
  TELEGRAM_TEST_SESSION: ${{ secrets.TELEGRAM_TEST_SESSION }}
  TELEGRAM_CHANNEL: ${{ inputs.telegram_channel }}
```

Внутри шага `shell` секреты должны использоваться через переменные окружения, а не подставляться в командную строку как открытый текст. Если нужно передать секрет в удаленный процесс, используйте строгую кавычку и не печатайте итоговую команду.

## Локальное хранение

Предпочтительный способ - GitHub Secrets. Локальные копии допустимы только для одноразовой диагностики.

Разрешено:

- `/tmp/telegram-test.session` с правами `600` на время ротации;
- `.env.local`, если файл находится в `.gitignore`;
- `data/` или другой исключенный из git каталог для временного состояния.

Не использовать:

- значения в отслеживаемых git-файлах Markdown, YAML, Python, shell или TOML;
- Telethon-файл `.session` в корне репозитория;
- вывод `TELEGRAM_TEST_SESSION` в терминал, issue, комментарий, артефакт GitHub Actions или лог.

## Ограничения

- GitHub Secrets не позволяют прочитать существующее значение обратно; можно только проверить имя и дату обновления или перезаписать секрет.
- `TELEGRAM_TEST_SESSION` дает доступ уровня Telegram-аккаунта, а не только к одному каналу.
- Чтение приватного канала возможно только если авторизованный аккаунт уже имеет доступ к нему.
- Telegram API отслеживает злоупотребления; автоматическое массовое чтение, спам и накрутки запрещены правилами Telegram.

## Официальные источники

- Telegram: [Creating your Telegram Application](https://core.telegram.org/api/obtaining_api_id)
- Telethon: [Signing In](https://docs.telethon.dev/en/stable/basic/signing-in.html)
- Telethon: [Session Files and StringSession](https://docs.telethon.dev/en/stable/concepts/sessions.html)
- GitHub Actions: [Using secrets in GitHub Actions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
- GitHub Actions: [Contexts reference, secrets context](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#secrets-context)
