# Moltis Codex Update Skill

## Что это

Это новый канонический Moltis-native навык для отслеживания обновлений `Codex CLI`.

Простыми словами:
- Moltis сам проверяет официальный changelog;
- Moltis сам запоминает последнее увиденное состояние;
- Moltis сам отвечает пользователю по-русски;
- optional project profile помогает делать рекомендации более прикладными.

Этот путь заменяет старую гибридную модель, где canonical runtime жил в repo-side watcher scripts.

## Как это работает сейчас

На текущем implementation slice навык уже умеет:

1. прочитать официальный источник Codex CLI;
2. распознать свежую upstream-версию и её ключевые изменения;
3. понять, новое это состояние или уже виденное;
4. вернуть краткий русский summary;
5. при наличии project profile учесть его правила.

На текущем срезе уже включено:
- scheduler duplicate suppression внутри самого Moltis-native runtime;
- Telegram delivery для scheduler path;
- явные delivery-статусы в state file: `not-attempted`, `deferred`, `not-configured`, `suppressed`, `sent`, `failed`.

Пока ещё не закрыто целиком:
- live rollout/UAT production scheduler path;
- финальный retirement старого migration fallback path.

## On-demand usage

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

## Profile helper

Проверка профиля:

```bash
bash scripts/moltis-codex-update-profile.sh validate \
  --file tests/fixtures/codex-update-skill/project-profile-basic.json
```

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

## Деградация

Если официальный источник недоступен или changelog поменял формат:
- навык должен честно вернуть `нужно проверить`;
- он не должен угадывать или выдавать ложный `upgrade-now`.

Если scheduler не может отправить alert:
- `not-configured` означает, что Telegram delivery не включён или не найден `chat_id`;
- `failed` означает, что sender был вызван, но Telegram вернул ошибку;
- `suppressed` означает, что этот fingerprint уже отправлялся раньше;
- `deferred` означает, что upstream-источник пока нельзя оценить надёжно.

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

## Migration note

Старый гибридный advisory path остаётся только как временный migration fallback.
Новый canonical target для этой функции — `023-full-moltis-codex-update-skill`.
