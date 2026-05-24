# Moltinger

Центральная точка входа в проектную документацию.

## Быстрый вход

| Раздел | Где читать | Когда использовать |
|--------|------------|--------------------|
| Быстрый справочник | [docs/QUICK-REFERENCE.md](docs/QUICK-REFERENCE.md) | Начало рабочей сессии, основные команды и ссылки |
| Управление секретами | [docs/SECRETS-MANAGEMENT.md](docs/SECRETS-MANAGEMENT.md) | Любые изменения или проверки секретов |
| Telegram MTProto: переиспользование тестовой авторизации | [docs/TELEGRAM-MTPROTO-SECRETS-REUSE.md](docs/TELEGRAM-MTPROTO-SECRETS-REUSE.md) | Чтение каналов через MTProto с `TELEGRAM_TEST_API_ID`, `TELEGRAM_TEST_API_HASH`, `TELEGRAM_TEST_SESSION` |
| Текущее состояние проекта | [SESSION_SUMMARY.md](SESSION_SUMMARY.md) | Восстановление контекста между сессиями |
| Топология веток и worktree | [docs/GIT-TOPOLOGY-REGISTRY.md](docs/GIT-TOPOLOGY-REGISTRY.md) | Проверка назначения веток, worktree и рабочих линий |

## Правило секретов

Секретные значения не хранятся в git. Каноническое хранилище для проектных секретов - GitHub Secrets. Локальные файлы с секретами должны оставаться вне индекса git и использоваться только для диагностики или первичной авторизации.
