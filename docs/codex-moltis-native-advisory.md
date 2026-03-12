# Moltis-Native Codex Advisory Flow

## Статус

На `2026-03-12` Telegram-ownership для advisory flow считается такой:

- watcher и advisor в этом репозитории только готовят нормализованный сигнал;
- Moltis должен быть единственным владельцем Telegram alert UX;
- production-safe default остаётся `one_way_only`, пока callback path в Moltis не подтверждён end-to-end.

## Простыми словами

Теперь у фичи две чёткие части:

1. Этот репозиторий отвечает на вопрос: `что нового в Codex CLI и что это значит для проекта`.
2. Moltis отвечает на вопрос: `как показать это пользователю в Telegram и как принять его действие`.

Это сделано специально, чтобы больше не повторять старую ошибку, когда repo-side script задавал вопрос в Telegram, а ответ перехватывал generic Moltis chat.

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

- healthy path: рендерит alert с inline callback-ready markup;
- degraded path: рендерит честный `one-way alert` без `/codex_*`.

Важно:

- этот helper не должен снова становиться “вторым владельцем Telegram”;
- его задача здесь — зафиксировать contract, текст уведомления, audit record и repo-managed runtime surface;
- конечный callback UX всё равно должен жить внутри Moltis core.

## Audit record

Intake helper пишет machine-readable record в:

```bash
/opt/moltinger/.tmp/current/codex-advisory-intake-audit
```

Локально по умолчанию:

```bash
.tmp/current/codex-advisory-intake-audit
```

В record должны быть:

- `event_id`
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

Пока `MOLTIS_CODEX_ADVISORY_INTERACTIVE_MODE` должен оставаться `one_way_only`, если Moltis runtime не подтвердил рабочий callback ingress.

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
  --stdout summary
```

3. Принудительно проверить degraded path:

```bash
bash scripts/moltis-codex-advisory-intake.sh \
  --event-file tests/fixtures/codex-advisory-events/advisory-event-interactive-ready.json \
  --force-one-way \
  --stdout summary
```

## Что не нужно делать

Не нужно снова вводить пользователю команды вида:

- `/codex_da`
- `/codex_net`
- `/codex-followup ...`

Это больше не считается допустимым production UX для advisory flow.
