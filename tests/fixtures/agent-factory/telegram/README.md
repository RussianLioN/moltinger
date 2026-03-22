# Telegram Adapter Fixtures

Этот каталог хранит fixtures для follow-up Telegram adapter (`specs/023-telegram-factory-adapter`).

## Назначение

- Нормализация входящих Telegram updates в envelope для adapter runtime.
- Проверка session routing (`new project`, продолжение, `/status`, reopen).
- Проверка brief review/confirm внутри Telegram.
- Проверка downstream handoff и доставки concept-pack артефактов.

## Базовые fixtures

- `update-new-project.json` — старт нового проекта из Telegram.
- `update-discovery-answer.json` — продолжение discovery после первого вопроса.
- `update-brief-confirm.json` — review/correct/confirm сценарии brief.
- `update-resume-status.json` — resume и `/status` сценарии.

## Правила

- Только синтетические и обезличенные данные.
- Структура update должна быть совместима с Bot API webhook payload.
- Один fixture = один сценарий/интент, без смешивания нескольких веток в одном файле.
- Поля `update_id`, `chat.id`, `from.id`, `message_id` должны быть traceable для локальных тестов.
