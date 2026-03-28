# On-Demand Telegram Remote UAT

Канонический ручной post-deploy UAT для Moltinger.

## Что это теперь делает

- Один authoritative запуск через `Telegram Web`.
- Один review-safe JSON artifact как основной verdict.
- Опциональный restricted debug bundle только по явному запросу.
- Опциональный `MTProto` только как secondary diagnostics после primary verdict.
- Production transport mode не меняется и остается `polling`.

## Что это больше не делает

- Не продвигает remote UAT в blocking PR/main CI.
- Не включает scheduler или постоянный production spam.
- Не использует `synthetic` или `real_user` как основной operator entrypoint.

## GitHub Workflow

Workflow: `.github/workflows/telegram-e2e-on-demand.yml`

Запуск:

```bash
gh workflow run telegram-e2e-on-demand.yml \
  -f message='/status' \
  -f timeout_sec='45' \
  -f operator_intent='post_deploy_verification' \
  -f run_secondary_mtproto=false \
  -f upload_restricted_debug=false \
  -f artifact_name='telegram-remote-uat' \
  -f verbose=false
```

### Inputs

- `message` — probe message/command, по умолчанию `/status`
- `timeout_sec` — timeout ожидания ответа
- `operator_intent` — причина запуска (`post_deploy_verification`, `rerun_after_fix` и т.д.)
- `run_secondary_mtproto` — включить secondary MTProto diagnostics
- `upload_restricted_debug` — загрузить restricted debug bundle
- `artifact_name` — имя артефакта
- `verbose` — verbose wrapper logs

### Что делает workflow

1. Берет SSH-доступ через `SSH_PRIVATE_KEY`.
2. Идет на production target `root@ainetic.tech`.
3. Копирует текущие checkout-версии wrapper/probe во временную директорию под `/opt/moltinger/.tmp/`.
4. Запускает authoritative wrapper против production-aware target без изменения deploy state.
5. Возвращает review-safe JSON artifact.
6. При opt-in возвращает restricted debug bundle отдельным artifact.

### Guardrails

- workflow serializes runs через `concurrency: telegram-remote-uat-production`
- wrapper serializes shared target через lock file
- `TELEGRAM_TEST_*` secrets больше не висят job-wide на всех шагах
- restricted debug не загружается по умолчанию

## CLI Wrapper

Скрипт: `scripts/telegram-e2e-on-demand.sh`

Основной режим:

```bash
./scripts/telegram-e2e-on-demand.sh \
  --mode authoritative \
  --message '/status' \
  --timeout-sec 45 \
  --output /tmp/telegram-e2e-result.json
```

С secondary MTProto diagnostics:

```bash
./scripts/telegram-e2e-on-demand.sh \
  --mode authoritative \
  --secondary-diagnostics mtproto \
  --message '/status' \
  --timeout-sec 45 \
  --output /tmp/telegram-e2e-result.json \
  --debug-output /tmp/telegram-e2e-debug.json
```

## Review-Safe Artifact Contract

Основной JSON теперь имеет каноническую структуру:

- `schema_version`
- `run`
- `failure`
- `attribution_evidence`
- `diagnostic_context`
- `fallback_assessment`
- `recommended_action`
- `artifact_status`
- `redactions_applied`
- `debug_bundle.available`

### Что оператор смотрит первым

- `run.verdict`
- `run.stage`
- `failure.code`
- `recommended_action`

### Как authoritative path теперь отличает финальный ответ от промежуточного

Authoritative `Telegram Web` probe больше не принимает первый попавшийся входящий bubble за окончательный успех.

Теперь он:

1. ждёт первый attributable reply после sent message;
2. затем выдерживает `reply settle window`;
3. и только после этого оценивает последний стабильный ответ.

Практический смысл:

- ранняя промежуточная реплика вроде `Проверяю снова...` больше не считается достаточным pass;
- если следом приходит `Timed out: Agent run timed out after <N>s`, authoritative verdict должен стать `failed`, а не `passed`.

## Failure Codes

Authoritative Telegram Web path различает минимум:

- `missing_session_state`
- `ui_drift`
- `chat_open_failure`
- `stale_chat_noise`
- `send_failure`
- `bot_no_response`
- `semantic_activity_leak`
- `semantic_pre_send_activity_leak`
- `semantic_host_path_leak`
- `semantic_codex_update_false_negative`
- `semantic_codex_update_remote_contract_violation`
- `semantic_codex_update_state_memory_false_negative`

Для `codex-update`-запросов это значит ещё одно правило: если remote user-facing reply обещает operator-only runtime path вроде `make codex-update` или server-side обновление локальной машины пользователя, authoritative verdict должен быть `failed`, даже если helper payload выглядит зелёным.

Отдельно для вопросов про сохранённое состояние `codex-update`: если reply делает выводы вида `в памяти не найдено`, `в базе не зафиксировано` или аналогично подменяет runtime state общим memory-search path, authoritative verdict тоже должен быть `failed`.

## Restricted Debug Bundle

Restricted debug bundle хранит raw helper evidence:

- `authoritative_raw`
- `authoritative_stderr_tail`
- `fallback_raw`
- `fallback_stderr_tail`

Этот bundle не считается routine-share artifact и загружается только при явном `upload_restricted_debug=true`.

## MTProto Secondary Lane

`MTProto` больше не заменяет primary verdict.

Он используется только если:

1. primary Telegram Web verdict уже известен;
2. оператор явно запросил secondary diagnostics;
3. есть `TELEGRAM_TEST_API_ID`, `TELEGRAM_TEST_API_HASH`, `TELEGRAM_TEST_SESSION`.

Если prerequisites отсутствуют, основной artifact фиксирует это в `fallback_assessment` как `outcome=unavailable`.

### Важная оговорка про comparability

`TELEGRAM_TEST_SESSION` в secondary lane может принадлежать отдельному test user, а не тому же allowlisted пользователю, под которым авторизован authoritative `Telegram Web`.

Если этот test user не входит в `dm_policy = "allowlist"` для `@moltinger_bot`, secondary `MTProto` может получить ответ вида:

`To use this bot, please enter the verification code...`

Это не означает регрессию `codex-update` или failure authoritative path. Теперь review-safe artifact фиксирует такой случай как:

- `fallback_assessment.observed_verification_gate = true`
- `fallback_assessment.comparable_to_authoritative = false`

Практический смысл:

- authoritative `Telegram Web` остаётся источником истины для pass/fail;
- `MTProto` в таком случае показывает только то, что отдельный test user упёрся в sender verification gate;
- для полностью сопоставимой secondary проверки нужно либо использовать ту же allowlisted учётку, либо добавить MTProto test user в allowlist.

## Codex Advisory Acceptance

Для нового Moltis-native advisory flow не нужно руками интерпретировать ответы в Telegram-чате.
Отдельный hermetic helper проверяет путь `alert -> accept -> recommendations` без зависимости от live ingress:

```bash
./scripts/codex-advisory-e2e.sh \
  --output .tmp/current/codex-advisory-e2e-report.json
```

Или коротко:

```bash
make codex-advisory-e2e
```

Что именно он подтверждает:

1. upstream watcher эмитит нормализованный advisory event;
2. Moltis-native intake поднимает advisory session и рендерит alert;
3. authoritative router принимает callback или recovery action;
4. follow-up с рекомендациями отправляется сразу после `accept`;
5. degraded one-way path остаётся честным и фиксируется в audit trail.

Для live post-deploy проверки transport/runtime по-прежнему остается каноническим этот remote UAT workflow, а для advisory UX используется отдельный helper выше.
