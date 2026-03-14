# Moltis Codex Update Skill

## Что это

Это новый канонический Moltis-native навык для отслеживания обновлений `Codex CLI`.

Простыми словами:
- Moltis сам проверяет официальный changelog;
- Moltis сам запоминает последнее увиденное состояние;
- Moltis сам отвечает пользователю по-русски;
- optional project profile помогает делать рекомендации более прикладными.

Этот путь заменяет старую гибридную модель, где canonical runtime жил в repo-side watcher scripts.
Старый watcher теперь нужен только как migration-only исторический материал и не должен восприниматься как основной пользовательский путь.

## Как это работает сейчас

На текущем implementation slice навык уже умеет:

1. прочитать официальный источник Codex CLI;
2. распознать свежую upstream-версию и её ключевые изменения;
3. понять, новое это состояние или уже виденное;
4. вернуть краткий русский summary;
5. при наличии project profile учесть его правила и profile-specific fallback.

На текущем срезе уже включено:
- scheduler duplicate suppression внутри самого Moltis-native runtime;
- Telegram delivery для scheduler path;
- явные delivery-статусы в state file: `not-attempted`, `deferred`, `not-configured`, `suppressed`, `sent`, `failed`.
- machine-readable audit mirror для manual и scheduler запусков.

На текущем implementation уровне уже закрыто всё внутри feature `023`.
Отдельно от этой ветки остаётся только production rollout/UAT, если оператор захочет включать live scheduler delivery на сервере.

## On-demand usage

Канонический операторский entrypoint:

```bash
make codex-update
```

Он запускает Moltis-native runtime в manual-режиме, включает issue signals и пишет артефакты в `.tmp/current/`.

Если нужен прямой runtime без Make target:

Прямой runtime:

```bash
bash scripts/moltis-codex-update-run.sh --mode manual
```

С project profile:

```bash
bash scripts/moltis-codex-update-run.sh \
  --mode manual \
  --profile-file tests/fixtures/codex-update-skill/project-profile-basic.json
```

С profile fallback без прямого keyword match:

```bash
bash scripts/moltis-codex-update-run.sh \
  --mode manual \
  --release-file tests/fixtures/codex-update-skill/releases-0.114.0.html \
  --profile-file tests/fixtures/codex-update-skill/project-profile-fallback.json
```

С fixture-источником:

```bash
bash scripts/moltis-codex-update-run.sh \
  --mode manual \
  --release-file tests/fixtures/codex-update-skill/releases-0.114.0.html \
  --include-issue-signals \
  --issue-signals-file tests/fixtures/codex-update-skill/issue-signals.json
```

## Scheduler path

Scheduler использует тот же runtime:

```bash
bash scripts/moltis-codex-update-run.sh --mode scheduler --stdout json
```

Если scheduler запущен на свежем upstream fingerprint и Telegram включён, Moltis:
1. вычисляет fingerprint;
2. сравнивает его с `last_alert_fingerprint`;
3. отправляет одно сообщение только для нового fingerprint;
4. на повторном запуске пишет `suppressed` вместо дубля.

Пример hermetic scheduler-run:

```bash
bash scripts/moltis-codex-update-run.sh \
  --mode scheduler \
  --release-file tests/fixtures/codex-update-skill/releases-0.114.0.html \
  --include-issue-signals \
  --issue-signals-file tests/fixtures/codex-update-skill/issue-signals.json \
  --telegram-enabled \
    --telegram-chat-id 262872984 \
    --stdout json
```

## Audit trail

Каждый запуск теперь оставляет два машиночитаемых артефакта:

- JSON audit record
- Markdown summary

По умолчанию audit mirror живёт здесь:

```text
.tmp/current/moltis-codex-update-audit/
```

Внутри report теперь есть блок:

- `audit.dir`
- `audit.record_path`
- `audit.summary_path`
- `audit.written_at`

А state file дополнительно хранит:

- `last_run_id`
- `last_audit_record`
- `last_audit_summary`
- `last_audit_written_at`

Простыми словами:
- оператор теперь может посмотреть не только текущее state, но и конкретный файл последнего прогона;
- это одинаково работает и для ручного запуска, и для scheduler path.

## State helper

Состояние навыка живёт через:

```bash
bash scripts/moltis-codex-update-state.sh get
```

По умолчанию state file:

```text
.tmp/current/moltis-codex-update-state.json
```

Теперь state также хранит:
- последний delivery status;
- время последней попытки отправки;
- delivery error, если отправка не удалась;
- `last_alert_message_id` для успешного Telegram alert.
- `last_run_id` для связки state с audit record;
- ссылки на последний audit JSON и summary.

## Profile helper

Проверка профиля:

```bash
bash scripts/moltis-codex-update-profile.sh validate \
  --file tests/fixtures/codex-update-skill/project-profile-basic.json
```

Загрузка нормализованного профиля:

```bash
bash scripts/moltis-codex-update-profile.sh load \
  --file tests/fixtures/codex-update-skill/project-profile-basic.json
```

## Stable profile contract

Теперь stable profile contract включает:
- `relevance_rules[]` с:
  - `id`
  - `keywords`
  - `title_ru`
  - `rationale_ru`
  - `next_steps_ru[]`
  - optional `priority_paths[]`
  - optional `recommendation_template_id`
- `recommendation_templates[]` с готовыми заголовками, rationale и шагами
- `fallback_recommendation`, которая используется, если профиль валиден, но ни одно правило не совпало

Простыми словами:
- если правило совпало, Moltis строит recommendation из rule + template;
- если профиль есть, но прямого совпадения нет, Moltis всё равно даёт project-specific совет, а не сваливается в полностью generic ответ;
- если профиль сломан, upstream advisory всё равно возвращается, но в notes честно появляется ошибка профиля.

## Что пользователь должен получить

Если пользователь пишет:

```text
Проверь обновления Codex CLI
```

Moltis должен ответить простым русским summary:
- вышло ли новое upstream-обновление;
- насколько это важно;
- почему это важно;
- какие следующие шаги разумны.

Если profile загружен:
- recommendation bundle должен показывать, что источник рекомендаций — профиль;
- matched rule попадает в audit через `source_rule_id`;
- fallback profile recommendation не притворяется match-ом и оставляет `source_rule_id` пустым.

## Деградация

Если официальный источник недоступен или changelog поменял формат:
- навык должен честно вернуть `нужно проверить`;
- он не должен угадывать или выдавать ложный `upgrade-now`.

Если scheduler не может отправить alert:
- `not-configured` означает, что Telegram delivery не включён или не найден `chat_id`;
- `failed` означает, что sender был вызван, но Telegram вернул ошибку;
- `suppressed` означает, что этот fingerprint уже отправлялся раньше;
- `deferred` означает, что upstream-источник пока нельзя оценить надёжно.

Если profile-path деградирует:
- `profile.status = invalid` и ошибки пишутся в `.profile.errors`;
- generic upstream advisory остаётся доступным;
- false project-specific рекомендаций появляться не должно.

## Scheduler ownership и GitOps rollout

Канонический scheduler path теперь принадлежит Moltis-native skill:

```text
scripts/moltis-codex-update-run.sh --mode scheduler
```

GitOps wiring:
- runtime defaults живут в [config/moltis.toml](/Users/rl/coding/moltinger-molt-2-codex-update-monitor-new/config/moltis.toml)
- cron job живёт в [moltis-codex-upstream-watcher](/Users/rl/coding/moltinger-molt-2-codex-update-monitor-new/scripts/cron.d/moltis-codex-upstream-watcher)
- inventory зафиксирован в [manifest.json](/Users/rl/coding/moltinger-molt-2-codex-update-monitor-new/scripts/manifest.json)

Минимальные env для live scheduler delivery:

```text
MOLTIS_CODEX_UPDATE_TELEGRAM_ENABLED=true
MOLTIS_CODEX_UPDATE_TELEGRAM_ENV_FILE=/opt/moltinger/.env
```

Опционально можно задать явный chat id:

```text
MOLTIS_CODEX_UPDATE_TELEGRAM_CHAT_ID=<chat_id>
```

Если `chat_id` не задан явно, runtime пытается взять его из `.env`, а затем fallback-ом использует первый идентификатор из `TELEGRAM_ALLOWED_USERS`.

## Hermetic proof

Для полного доказательства нового пути теперь есть отдельный helper:

```bash
make codex-update-e2e
```

Он проверяет:

1. manual run с project profile;
2. scheduler run с одной реальной отправкой;
3. повторный scheduler run с duplicate suppression;
4. наличие audit files для обоих путей.

Артефакт по умолчанию:

```text
.tmp/current/moltis-codex-update-e2e-report.json
```

Простыми словами:
- это короткий hermetic proof, что Moltis-owned skill действительно умеет полный путь `manual -> scheduler -> delivery/suppress`;
- он нужен как инженерное доказательство перед live rollout.

## Rollback и migration-off

Если новый путь нужно быстро откатить:

1. оставить `MOLTIS_CODEX_UPDATE_TELEGRAM_ENABLED=false`, чтобы scheduler перестал отправлять Telegram;
2. сохранить Moltis-native on-demand skill как источник ручной проверки;
3. не возвращать старые `/codex_*` reply UX и старый interactive consent flow;
4. воспринимать `docs/codex-cli-upstream-watcher.md` только как migration-only reference.

Если нужно полностью заморозить этот feature в runtime:

- отключается scheduler invoke;
- state и audit artifacts сохраняются для диагностики;
- пользовательский on-demand запрос можно временно оставить как read-only проверку без доставки.

## Migration note

Старый гибридный advisory path остаётся только как временный migration fallback.
Новый canonical target для этой функции — `023-full-moltis-codex-update-skill`.
Канонический локальный entrypoint для оператора теперь: `make codex-update`.
