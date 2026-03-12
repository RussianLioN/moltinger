# Монитор обновлений Codex CLI

`codex-cli-upstream-watcher.sh` следит за официальным changelog Codex CLI, не требует установленного `codex` на хосте Moltinger и умеет:

- понять, появилось ли новое upstream-состояние
- показать важность этого изменения простым русским языком
- собирать события в дайджест, чтобы не шуметь
- подготовить bridge к проектным рекомендациям через advisor-слой
- подготовить данные для project-facing рекомендаций, а в production пока отправлять только one-way alert до live rollout Moltis-native advisory flow
- эмитить нормализованный `CodexAdvisoryEvent` для Moltis-native advisory flow

Инструмент по-прежнему разделяет две задачи:

- upstream watcher отвечает на вопрос: «Что нового у Codex CLI вообще?»
- advisor bridge помогает ответить на вопрос: «Что из этого стоит проверить именно в этом проекте?»

## Статус на 2026-03-13

Текущий baseline `main` по-прежнему безопасный, а эта rollout-ветка уже готовит live-переключение:

- baseline `main`: Telegram-уведомление работает как `one-way alert`;
- rollout branch `moltinger-ewde`: watcher уже переводится на Moltis-native advisory sender adapter;
- старый repo-side интерактивный consent flow выведен из пользовательской эксплуатации;
- любые ответы вида `/codex_*` считаются устаревшим путём и не должны предлагаться пользователю;
- producer contract и Moltis-facing intake описаны в [codex-moltis-native-advisory.md](/Users/rl/coding/moltinger-ewde-codex-advisory-rollout/docs/codex-moltis-native-advisory.md).

Простыми словами:

- watcher по-прежнему полезен как producer upstream-сигнала;
- но сам Telegram-диалог с пользователем теперь не должен жить в repo-side Codex bridge.

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

## Telegram-уведомления и live rollout wiring

Для rollout production path теперь выглядит так:

1. cron запускает watcher;
2. watcher пишет `CodexAdvisoryEvent` в `CODEX_UPSTREAM_WATCHER_ADVISORY_EVENT_OUT`;
3. watcher вызывает `moltis-codex-advisory-send.sh` вместо прямого Bot API sender-а;
4. sender-adapter передаёт доставку в `moltis-codex-advisory-intake.sh`;
5. intake отправляет alert и создаёт advisory session;
6. Moltis router hook принимает callback и шлёт follow-up рекомендации.

Пример запуска:

```bash
./scripts/codex-cli-upstream-watcher.sh \
  --mode scheduler \
  --include-issue-signals \
  --telegram-enabled \
  --advisory-event-out /opt/moltinger/.tmp/current/codex-advisory-event.json \
  --telegram-env-file /opt/moltinger/.env \
  --json-out /opt/moltinger/.tmp/current/codex-upstream-watcher-report.json \
  --summary-out /opt/moltinger/.tmp/current/codex-upstream-watcher-summary.md \
  --stdout none
```

Что происходит в rollout path:

1. watcher находит новое upstream-состояние;
2. пишет advisory event в файл;
3. отдаёт отправку не напрямую, а через `moltis-codex-advisory-send.sh`;
4. Moltis-native intake решает, нужно ли открывать interactive advisory session;
5. Telegram-пользовательский диалог больше не живёт внутри watcher-а.

Для cron на сервере используются такие ключи:

```bash
MOLTIS_CONFIG_FILE=/opt/moltinger/config/moltis.toml
CODEX_UPSTREAM_WATCHER_ADVISORY_EVENT_OUT=/opt/moltinger/.tmp/current/codex-advisory-event.json
CODEX_UPSTREAM_WATCHER_TELEGRAM_SEND_SCRIPT=/opt/moltinger/scripts/moltis-codex-advisory-send.sh
CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_ENABLED=false
MOLTIS_CODEX_ADVISORY_INTAKE_SCRIPT=/opt/moltinger/scripts/moltis-codex-advisory-intake.sh
```

Простыми словами:

- watcher больше не должен сам управлять интерактивным Telegram UX;
- watcher только детектирует событие и передаёт его в Moltis-native слой;
- интерактивность включается не флагом внутри watcher-а, а живым runtime wiring через intake/router.

## Исторический контекст feature 017

Ниже по документу и в связанных acceptance-артефактах могут встречаться материалы `017-codex-telegram-consent-routing`.
Их нужно воспринимать как инженерный контекст и промежуточный исследовательский слой, а не как текущий production UX.

То есть:

- `017` помог подтвердить архитектурную проблему;
- production больше не должен повторять его старый интерактивный UX;
- follow-up рекомендации в Telegram должны вернуться только после Moltis-native переноса.

## Acceptance path для текущего Moltis-native flow

Для acceptance-проверки сценария `alert -> accept -> recommendations` теперь есть отдельный helper:

```bash
make codex-advisory-e2e
```

Он делает три вещи подряд:

1. поднимает fresh advisory alert на fixture-входах;
2. проводит `accept` через текущий Moltis-native advisory router;
3. проверяет degraded режим, где alert становится one-way only и audit record сохраняет причину.

Артефакт по умолчанию:

- `.tmp/current/codex-advisory-e2e-report.json`

Простыми словами:

- это короткий hermetic proof для текущего `021` flow;
- он подтверждает, что alert, callback и follow-up работают как один целый путь;
- и отдельно доказывает честный safe-degrade.

## Rollout

Безопасный порядок включения такой:

1. убедиться, что доступны `moltis-codex-advisory-send.sh`, `moltis-codex-advisory-intake.sh`, `moltis-codex-advisory-router.sh` и `codex-advisory-session-store.sh`;
2. проверить, что cron использует `CODEX_UPSTREAM_WATCHER_TELEGRAM_SEND_SCRIPT=/opt/moltinger/scripts/moltis-codex-advisory-send.sh`;
3. проверить, что advisory runtime не остаётся принудительно в `one_way_only`;
4. прогнать `make codex-advisory-e2e`;
5. прогнать component rollout checks;
6. только потом подтверждать live interactive advisory path в Moltis runtime.

Если этот порядок соблюдён, пользователь получает:

- alert с явным действием;
- мгновенный follow-up после `accept`;
- no-spam idempotent behavior на повторах.

## Rollback

Если interactive advisory path временно нельзя держать включённым, rollback простой:

- вернуть `MOLTIS_CODEX_ADVISORY_INTERACTIVE_MODE=one_way_only`;
- вернуть watcher на обычный sender вместо `moltis-codex-advisory-send.sh`, если нужно снять adapter path целиком;
- не подключать advisory callback hook в Moltis ingress;
- оставить watcher как producer и Telegram как one-way alert.

Тогда watcher деградирует безопасно:

- отправляет только one-way alert;
- не просит пользователя отвечать на неработающий вопрос;
- не создаёт ложное ожидание follow-up.

Это и есть рекомендованный rollback до исправления transport/ingress-проблем.

## Observability

Главные места для проверки:

- watcher JSON report: `followup.consent.*`, `automation.alert.*`, `telegram_target.*`
- consent store record: `request.status`, `delivery.status`, `decision.*`
- helper artifact: `.tmp/current/codex-telegram-consent-e2e-report.json`
- scheduler log: `/var/log/moltis/codex-upstream-watcher.log`

На что смотреть в первую очередь:

- `consent_router_ready`
- `router_mode`
- `delivery.status`
- `request.status`
- наличие/отсутствие consent question в самом alert-тексте

## Когда watcher задаёт вопрос, а когда нет

Watcher теперь спрашивает о практических рекомендациях только тогда, когда authoritative consent router реально готов:

- router path включён;
- доступен shared consent store helper;
- alert можно безопасно связать с `request_id` и `action_token`.

Если router path недоступен, watcher деградирует в one-way alert:

- отправляет только уведомление об обновлении;
- не обещает сломанный follow-up;
- не просит пользователя отвечать на вопрос, который никто не обработает корректно.

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
