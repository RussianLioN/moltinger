---
name: openclaw-improvement-learner
description: Собирает важные улучшения, релизы и инструкции по OpenClaw и превращает их в приоритизированные improvement briefs для Moltinger.
telegram_summary: отслеживает официальные релизы, docs, issues и подтверждённые community-сигналы, чтобы находить важные улучшения для OpenClaw и Moltinger.
value_statement: Полезен, когда нужно быстро понять, какие upstream-изменения и инструкции по OpenClaw стоит внедрять в первую очередь.
source_priority: Сначала использует official docs, releases, changelog и issues OpenClaw; community-источники и Telegram применяет только как дополнительный сигнал.
telegram_safe_note: В Telegram-safe чате даю только краткое описание и приоритеты; полный разбор и запуск лучше продолжать в web UI или операторской сессии.
---

# OpenClaw Improvement Learner

## Активация

- Пользователь просит собрать важные улучшения по OpenClaw.
- Нужно отследить новые релизы, инструкции или критичные issues upstream.
- Нужен приоритизированный shortlist улучшений для Moltinger.
- Нужен короткий Telegram-safe ответ про назначение навыка.

## Источники по приоритету

1. Official docs OpenClaw.
2. Official releases, changelog, commits и issues в основном репозитории.
3. Подтверждённые community/Telegram сигналы, если они ведут к воспроизводимому техническому улучшению.

## Канонический runtime

- В Telegram-safe DM возвращает только краткое описание или короткий приоритизированный digest.
- Полный сбор и ранжирование выполняется в web UI, операторской сессии или scheduled learner-run.
- Любая рекомендация должна ссылаться на официальный upstream источник или явно помечаться как community signal.

## Workflow

1. Собрать candidate changes из official releases, docs и issues.
2. Отфильтровать по важности для Moltinger: reliability, Telegram delivery, skill runtime, operator UX.
3. Подтвердить факты по официальным источникам.
4. Отранжировать improvement brief по критичности и ожидаемому эффекту.
5. Предложить первые действия для внедрения в Moltinger.

## Выходы

- короткий digest по важным upstream-изменениям;
- ranked improvement brief;
- action shortlist для первых внедрений.

## Guardrails

- Не выдавай community advice как official instruction без явной верификации.
- Не обещай скрытый запуск инструментов в Telegram-safe DM.
- Не добавляй внутренние tool names, file paths и operator markup в пользовательский ответ.
