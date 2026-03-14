# Agent Factory Web Demo Runbook

## Purpose

Этот runbook описывает текущий foundational slice `024-web-factory-demo-adapter`.

Текущая цель слоя:

1. открыть controlled browser demo surface для фабричного агента-бизнес-аналитика на `Moltis`
2. нормализовать browser turn в discovery runtime из `022`
3. хранить adapter-level session/access/history отдельно от discovery-core state
4. отрисовывать безопасные user-facing reply cards вместо raw runtime JSON

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

На этом этапе adapter ещё не завершает:

- full brief correction/confirmation UX
- downstream `handoff -> intake -> artifacts`
- browser downloads
- remote smoke/deploy rollout

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
- `POST /api/turn`

## Storage Layout

Adapter-local state lives under:

```text
data/agent-factory/web-demo/
├── access/
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

## Safety Rules

- browser UI must not render repo paths, stack traces or secrets
- discovery logic stays in `022`; adapter only routes and projects
- access must fail closed
- demo examples must stay synthetic or sanitized
- adapter state must stay separate from downstream concept-pack state
