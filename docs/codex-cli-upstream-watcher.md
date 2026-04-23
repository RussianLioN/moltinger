# Монитор обновлений Codex CLI

> Статус: migration-only reference.
> Канонический путь для этой функции теперь описан в [docs/moltis-codex-update-skill.md](/Users/rl/coding/moltinger-molt-2-codex-update-monitor-new/docs/moltis-codex-update-skill.md).
> Для ручной канонической проверки используй `make codex-update`, а не старые watcher/advisor/delivery entrypoint-ы.
> Legacy consent-флаги watcher-а теперь no-op: старый `/codex_*` interactive UX принудительно выведен из эксплуатации.

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

## Статус на 2026-03-12

Текущий live production UX намеренно ограничен:

- Telegram-уведомление работает как `one-way alert`;
- старый repo-side интерактивный consent flow выведен из пользовательской эксплуатации;
- любые ответы вида `/codex_*` считаются устаревшим путём и не должны предлагаться пользователю;
- новый интерактивный advisory flow уже реализуется в Moltis-native runtime surface, но production-safe default пока не переведён из `one-way alert`.
- producer contract и Moltis-facing intake описаны в [docs/codex-moltis-native-advisory.md](/Users/rl/coding/moltinger-molt-2-codex-update-monitor-new/docs/codex-moltis-native-advisory.md).

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

## Telegram-уведомления и текущий безопасный режим

В production scheduler-режим сейчас должен отправлять только `one-way alert`.

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

Что происходит сейчас:

1. watcher находит новое upstream-состояние;
2. отправляет одно Telegram-сообщение;
3. не предлагает follow-up вопрос, reply-команды или callback-кнопки;
4. practical recommendations остаются отдельным следующим шагом, а не repo-side Telegram dialogue.

Важно для production:

- repo-side watcher должен работать только как one-way alert;
- это не временный флаг, а следствие текущего официального контракта Moltis:
  - Telegram channel не заявляет interactive components;
  - `MessageReceived` уже умеет modify/block inbound text, но `Command` остаётся read-only, а callback/follow-up UX без interactive components всё равно не на что безопасно навесить;
- поэтому watcher не задаёт вопрос о рекомендациях и не показывает кнопки, чтобы не создавать ложное ожидание сломанного follow-up.

Простыми словами:

- сейчас пользователю должно приходить только короткое уведомление;
- никакие `/codex_da`, `/codex_net` и похожие reply-команды больше не считаются допустимым live UX;
- следующий live шаг зависит не от read-only ingress myth, а от появления честного interactive Telegram UX поверх Moltis.

Важно:

- даже если watcher запущен на том же host, интерактивный follow-up для Telegram здесь не включается;
- `CODEX_UPSTREAM_WATCHER_TELEGRAM_COMMAND_HOOK_READY` и похожие legacy flags больше не должны влиять на live UX;
- router/store helper-ы в репозитории остаются как hermetic contract/handoff surface, а не как доказанный production ingress path.

## Исторический контекст feature 017

Ниже по документу и в связанных acceptance-артефактах могут встречаться материалы `017-codex-telegram-consent-routing`.
Их нужно воспринимать как инженерный контекст и промежуточный исследовательский слой, а не как текущий production UX.

То есть:

- `017` помог подтвердить архитектурную проблему;
- production больше не должен повторять его старый интерактивный UX;
- follow-up рекомендации в Telegram должны вернуться только после Moltis-native переноса.

## Acceptance path для текущего Moltis-native flow

Для acceptance-проверки contract/handoff surface есть отдельный helper:

```bash
make codex-advisory-e2e
```

Он делает три вещи подряд в hermetic-среде:

1. поднимает fresh advisory alert на fixture-входах;
2. проводит `accept` через текущий Moltis-native advisory router;
3. проверяет degraded режим, где alert становится one-way only и audit record сохраняет причину.

Артефакт по умолчанию:

- `.tmp/current/codex-advisory-e2e-report.json`

Простыми словами:

- это hermetic proof для shell-contract и audit-model, а не live-proof Telegram ingress;
- он полезен как handoff surface для будущего upstream/runtime path;
- он отдельно доказывает честный safe-degrade.

## Rollout

В текущем состоянии включать live interactive advisory path для Telegram из этого репозитория не нужно.

Безопасный порядок сейчас такой:

1. оставить watcher в one-way режиме;
2. не пытаться включать repo-managed callback router через hook config;
3. использовать `make codex-advisory-e2e` только как hermetic contract check;
4. ждать upstream Moltis capability, которая даст настоящий terminal Telegram ingress.

## Rollback

Если interactive advisory path временно нельзя держать включённым, rollback простой:

- вернуть `MOLTIS_CODEX_ADVISORY_INTERACTIVE_MODE=one_way_only`;
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
- repo-side baseline helper artifact: `.tmp/current/codex-telegram-consent-e2e-report.json`
- Moltis-native advisory artifact: `.tmp/current/codex-advisory-e2e-report.json`
- Moltis-native advisory session/audit records: `interaction_record.*`, `followup_status`, `degraded_reason`
- scheduler log: `/var/log/moltis/codex-upstream-watcher.log`

На что смотреть в первую очередь:

- `consent_router_ready`
- `router_mode`
- `interaction_record.followup_status`
- `degraded_reason`
- наличие/отсутствие consent question в самом alert-тексте

## Когда watcher задаёт вопрос, а когда нет

В текущем repo-side baseline watcher больше не задаёт вопрос о практических рекомендациях вообще.

Причина простая:

- старый repo-side consent UX выведен из эксплуатации;
- authoritative follow-up path должен жить в Moltis-native runtime, а не в watcher-скрипте;
- до подтверждённого Moltis-native interactive transport watcher обязан оставаться честным one-way notifier.

Практически это значит:

- scheduler alert сообщает только о новом Codex advisory;
- в тексте больше не должно быть вопроса `Хотите получить практические рекомендации`;
- watcher не должен показывать legacy-команды вроде `/codex_da`;
- `followup.consent.status` в report остаётся `disabled`, а `router_mode` остаётся `one_way_only`.

## Что изменилось в UX после feature 017

Feature 017 зафиксировал правильную архитектурную границу: интерактивный ответ должен обрабатываться основным Moltis ingress, а не repo-side watcher.

На текущем срезе это означает:

1. watcher остаётся producer/notifier;
2. repo-side interactive follow-up больше не рекламируется пользователю;
3. helper `codex-telegram-consent-e2e` теперь доказывает честный one-way baseline и safe degraded fallback, а не старый `alert -> consent -> recommendations` путь.

Простыми словами:

- раньше repo-side helper проверял устаревший consent flow;
- теперь он проверяет, что watcher не врёт пользователю про несуществующий interactive path;
- интерактивное продолжение должно вернуться только через Moltis-native runtime.

## Legacy fallback и граница текущего среза

Legacy path через Bot API `getUpdates` и reply-команды больше не входит в живой production contract watcher-а.

Важно:

- старые compatibility flags сохраняются только как no-op surface, чтобы не ломать старые вызовы скрипта;
- watcher не должен читать ответы пользователя и не должен строить pending consent-state;
- если нужна реальная интерактивность в Telegram, это уже отдельная upstream/runtime задача, а не скрытый режим watcher-а.

## Moltis-native advisory session store

Для будущего interactive path source of truth должен находиться уже не в repo-side consent store, а в Moltis-native advisory session store:

- script: `scripts/codex-advisory-session-store.sh`
- default dir: `.tmp/current/codex-advisory-session-store/`

Один record хранит:

- advisory session identity
- chat binding и fingerprint
- callback/interation status
- follow-up delivery outcome
- degraded reason, если interactive path был выключен

Важно:

- `codex-telegram-consent-e2e` не должен создавать repo-side consent records;
- repo-side helper доказывает только honest one-way baseline;
- advisory session store и router helper в этом репозитории сейчас выступают как handoff/contract artifacts, а не как live Telegram capability.

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
