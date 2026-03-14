# Agent Factory Web Demo Runbook

## Purpose

Этот runbook описывает текущий рабочий slice `024-web-factory-demo-adapter`.

Текущая цель слоя:

1. открыть controlled browser demo surface для фабричного агента-бизнес-аналитика на `Moltis`
2. нормализовать browser turn в discovery runtime из `022`
3. хранить adapter-level session/access/history отдельно от discovery-core state
4. отрисовывать безопасные user-facing reply cards вместо raw runtime JSON
5. автоматически запускать downstream `handoff -> intake -> concept pack`
6. публиковать browser-safe downloads для `project doc`, `agent spec`, и `presentation`

## Current Scope

На текущем этапе web adapter уже умеет:

- принимать browser envelope через `handle-turn`
- fail-closed блокировать проект без valid access grant или восстановленной browser session
- создавать и восстанавливать `WebDemoSession`
- вести `BrowserProjectPointer`
- маршрутизировать `start_project`, `submit_turn` и `request_status`
- сохранять session/access/history snapshots под `data/agent-factory/web-demo/`
- раздавать `index.html`, `app.css`, `app.js` и `/health` через lightweight Python server
- показывать первый live discovery follow-up вопрос в том же browser shell после сырой идеи пользователя
- возвращать browser-safe `status_update` и `discovery_question` cards без leakage внутренних runtime полей
- подсказывать shell правильный следующий режим через `ui_projection.preferred_ui_action`
- рендерить reviewable brief по секциям, принимать correction/confirm/reopen actions и сохранять versioned confirmation history
- после `confirm_brief` автоматически запускать downstream handoff chain через `scripts/agent-factory-intake.py` и `scripts/agent-factory-artifacts.py`
- публиковать browser-safe `download_artifacts` и HTTP download endpoint `/api/download`

На этом этапе adapter ещё не завершает:

- remote smoke/deploy rollout
- long-lived browser resume/reopen polish beyond the current saved-session path

Эти части закрываются в следующих user stories `024`.

## Runtime Commands

### 1. Local one-turn adapter execution

```bash
python3 scripts/agent-factory-web-adapter.py handle-turn \
  --source tests/fixtures/agent-factory/web-demo/session-new.json \
  --state-root /tmp/agent-factory-web-demo \
  --output /tmp/agent-factory-web-demo/out.json
```

Expected result:

- создается или восстанавливается `web_demo_session`
- browser turn уходит в `scripts/agent-factory-discovery.py`
- возвращаются `status_snapshot`, `reply_cards` и sanitized `discovery_runtime_state`

### 2. Local demo server

```bash
python3 scripts/agent-factory-web-adapter.py serve \
  --host 127.0.0.1 \
  --port 18791 \
  --state-root /tmp/agent-factory-web-demo \
  --assets-root web/agent-factory-demo
```

Available routes:

- `GET /health`
- `GET /`
- `GET /app.css`
- `GET /app.js`
- `GET /api/session?session_id=<web_demo_session_id>`
- `GET /api/download?session_id=<web_demo_session_id>&token=<download_token>`
- `POST /api/turn`

## Storage Layout

Adapter-local state lives under:

```text
data/agent-factory/web-demo/
├── access/
├── downloads/
├── history/
└── sessions/
```

### access/

Stores one sanitized access-gate snapshot per access grant.

### sessions/

Stores one active adapter snapshot per `web_demo_session_id`, including:

- `web_demo_session`
- `browser_project_pointer`
- `web_conversation_envelope`
- `status_snapshot`
- `reply_cards`
- `discovery_runtime_state`

### history/

Stores per-request adapter snapshots for lightweight audit and resume traceability.

### downloads/

Stores per-session browser delivery state:

- `concept-pack.json`
- `downloads/project-doc.md`
- `downloads/agent-spec.md`
- `downloads/presentation.md`
- `delivery-index.json` with private `download_ref -> token` resolution

## Browser Envelope Contract

Minimal request shape:

```json
{
  "demo_access_grant": {
    "status": "active",
    "grant_value_hash": "..."
  },
  "web_demo_session": {
    "web_demo_session_id": "web-demo-session-example",
    "session_cookie_id": "browser-cookie-example"
  },
  "browser_project_pointer": {
    "project_key": "claims-routing-discovery-demo"
  },
  "web_conversation_envelope": {
    "request_id": "web-request-001",
    "ui_action": "start_project",
    "user_text": "..."
  }
}
```

Supported foundational actions:

- `start_project`
- `submit_turn`
- `request_status`
- `request_brief_review`
- `request_brief_correction`
- `confirm_brief`
- `reopen_brief`
- `download_artifact`

## Live Discovery UX (US1)

### Browser entry flow

1. Оператор открывает web demo server или deployed subdomain.
2. Пользователь вводит demo access token.
3. Пользователь выбирает `Новый проект` и отправляет сырую идею свободным текстом.
4. Adapter открывает `WebDemoSession`, запускает discovery runtime из `022`, и возвращает:
   - человекочитаемый `status_update`
   - `discovery_question` с первым business-analyst follow-up вопросом
   - `ui_projection.preferred_ui_action=submit_turn`, чтобы shell сразу переводил composer в режим ответа
5. Следующий ответ пользователя отправляется как обычный `submit_turn` без JSON/CLI-прослойки.

### Browser-safe response contract

Для live discovery UI должен использовать только browser-facing projection:

- `status_snapshot.user_visible_status_label`
- `status_snapshot.next_recommended_action_label`
- `reply_cards[].kind`
- `reply_cards[].title`
- `reply_cards[].body`
- `ui_projection.preferred_ui_action`
- `ui_projection.current_question`
- `ui_projection.current_topic`

UI не должен показывать пользователю:

- `discovery_runtime_state`
- repo paths
- внутренние status codes вроде `ask_next_question`
- debug payloads и stack traces

### Local validation examples

Первый turn:

```bash
python3 scripts/agent-factory-web-adapter.py handle-turn \
  --source tests/fixtures/agent-factory/web-demo/session-new.json \
  --state-root /tmp/agent-factory-web-demo \
  --output /tmp/agent-factory-web-demo/first-turn.json
```

Follow-up answer:

```bash
python3 scripts/agent-factory-web-adapter.py handle-turn \
  --source tests/fixtures/agent-factory/web-demo/session-discovery-answer.json \
  --state-root /tmp/agent-factory-web-demo \
  --output /tmp/agent-factory-web-demo/second-turn.json
```

## Brief Review And Confirmation (US2)

### Browser review behavior

Когда discovery runtime уже перешёл в `awaiting_confirmation`, browser adapter теперь:

- рендерит exact brief version отдельной карточкой
- дробит summary на читаемые sections вместо одного длинного блока
- показывает browser-safe confirmation prompt с явным `confirm_brief`, `request_brief_correction` и `reopen_brief`
- оставляет traceable `linked_brief_version` в browser pointer и `status_snapshot.brief_version`

Текущий review split:

- `Версия brief <version>`
- `Проблема и желаемый результат`
- `Пользователи и процесс`
- `User story и границы`
- `Примеры входов и выходов`
- `Правила, исключения и риски`
- `Ограничения и метрики`

### Browser actions

- `request_brief_review` можно отправить без free-form текста; shell сам перечитывает текущую reviewable версию
- `request_brief_correction` принимает обычный пользовательский текст и, при необходимости, `brief_section_updates`
- `confirm_brief` считается explicit action даже без отдельного текста подтверждения; adapter сам подставляет безопасную default confirmation phrase
- `reopen_brief` создаёт новую version chain и возвращает UI обратно в confirmation loop

### Local validation examples

Reviewable brief:

```bash
python3 scripts/agent-factory-web-adapter.py handle-turn \
  --source tests/fixtures/agent-factory/web-demo/session-awaiting-confirmation.json \
  --state-root /tmp/agent-factory-web-demo \
  --output /tmp/agent-factory-web-demo/brief-review.json
```

Expected result:

- `status=awaiting_confirmation`
- readable `brief_summary_section` cards
- `confirmation_prompt` with exact brief version

Conversational correction and confirmation:

```bash
./tests/run.sh --lane integration_local --filter integration_local_agent_factory_web_confirmation --json
```

Expected result:

- browser correction publishes a new brief version
- explicit confirmation fixes that exact version as confirmed
- reopen returns the UI to a new reviewable version without losing confirmation history

## Automatic Handoff And Browser Downloads (US3)

### Browser delivery behavior

После explicit browser confirmation shell не требует ручного JSON шага:

1. `confirm_brief` фиксирует exact reviewed brief version.
2. Shell делает безопасный follow-up `request_status`.
3. Adapter при необходимости перевыпускает `factory_handoff_record` из confirmed discovery state.
4. Adapter запускает downstream chain:
   - `scripts/agent-factory-intake.py`
   - `scripts/agent-factory-artifacts.py generate`
5. Browser response переходит в `status=download_ready`.
6. Пользователь получает 3 артефакта через `download_artifacts[]` с browser-safe `/api/download` URL.

### Delivery contract

Browser response должен содержать только sanitized delivery metadata:

- `artifact_kind`
- `download_name`
- `download_status`
- `project_key`
- `brief_version`
- `download_token`
- `download_url`

Browser response не должен содержать:

- `download_ref`
- локальные filesystem paths
- `working_root`
- `download_root`

### Local validation examples

Ready download fixture:

```bash
python3 scripts/agent-factory-web-adapter.py handle-turn \
  --source tests/fixtures/agent-factory/web-demo/session-download-ready.json \
  --state-root /tmp/agent-factory-web-demo \
  --output /tmp/agent-factory-web-demo/downloads.json
```

Expected result:

- `status=download_ready`
- `next_action=download_artifact`
- 3 browser downloads are exposed
- `status_snapshot.download_readiness=ready`

Full browser handoff chain:

```bash
./tests/run.sh --lane integration_local --filter integration_local_agent_factory_web_handoff --json
```

Expected result:

- confirmed browser brief triggers downstream concept-pack generation
- manifest keeps discovery provenance and `delivery_channel=web`
- `/api/download` serves the generated `project-doc.md`, `agent-spec.md`, and `presentation.md`

### Failure messaging

Если downstream handoff или artifact generation ломается, adapter:

- не публикует partially-ready downloads
- оставляет user-facing state в safe status response
- публикует `error_message` reply card вместо raw exception payload
- сохраняет adapter/session snapshot для operator follow-up

## Safety Rules

- browser UI must not render repo paths, stack traces or secrets
- discovery logic stays in `022`; adapter only routes and projects
- access must fail closed
- demo examples must stay synthetic or sanitized
- adapter state must stay separate from downstream concept-pack state
