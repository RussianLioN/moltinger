# Agent Factory Web Demo Runbook

## Purpose

Этот runbook описывает текущий рабочий slice `024-web-factory-demo-adapter`.

Текущая цель слоя:

1. открыть controlled browser demo surface для фабричного агента-бизнес-аналитика на `Moltis`
2. нормализовать browser turn в discovery runtime из `022`
3. хранить adapter-level session/access/history отдельно от discovery-core state
4. хранить отдельные pointer/resume snapshots для устойчивого browser resume
5. отрисовывать безопасные user-facing reply cards вместо raw runtime JSON
6. автоматически запускать downstream `handoff -> intake -> concept pack`
7. публиковать browser-safe downloads для `project doc`, `agent spec`, и `presentation`

## Current Scope

На текущем этапе web adapter уже умеет:

- принимать browser envelope через `handle-turn`
- fail-closed блокировать проект без valid access grant или восстановленной browser session
- создавать и восстанавливать `WebDemoSession`
- вести `BrowserProjectPointer`
- маршрутизировать `start_project`, `submit_turn` и `request_status`
- сохранять session/access/history snapshots под `data/agent-factory/web-demo/`
- раздавать `index.html`, `app.css`, `app.js` и `/health` через lightweight Python server
- показывать отдельный `access gate`, а после успешного входа переводить пользователя в отдельное рабочее пространство
- держать `composer` главным фокусом первого рабочего экрана и прятать служебный контекст в secondary disclosure
- поддерживать левый sidebar со списком проектов и быстрым возвратом к ним
- автоматически давать проекту рабочее имя после первого содержательного user turn и позволять переименовывать проект через меню `⋯`
- показывать первый live discovery follow-up вопрос в том же browser shell после сырой идеи пользователя
- возвращать browser-safe `status_update` и `discovery_question` cards без leakage внутренних runtime полей
- подсказывать shell правильный следующий режим через `ui_projection.preferred_ui_action`
- рендерить reviewable brief по секциям, принимать correction/confirm/reopen actions и сохранять versioned confirmation history
- принимать файлы прямо из browser composer и безопасно извлекать excerpt для `txt/csv/json/md/docx`
- после `confirm_brief` автоматически запускать downstream handoff chain через `scripts/agent-factory-intake.py` и `scripts/agent-factory-artifacts.py`
- публиковать browser-safe `download_artifacts` и HTTP download endpoint `/api/download`
- хранить отдельные `pointers/` и `resume/` snapshots, чтобы refresh/resume не зависели только от localStorage
- перечитывать `GET /api/session` после refresh и показывать browser-safe `resume_context` вместо потери активного проекта
- возвращать reopened brief в новый reviewable loop без потери `confirmation_history` и `handoff_history`

На этом этапе adapter ещё не завершает:

- remote smoke/deploy rollout

Оставшийся follow-up scope уже вне текущего browser slice:

- более сложные multi-user/session handoff сценарии
- отдельные интерфейсные адаптеры поверх этого же runtime (`023` для Telegram и будущие UI)

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
├── pointers/
├── resume/
├── sessions/
└── uploads/
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

### pointers/

Stores one active `BrowserProjectPointer` snapshot per `web_demo_session_id`, so the adapter can restore the active project and linked brief version independently of the full session payload.

### resume/

Stores one browser-safe `resume_context` snapshot per `web_demo_session_id`, including the current status label, latest brief versions, pending question, and history counters used by the shell after refresh.

### downloads/

Stores per-session browser delivery state:

- `concept-pack.json`
- `downloads/project-doc.md`
- `downloads/agent-spec.md`
- `downloads/presentation.md`
- `delivery-index.json` with private `download_ref -> token` resolution

### uploads/

Stores per-session raw attachment bytes under a separate adapter-owned root.

Browser responses never echo raw payloads back. The adapter returns only:

- file name
- content type
- safe excerpt when auto-extraction is available
- truncation flag
- upload timestamp

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

## Browser Composer Attachments

В web shell пользователь может прикладывать файлы прямо в chat composer.

Current behavior:

- до 4 файлов на один turn
- безопасный лимит чтения: `512 KB` на файл
- auto-excerpt для `txt`, `md`, `csv`, `tsv`, `json`, `yaml`, `xml`, `html`, `log`, `docx`
- unsupported formats пока идут как metadata-only attachment

Current UX contract:

- текст печатается локально сразу и не зависит от round-trip на сервер
- отправка в фабрику происходит только по кнопке `Отправить`
- прикреплённые файлы видны в composer до отправки
- после ответа сервера attachment count и session attachment list отражаются в status strip

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

### Current browser composition

Browser shell intentionally split into 3 user-facing states:

1. `Access gate`
   - сначала пользователь видит только экран доступа
   - token не висит рядом с рабочим composer и не конкурирует с основным сценарием
2. `Empty home`
   - после успешного входа открывается чистый рабочий экран
   - слева виден список проектов и кнопка `Новый проект`
   - в центре главный фокус у `composer`, а не у status/dashboard элементов
3. `Project workspace`
   - после первого реального turn раскрывается thread проекта
   - текущий вопрос агента поднимается в `composer`
   - `Контекст проекта` остаётся в `<details>` и не конкурирует с диалогом

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

## Controlled Subdomain Demo Access (US4)

### Deploy target

US4 публикует browser demo как отдельный same-host target:

```bash
./scripts/deploy.sh asc-demo deploy
./scripts/deploy.sh --json asc-demo status
```

`deploy.sh` для `asc-demo` должен:

- использовать [docker-compose.asc.yml](/Users/rl/coding/moltinger-019-asc-fabrique-prototype/docker-compose.asc.yml)
- создать bind-backed runtime roots для `data/agent-factory/web-demo`, `data/agent-factory/discovery` и `data/agent-factory/concepts`
- проверить `http://localhost:${ASC_DEMO_INTERNAL_PORT:-18791}/health`
- проверить `http://localhost:${ASC_DEMO_INTERNAL_PORT:-18791}/metrics`

### Access gate configuration

Для controlled demo используются env anchors:

- `ASC_DEMO_DOMAIN`
- `ASC_DEMO_PUBLIC_BASE_URL`
- `ASC_DEMO_ACCESS_MODE`
- `ASC_DEMO_SHARED_TOKEN_HASH`
- `ASC_DEMO_OPERATOR_LABEL`

Recommended mode for the published demo:

- `ASC_DEMO_ACCESS_MODE=shared_token_hash`
- `ASC_DEMO_SHARED_TOKEN_HASH=<sha256 от выдаваемого demo token>`

Current behavior:

- если `ASC_DEMO_ACCESS_MODE=shared_token_hash` и hash настроен, adapter пропускает только matching token
- если hash не настроен, `/api/health` показывает `publication_status=degraded`
- локальные fixture-прогоны могут жить в `fixture_trust`, не ломая hermetic validation

### Operator-safe health publication

Published demo surface now exposes:

- `GET /health`
- `GET /api/health`
- `GET /metrics`

`/api/health` отдаёт operator-safe projection:

- `service`
- `public_base_url`
- `access_gate_mode`
- `access_gate_configured`
- `operator_status.publication_status`
- `operator_status.needs_operator_attention`
- session/access/history/download counters

`/metrics` отдаёт минимальные gauges:

- `agent_factory_web_demo_active_sessions`
- `agent_factory_web_demo_access_grants`
- `agent_factory_web_demo_saved_pointers`
- `agent_factory_web_demo_resume_contexts`
- `agent_factory_web_demo_download_sessions`
- `agent_factory_web_demo_publication_ready`
- `agent_factory_web_demo_access_gate_configured`

### Local validation examples

Component access + health projection:

```bash
./tests/run.sh --lane component --filter component_agent_factory_web_access --json
```

Remote smoke for the published demo:

```bash
TEST_LIVE=1 LIVE_ASC_DEMO_URL=https://asc.ainetic.tech \
./tests/run.sh --lane web_demo_live --json --live
```

Expected smoke result:

- landing page is reachable
- `/health` returns `200`
- `/api/health` reports `access_gate_mode=shared_token_hash`
- `/api/health` reports `publication_status=ready`
- `/metrics` returns `200`

## Resume And Reopen In Browser (US5)

### Browser resume behavior

После US5 browser shell ведёт себя как рабочий пользовательский канал, а не как one-shot demo:

1. после первого live turn adapter сохраняет полный session snapshot, active pointer и отдельный `resume_context`
2. при `GET /api/session` shell перечитывает текущий server-side snapshot и восстанавливает активный проект без JSON/CLI шага
3. после refresh shell не сбрасывается в `Новый проект`, а возвращается в правильный action mode (`submit_turn`, `confirm_brief`, `download_artifact`)
4. reopened brief публикует новую version chain, но сохраняет `confirmation_history` и `handoff_history`

### Browser-safe resume contract

`GET /api/session` теперь должен возвращать не только последний session snapshot, но и browser-safe `resume_context`:

- `resume_available`
- `resumed_from_saved_session`
- `summary_text`
- `current_status`
- `current_status_label`
- `current_topic`
- `pending_question`
- `latest_brief_version`
- `latest_confirmed_brief_version`
- `confirmation_history_count`
- `handoff_history_count`
- `download_artifact_count`

Shell использует эти поля, чтобы:

- показать человеку короткое сообщение о восстановлении сессии
- не терять активный проект после refresh
- корректно объяснять, что brief был переоткрыт, а не просто “ждёт подтверждения”

### Local validation examples

Server-side resume and reopen:

```bash
./tests/run.sh --lane integration_local --filter integration_local_agent_factory_web_resume --json
```

Browser refresh continuity:

```bash
./tests/run.sh --lane e2e_browser --filter agent_factory_web_demo --json
```

Expected result:

- server-side resume restores the saved active project without a fresh access token
- `pointers/` and `resume/` snapshots exist under `data/agent-factory/web-demo/`
- page reload keeps the same browser session and lets the user continue discovery
- reopening a confirmed/download-ready brief returns the UI to a new reviewable version while preserving prior confirmation and handoff provenance

## Safety Rules

- browser UI must not render repo paths, stack traces or secrets
- discovery logic stays in `022`; adapter only routes and projects
- access must fail closed
- demo examples must stay synthetic or sanitized
- adapter state must stay separate from downstream concept-pack state
