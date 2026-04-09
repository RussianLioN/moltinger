# Moltis-Native Codex Advisory Flow

## Статус

На `2026-04-09` authoritative Telegram-contract для advisory flow считается такой:

- watcher и advisor в этом репозитории только готовят нормализованный сигнал;
- Moltis должен быть единственным владельцем Telegram alert UX;
- production-safe default остаётся `one_way_only`, потому что официальный контракт Moltis пока не даёт этому репозиторию честно включить интерактивный Telegram follow-up.

## Простыми словами

Теперь у фичи две чёткие части:

1. Этот репозиторий отвечает на вопрос: `что нового в Codex CLI и что это значит для проекта`.
2. Moltis отвечает на вопрос: `как показать это пользователю в Telegram и как принять его действие`.

Это сделано специально, чтобы больше не повторять старую ошибку, когда repo-side script задавал вопрос в Telegram, а ответ перехватывал generic Moltis chat.

Причина теперь зафиксирована явно:

- в официальной документации Moltis Telegram channel не заявляет interactive components;
- `MessageReceived` и `Command` hooks остаются read-only, то есть не могут терминально перехватить ingress раньше generic chat.

## Новый producer contract

Watcher теперь должен уметь выдавать нормализованный `CodexAdvisoryEvent`.

Канонический schema path:

```bash
specs/021-moltis-native-codex-update-advisory/contracts/advisory-event.schema.json
```

Смысл контракта:

- `summary_ru` и `why_it_matters_ru` дают человеку короткое объяснение;
- `highlights_ru[]` содержат простые русские тезисы для alert;
- `recommendation_payload` содержит project-facing follow-up;
- `interactive_followup_eligible` говорит Moltis, можно ли вообще показывать inline-действия.

## Новый Moltis-facing intake

В репозитории добавлен helper:

```bash
scripts/moltis-codex-advisory-intake.sh
```

Он принимает уже нормализованный advisory event и делает одну из двух вещей:

- contract preview path: может отрендерить interactive-ready артефакт для hermetic/handoff проверки;
- production-safe path: рендерит честный `one-way alert` без `/codex_*`.

Важно:

- этот helper не должен снова становиться “вторым владельцем Telegram”;
- его задача здесь — зафиксировать contract, текст уведомления, audit record и repo-managed runtime surface;
- interactive preview не равен live Telegram capability;
- конечный callback UX всё равно должен жить внутри Moltis core.

## Advisory session store и router

Для contract/handoff surface есть ещё два helper-а:

```bash
scripts/codex-advisory-session-store.sh
scripts/moltis-codex-advisory-router.sh
```

Их роли разделены так:

- `codex-advisory-session-store.sh` хранит pending advisory session, message id, статус callback-а и результат follow-up delivery;
- `moltis-codex-advisory-router.sh` принимает `callback_query` или recovery-команду, валидирует chat binding и expiry, а затем либо отправляет рекомендации, либо честно закрывает advisory как `decline`/`expired`/`duplicate`.

Локальный каталог session store по умолчанию:

```bash
.tmp/current/codex-advisory-session-store
```

Важно:

- recovery-команда теперь есть только как запасной путь восстановления в hermetic contract;
- она не должна рекламироваться как primary UX в самом Telegram alert;
- primary UX для пользователя в production сейчас вообще не интерактивный: Telegram advisory остаётся one-way.

## Audit record

Intake helper пишет machine-readable record в:

```bash
/opt/moltinger/.tmp/current/codex-advisory-intake-audit
```

Локально по умолчанию:

```bash
.tmp/current/codex-advisory-intake-audit
```

В audit record должны быть:

- `event_id`
- `upstream_fingerprint`
- `alert_id`
- `chat_id`
- `message_id`
- `interactive_mode`
- `decision`
- `decision_source`
- `followup_status`
- `degraded_reason`

## Config handoff для Moltis

Repository-managed config теперь фиксирует такие env keys:

- `MOLTIS_CODEX_ADVISORY_EVENT_SCHEMA`
- `MOLTIS_CODEX_ADVISORY_INTAKE_SCRIPT`
- `MOLTIS_CODEX_ADVISORY_AUDIT_DIR`
- `MOLTIS_CODEX_ADVISORY_TELEGRAM_SEND_SCRIPT`
- `MOLTIS_CODEX_ADVISORY_TELEGRAM_ENV_FILE`
- `MOLTIS_CODEX_ADVISORY_INTERACTIVE_MODE`
- `MOLTIS_CODEX_ADVISORY_SESSION_STORE_SCRIPT`
- `MOLTIS_CODEX_ADVISORY_SESSION_STORE_DIR`
- `MOLTIS_CODEX_ADVISORY_ROUTER_SEND_SCRIPT`
- `MOLTIS_CODEX_ADVISORY_ROUTER_ENV_FILE`
- `MOLTIS_CODEX_ADVISORY_ROUTER_SEND_REPLY`
- `MOLTIS_CODEX_ADVISORY_CALLBACK_WINDOW_HOURS`
- `MOLTIS_CODEX_ADVISORY_RECOVERY_COMMAND`

Пока `MOLTIS_CODEX_ADVISORY_INTERACTIVE_MODE` должен оставаться `one_way_only`.
В этом репозитории это уже не условная осторожность, а зафиксированный production contract до появления upstream Moltis capability для terminal Telegram ingress.

## Минимальная локальная проверка

1. Сгенерировать advisory event из watcher-а:

```bash
bash scripts/codex-cli-upstream-watcher.sh \
  --mode manual \
  --release-file tests/fixtures/codex-upstream-watcher/releases-0.114.0.html \
  --include-issue-signals \
  --issue-signals-file tests/fixtures/codex-upstream-watcher/issue-signals.json \
  --advisory-event-out .tmp/current/codex-advisory-event.json \
  --stdout none
```

2. Прогнать intake в preview mode:

```bash
bash scripts/moltis-codex-advisory-intake.sh \
  --event-file .tmp/current/codex-advisory-event.json \
  --chat-id 262872984 \
  --interactive-mode inline_callbacks \
  --stdout summary
```

3. Hermetic contract path: alert -> accept -> recommendations:

```bash
make codex-advisory-e2e
```

4. Принудительно проверить degraded path:

```bash
bash scripts/moltis-codex-advisory-intake.sh \
  --event-file tests/fixtures/codex-advisory-events/advisory-event-interactive-ready.json \
  --force-one-way \
  --stdout summary
```

Артефакт hermetic proof по умолчанию:

```bash
.tmp/current/codex-advisory-e2e-report.json
```

Этот отчёт уже содержит:

- текст alert для contract-preview path;
- текст follow-up рекомендаций;
- вшитый audit record для interactive path;
- вшитый audit record для degraded path.

## Verification checklist

Перед review достаточно пройти такой минимальный набор:

```bash
./scripts/sync-claude-skills-to-codex.sh --check
make codex-check
bash tests/component/test_moltis_codex_advisory_intake.sh
bash tests/component/test_moltis_codex_advisory_router.sh
make codex-advisory-e2e
```

Простыми словами:

- bridge остаётся в синхроне;
- runtime docs/config не расходятся;
- one-way contract доказан;
- hermetic handoff surface доказан;
- audit trail виден в одном JSON-артефакте.

## Safe Disable и Rollback

Если interactive advisory path когда-нибудь появится upstream и его временно нельзя будет держать включённым, безопасный rollback должен быть только конфигурационным:

1. Оставить `MOLTIS_CODEX_ADVISORY_INTERACTIVE_MODE=one_way_only`.
2. Не подключать или временно отключить Moltis callback hook для `moltis-codex-advisory-router.sh`.
3. Не удалять producer-side advisory event emission и intake surface: one-way alert должен продолжать работать.
4. Прогнать preview/verification и убедиться, что alert не показывает inline actions и не обещает follow-up.

Минимальная проверка после safe-disable:

```bash
bash scripts/moltis-codex-advisory-intake.sh \
  --event-file tests/fixtures/codex-advisory-events/advisory-event-interactive-ready.json \
  --interactive-mode one_way_only \
  --stdout summary
```

Ожидаемое поведение после rollback:

- alert остаётся русским и полезным;
- пользователь получает только one-way уведомление;
- audit record сохраняет `degraded_reason`;
- никаких `/codex_*` и ложных интерактивных обещаний больше нет.

## Что не нужно делать

Не нужно снова вводить пользователю команды вида:

- `/codex_da`
- `/codex_net`
- `/codex-followup ...`

Это больше не считается допустимым production UX для advisory flow.
