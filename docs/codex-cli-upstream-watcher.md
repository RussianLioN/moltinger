# Монитор обновлений Codex CLI

`codex-cli-upstream-watcher.sh` следит за официальным changelog Codex CLI, не требует установленного `codex` на хосте Moltinger и умеет:

- понять, появилось ли новое upstream-состояние
- показать важность этого изменения простым русским языком
- собирать события в дайджест, чтобы не шуметь
- подготовить bridge к проектным рекомендациям через advisor-слой
- спросить пользователя в Telegram, нужны ли практические рекомендации, и открыть authoritative consent request для дальнейшего follow-up

Инструмент по-прежнему разделяет две задачи:

- upstream watcher отвечает на вопрос: «Что нового у Codex CLI вообще?»
- advisor bridge помогает ответить на вопрос: «Что из этого стоит проверить именно в этом проекте?»

## Что получает пользователь

Результат одной проверки приходит в три формы:

- короткий русский summary в терминале
- JSON-отчёт для автоматизации
- Telegram-уведомление, если включён scheduler и найдено новое состояние

В summary теперь всегда есть:

- уровень важности
- простое русское объяснение изменений
- состояние дайджеста
- статус вопроса о практических рекомендациях

## Ручной запуск

```bash
mkdir -p .tmp/current

./scripts/codex-cli-upstream-watcher.sh \
  --mode manual \
  --include-issue-signals \
  --json-out .tmp/current/codex-upstream-watcher-report.json \
  --summary-out .tmp/current/codex-upstream-watcher-summary.md \
  --stdout summary
```

Что это даёт:

- быстро показывает, есть ли новый upstream-релиз
- объясняет важность простыми словами
- сразу готовит project-facing рекомендации через advisor bridge

## Уровни важности

Watcher различает несколько уровней:

- `обычная`: новая версия есть, но без признаков срочного риска
- `высокая`: изменения затрагивают рабочие сценарии проекта, например worktree, resume, multi-agent, sandbox или `js_repl`
- `критическая`: есть признаки несовместимости, миграции или более рискованных изменений
- `нужно проверить`: официальный источник недоступен или сломан

Простыми словами:

- уровень важности нужен, чтобы понять, это просто новость или повод проверить проект прямо сейчас

## Режим дайджеста

По умолчанию watcher работает в режиме `immediate`: новое событие отправляется сразу.

Если нужен менее шумный режим, включай digest:

```bash
./scripts/codex-cli-upstream-watcher.sh \
  --mode scheduler \
  --delivery-mode digest \
  --digest-window-hours 24 \
  --digest-max-items 3 \
  --telegram-enabled
```

Как это работает:

- новые upstream-события складываются в очередь
- watcher отправляет одно объединённое сообщение, когда накопилось достаточно событий или прошло заданное окно
- критические изменения всё равно могут уйти сразу, чтобы не ждать digest-окна

Простыми словами:

- digest нужен, чтобы вместо серии мелких сообщений получать одну внятную сводку

## Практические рекомендации для проекта

Watcher теперь строит `advisor bridge` поверх уже существующего monitor/advisor слоя.

Что это значит:

- watcher сам отслеживает upstream-состояние
- advisor bridge смотрит, какие участки этого проекта вероятнее всего нужно пересмотреть
- рекомендации приходят не автоматически всем подряд, а только по запросу или по согласию пользователя

В summary это видно как секция:

- `Практические рекомендации для проекта`

Там watcher показывает:

- готовы ли рекомендации
- краткий смысл
- какие 2-3 направления проверить в первую очередь

## Telegram-уведомления и authoritative consent routing

Scheduler-режим умеет не только отправлять alert, но и продолжать диалог.

Пример запуска:

```bash
./scripts/codex-cli-upstream-watcher.sh \
  --mode scheduler \
  --include-issue-signals \
  --telegram-enabled \
  --telegram-env-file /opt/moltinger/.env \
  --json-out /opt/moltinger/.tmp/current/codex-upstream-watcher-report.json \
  --summary-out /opt/moltinger/.tmp/current/codex-upstream-watcher-summary.md \
  --stdout none
```

Что происходит:

1. watcher находит новое upstream-состояние
2. отправляет одно Telegram-сообщение
3. watcher создаёт shared consent record в `codex-telegram-consent-store`
4. в Telegram приходят явные affordances:
   - inline-кнопки
   - fallback-команды вида `/codex-followup accept <request_id> <token>`
5. дальнейший ответ должен принимать authoritative router, а не watcher-side `getUpdates`

Простыми словами:

- сначала приходит короткое уведомление
- затем пользователь видит явные токенизированные действия вместо неоднозначного `да/нет`
- ответ попадает в shared consent store и не должен зависеть от второго Telegram consumer-а

## Что изменилось в UX после feature 017

Теперь watcher больше не должен обещать диалог по свободному тексту `да/нет`, если authoritative router включён.

Пользовательский сценарий теперь такой:

1. приходит alert о новой версии Codex CLI;
2. в сообщении есть кнопки и явная fallback-команда;
3. authoritative router получает токенизированное действие;
4. shared store фиксирует `request_id`, `action_token`, `chat_id`, решение и срок действия окна.

Простыми словами:

- раньше watcher сам пытался позже прочитать ответ пользователя;
- теперь он только открывает корректно коррелированный запрос;
- входящий ответ должен обрабатывать основной Telegram ingress.

## Legacy fallback и граница текущего среза

Legacy path через Bot API `getUpdates` оставлен только как fallback для отключённого router path и для старых fixture-сценариев.

Полезные опции:

```bash
--telegram-consent-window-hours 72
--telegram-updates-file /path/to/updates.json
--telegram-allow-getupdates
```

Важно:

- live `getUpdates` по умолчанию выключен, чтобы watcher не конкурировал с основным consumer-ом Telegram-бота
- при включённом authoritative router watcher больше не должен быть владельцем production reply path
- включать `--telegram-allow-getupdates` стоит только в безопасном режиме: выделенный бот, maintenance-окно или гарантированно остановленный основной inbound-consumer
- если у бота активен webhook, watcher не полезет в `getUpdates` и зафиксирует это как ограничение
- если ответы Telegram временно недоступны, watcher не врёт и не отправляет рекомендации “как будто было согласие”
- legacy pending-состояние сохраняется в state-файле только при отключённом router path
- если окно ожидания истекло, follow-up закрывается как `expired`

## Shared consent store

Новый source of truth для authoritative path:

- script: `scripts/codex-telegram-consent-store.sh`
- default dir: `.tmp/current/codex-telegram-consent-store/`

Один record хранит:

- `request_id`
- `action_token`
- `chat_id`
- `fingerprint`
- срок действия окна
- prepared recommendation payload
- последнее зафиксированное решение

Это нужно, чтобы follow-up был коррелированным и audit-friendly, а не жил только внутри watcher state.

## Advisory issue signals

Дополнительные сигналы из тикетов добавляют контекст, но не заменяют официальный changelog.

```bash
./scripts/codex-cli-upstream-watcher.sh \
  --mode manual \
  --include-issue-signals \
  --issue-signals-url "https://api.github.com/repos/openai/codex/issues?state=open&per_page=20"
```

Простыми словами:

- changelog остаётся главным источником истины
- тикеты только усиливают или уточняют контекст

## Cron и GitOps

GitOps-managed cron-файл:

- `scripts/cron.d/moltis-codex-upstream-watcher`

Что делает cron-задача:

- пишет логи в `/var/log/moltis/codex-upstream-watcher.log`
- хранит state в `/opt/moltinger/.tmp/current/`
- читает Telegram credentials из `/opt/moltinger/.env`
- запускает watcher из репозитория, без ручного server-side drift

## Что лежит в JSON-отчёте

Основные разделы отчёта:

- `snapshot`
- `severity`
- `decision`
- `advisor_bridge`
- `followup`
- `automation`
- `state`

Самые важные поля:

- `snapshot.highlight_explanations`: русский пересказ основных изменений
- `severity.level`: насколько срочно проверять релиз
- `decision.status`: что делать прямо сейчас
- `followup.digest`: состояние дайджеста
- `followup.consent`: статус вопроса о практических рекомендациях
- `advisor_bridge.practical_recommendations`: готовые советы для проекта

## Понятная интерпретация статусов

- `deliver`: нужно отправить новое уведомление
- `suppress`: это состояние уже было обработано
- `queued`: событие добавлено в дайджест и ждёт отправки
- `retry`: отправка не удалась, нужно повторить позже
- `investigate`: данных недостаточно, требуется проверка

## Ограничения

- watcher не утверждает сам по себе, что локальный Codex CLI пользователя уже обновлён или отстаёт
- практические рекомендации строятся как bridge-слой и зависят от качества advisor-отчёта
- если Telegram transport работает, а чтение ответов временно недоступно, первое уведомление всё равно уйдёт, но follow-up может подождать следующего успешного run
