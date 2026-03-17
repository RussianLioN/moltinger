# Plan: ASC AI Fabrique Demo Backend

## Context

Строим backend для прототипа "ASC AI Fabrique Demo" — демонстрация пользовательского пути фабрики цифровых сотрудников для стейкхолдеров. Frontend полностью готов (2500 строк app.js с mock-режимом). Backend должен заменить mock реальной LLM-логикой.

**Ключевые решения:**
- **OpenAI-compatible API** вместо Anthropic SDK (пользователь предоставит endpoint + ключ)
- **Direct API + Theatre Layer** — прямые LLM-вызовы + статусные сообщения эмулирующие фабрику
- **4 артефакта**: 3 от архитектора (project_doc, agent_spec, presentation — шаблонные) + 1 реальный результат (one_page_summary — 4 секции через LLM)
- **Двухэтапная логика**: в нашем демо все "ручки" есть → фабрика выдаёт и артефакты архитектора, и результат работы

## Files to Create

```
asc-demo/
├── package.json                     # NEW
├── .env.example                     # NEW
├── server.js                        # NEW
├── src/
│   ├── llm.js                       # NEW — OpenAI-compatible client
│   ├── sessions.js                  # NEW — In-memory session store
│   ├── response-builder.js          # NEW — Builds responses matching mockAdapterTurn()
│   ├── router.js                    # NEW — Routes ui_action → handler
│   ├── discovery.js                 # NEW — LLM discovery flow (7 topics)
│   ├── brief.js                     # NEW — Brief generation + revision
│   ├── summary-generator.js         # NEW — 4 parallel LLM calls for summary
│   ├── prompts/
│   │   ├── architect-system.md      # NEW — System prompt агента-архитектора
│   │   ├── client-info.md           # NEW — Промпт секции 1 (из generation-prompts.md строки 1-63)
│   │   ├── deal-info.md             # NEW — Промпт секции 2 (строки 64-173)
│   │   ├── pricing-info.md          # NEW — Промпт секции 3 (строки 174-352)
│   │   └── cooperation-info.md      # NEW — Промпт секции 4 (строки 354-488)
│   └── demo-data/
│       └── boku-do-manzh.json       # NEW — CSV → JSON конвертация
├── public/                          # EXISTING — не трогать (кроме download_url)
└── artifacts/                       # EXISTING — runtime generated
```

## Files to Modify

- `asc-demo/CLAUDE.md` — обновить стек (OpenAI-compatible вместо Anthropic SDK), .env переменные

---

## Task 1: Project Init (package.json, .env, demo data JSON)

**Files**: `package.json`, `.env.example`, `src/demo-data/boku-do-manzh.json`

**package.json**:
- `type: "module"`, ESM
- deps: `express`, `openai`, `dotenv`, `cors`, `uuid`
- scripts: `"dev": "node --watch server.js"`, `"start": "node server.js"`

**.env.example**:
```
OPENAI_API_KEY=sk-your-key
OPENAI_BASE_URL=https://your-endpoint/v1
MODEL_NAME=your-model-name
PORT=3000
```

**boku-do-manzh.json** — конвертация `demo-client-data.csv` в JSON с 5 секциями:
- `client` (строки CSV 2-26), `deal` (27-38), `pricing` (39-62), `potential` (63-87), `cooperation` (88-110)

**Done when**: `npm install` проходит; JSON содержит все поля из CSV.

---

## Task 2: LLM Client (src/llm.js)

**Files**: `src/llm.js`

OpenAI-compatible wrapper:
```js
import OpenAI from "openai";
const client = new OpenAI({ apiKey: env.OPENAI_API_KEY, baseURL: env.OPENAI_BASE_URL });

export async function chatCompletion(messages, opts) → string
export async function chatCompletionJSON(messages, opts) → object  // парсит JSON из ответа
```

- `chatCompletionJSON` — strip markdown code fences, `JSON.parse()`
- Оба метода бросают exception при ошибке — обработка в router

**Done when**: импорт не падает; при валидных credentials возвращает ответ.

---

## Task 3: Sessions (src/sessions.js)

**Files**: `src/sessions.js`

In-memory `Map<sessionId, Session>`:
```js
Session = {
  sessionId, projectKey, stage,  // "gate_pending"|"discovery"|"awaiting_confirmation"|"downloads_ready"
  accessGranted,
  conversationHistory: [],       // [{role, content}] для OpenAI API
  coveredTopics: Set,
  uploadedFiles: [],
  briefText: "", briefVersion: 0,
  artifacts: [],                 // [{artifact_kind, download_name, content, download_status}]
  summaryPromise: null,          // Promise для deferred generation
  lastResponse: null,            // кэш для GET /api/session
  createdAt, updatedAt
}
```

API: `getOrCreate(id)`, `get(id)`, `update(id, patch)`

**Done when**: getOrCreate создаёт сессию; повторный вызов возвращает ту же.

---

## Task 4: Response Builder (src/response-builder.js)

**Files**: `src/response-builder.js`

Критический модуль — строит ответ в ТОЧНОМ формате `mockAdapterTurn()` (app.js:1922-2056).

4 builder-функции:
- `buildGatePendingResponse(session)` → reply_cards: [status_update]
- `buildDiscoveryResponse(session, {nextQuestion, nextTopic, whyAskingNow, missing, lowSignal, theatreMsg})` → reply_cards: [status_update, discovery_question, ?clarification_prompt]
- `buildAwaitingConfirmationResponse(session, {briefText, theatreMsg})` → reply_cards: [status_update, brief_summary_section, confirmation_prompt]; side_panel_mode: "brief_review"
- `buildDownloadsReadyResponse(session, {artifacts, theatreMsg})` → reply_cards: [status_update, download_prompt]; download_artifacts с download_url; side_panel_mode: "downloads"

Каждый ответ содержит ВСЕ поля: status, next_action, next_topic, next_question, access_gate, web_demo_session, browser_project_pointer, status_snapshot, reply_cards, download_artifacts, uploaded_files, discovery_runtime_state, ui_projection.

**Ref**: `public/app.js` строки 2001-2055 — эталон формата.

**Done when**: каждый builder возвращает объект со всеми полями mock-ответа.

---

## Task 5: Discovery (src/discovery.js + src/prompts/architect-system.md)

**Files**: `src/discovery.js`, `src/prompts/architect-system.md`

7 discovery-топиков (точно из app.js:66-109): problem, target_users, current_workflow, input_examples, expected_outputs, branching_rules, success_metrics.

**architect-system.md** — system prompt агента Moltis: ведёт discovery на русском, задаёт по одному вопросу, возвращает JSON с covered_topics + next_question.

`processDiscoveryTurn(session, userText, uploadedFiles)`:
1. Добавить user message в conversationHistory
2. Файлы → автопокрытие input_examples
3. LLM с chatCompletionJSON → { covered_topics, next_topic, next_question, why_asking_now, low_signal }
4. Обновить session.coveredTopics
5. Если все покрыты → `{ complete: true }`

**Fallback**: при ошибке LLM — signal-based matching (как mock buildMockCoverage) + дефолтный вопрос из топика.

**Done when**: LLM задаёт вопросы по непокрытым темам; после 5+ тем complete=true; fallback работает.

---

## Task 6: Brief (src/brief.js)

**Files**: `src/brief.js`

`generateBrief(session)`:
- LLM из conversationHistory → structured brief (markdown с 7 секциями по темам)
- Возвращается как brief_summary_section card в side panel

`reviseBrief(session, correctionText)`:
- LLM с текущим brief + правки → обновлённый brief
- briefVersion++

**Theatre layer**: "Discovery завершён. Агент-архитектор формирует brief..."

**Done when**: brief генерируется из диалога; side panel показывает brief; правки работают.

---

## Task 7: Summary Generator (src/summary-generator.js + 4 prompt files)

**Files**: `src/summary-generator.js`, `src/prompts/client-info.md`, `deal-info.md`, `pricing-info.md`, `cooperation-info.md`

**Промпт-файлы** — скопировать дословно из `generation-prompts.md`:
- client-info.md ← строки 1-63
- deal-info.md ← строки 64-173
- pricing-info.md ← строки 174-352
- cooperation-info.md ← строки 354-488

`generateSummary(session)`:
- 4 параллельных LLM-вызова через `Promise.all`
- Каждый: system=промпт из файла, user=JSON данных секции из boku-do-manzh.json
- Результат — one_page_summary.md (4 секции в одном файле)

**Артефакты на выходе** (4 шт.):
1. `{ artifact_kind: "one_page_summary", download_name: "one-page-summary.md", download_status: "ready" }` — реальный, LLM-generated
2. `{ artifact_kind: "project_doc", download_name: "project-doc.md", download_status: "ready" }` — шаблонный, собран из brief
3. `{ artifact_kind: "agent_spec", download_name: "agent-spec.md", download_status: "ready" }` — шаблонный
4. `{ artifact_kind: "presentation", download_name: "presentation.md", download_status: "ready" }` — шаблонный

Шаблонные артефакты генерируются из brief + discovery history без отдельного LLM-вызова (простая подстановка в markdown-шаблон).

**Done when**: 4 секции генерируются параллельно; 4 артефакта с download_url; скачивание работает.

---

## Task 8: Router (src/router.js)

**Files**: `src/router.js`

Центральный маршрутизатор `handleTurn(payload)`:

```
1. Парсинг: ui_action, sessionId, userText, uploadedFiles, accessToken
2. Access gate: token !== "demo-access-token" → buildGatePendingResponse
3. Route by action:
   - submit_turn / start_project → handleDiscoveryTurn
   - confirm_brief → handleConfirmBrief
   - request_brief_correction → handleBriefCorrection
   - reopen_brief → handleReopenBrief
   - request_status → handleRequestStatus
   - default → handleDiscoveryTurn
```

**Deferred generation** (используя auto-followup frontend):
- `confirm_brief` → запускает `generateSummary()` как Promise в session, возвращает ответ БЕЗ download_artifacts
- Frontend через 120ms шлёт `request_status` (app.js:2098-2111)
- `request_status` → await summaryPromise → возвращает с artifacts

**Переходы**:
- gate_pending → (valid token) → discovery
- discovery → (all topics covered) → awaiting_confirmation (auto-generate brief)
- awaiting_confirmation → (confirm_brief) → downloads_ready
- awaiting_confirmation → (request_brief_correction) → awaiting_confirmation (revised brief)

Каждый ответ кэшируется в session.lastResponse для GET /api/session.

**Done when**: полный flow gate→discovery→brief→confirm→downloads работает.

---

## Task 9: Express Server (server.js)

**Files**: `server.js`

```
- GET / → static from public/
- POST /api/turn → handleTurn(req.body) → JSON response
- GET /api/session?session_id=... → session.lastResponse
- GET /api/download/:sessionId/:artifactKind → artifact content as file
- Global error handler → fallback JSON in mockAdapterTurn format
```

**Download endpoint**: Content-Disposition: attachment; Content-Type: text/markdown.
Response builder включает `download_url: "/api/download/{sessionId}/{artifactKind}"` в каждый артефакт.

Frontend (app.js:1137): использует download_url если есть, иначе createMockDownload.

**Done when**: `npm run dev` стартует; UI загружается; POST/GET работают; скачивание артефактов работает.

---

## Task 10: Theatre Layer + Error Handling + Polish

**Files**: модификации router.js, response-builder.js, discovery.js

**Theatre layer** — статусные сообщения в reply_cards[0] (status_update):

| Переход | Сообщение |
|---------|-----------|
| Gate → Discovery | "Агент-архитектор Moltis начинает structured discovery..." |
| Discovery turn N | "Закрыто тем: X/7. {whyAskingNow}" |
| Discovery → Brief | "Discovery завершён. Формирование brief..." |
| Confirm → Production | "Brief подтверждён. Передача в производственный контур фабрики..." |
| Production → Ready | "Производство завершено. Артефакты готовы." |

**Error handling** (3 уровня):
1. LLM error в discovery → fallback на signal-based matching + дефолтный вопрос из топика
2. LLM error в brief → stub brief из ответов пользователя
3. LLM error в summary → шаблонный текст с подстановкой данных из JSON
4. Полный отказ → server.js catch → валидный JSON-ответ (frontend получает 200 + корректный формат)

**CLAUDE.md update**: заменить Anthropic SDK → OpenAI-compatible, обновить .env переменные.

**Done when**: при невалидном API key сервер не падает; theatre messages видны в UI; полный happy-path e2e.

---

## Dependency Graph

```
Task 1 (init) ──┬──> Task 2 (llm.js) ──┬──> Task 5 (discovery)  ──┐
                │                       ├──> Task 6 (brief)        ├──> Task 8 (router) ──> Task 9 (server) ──> Task 10 (polish)
                │                       └──> Task 7 (summary-gen)  ┘
                ├──> Task 3 (sessions) ─────────────────────────────┘
                └──> Task 4 (response-builder) ─────────────────────┘
```

Параллельно: [2, 3, 4] после 1. Затем [5, 6, 7] после 2. Затем [8] после 3+4+5+6+7. Затем [9, 10] последовательно.

## Verification

1. `npm install` — без ошибок
2. `npm run dev` — сервер на порту 3000
3. Открыть http://localhost:3000 — UI загружается
4. Ввести token "demo-access-token" — gate открывается
5. Discovery: агент задаёт осмысленные вопросы на русском, покрытие растёт
6. После 5+ тем — автопереход к brief, side panel открывается с brief_review
7. Подтвердить brief → theatre message "Передача в производственный контур..."
8. request_status → 4 артефакта готовы, side panel переключается на downloads
9. Скачать one-page-summary.md — содержит 4 секции с реальными данными "Боку до манж"
10. При невалидном API key: fallback ответы, сервер не падает
