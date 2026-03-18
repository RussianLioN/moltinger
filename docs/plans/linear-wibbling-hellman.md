# Plan: Fix Workflow Hang After File Upload (ASC Demo)

## Context

ASC Demo — прототип AI Agent Factory, дедлайн демо через несколько часов. После загрузки файла с примерами входных данных workflow зависает — бесконечный спиннер, следующий вопрос не приходит.

## Root Cause

**Отсутствие timeout на LLM-вызовах.**

```
Frontend postTurn() → POST /api/turn → handleTurn() → discoveryFlow()
  → processDiscoveryTurn() → llmDiscoveryStep() → chatCompletionJSON()
  → chatCompletion() → OpenAI SDK create() ← НЕТ TIMEOUT
```

Fireworks glm-5 API может отвечать >30s или зависнуть → весь HTTP-запрос блокируется. Фронтенд не имеет авто-timeout — только ручная отмена.

## Scope: P0 фиксы + фронтенд timeout

Минимальный набор для рабочего демо. 3 файла, ~45 минут.

### Fix 1: LLM timeout (`asc-demo/src/llm.js`)

**Что**: добавить `timeout` в OpenAI SDK клиент и per-request.

- Line 25: `new OpenAI({ apiKey, baseURL, timeout: 30_000 })`
- Line 73-78: передать `{ timeout: opts.timeout || 30_000 }` вторым аргументом в `.create()`

Existing `catch` blocks в `discovery.js:313`, `brief.js`, `summary-generator.js` УЖЕ переключаются на fallback при ошибке — дополнительных изменений в вызывающих модулях не нужно.

### Fix 2: statusFlow timeout (`asc-demo/src/router.js`)

**Что**: обернуть `await session.summaryPromise` в Promise.race с 90s timeout.

- Добавить утилиту `withTimeout(promise, ms, fallback)` в начало файла
- Line 276: `await withTimeout(session.summaryPromise, 90_000, null)`

### Fix 3: Frontend auto-timeout (`asc-demo/public/app.js`)

**Что**: добавить `AbortSignal.timeout(90_000)` + обработку `TimeoutError`.

- Line 2239: `AbortSignal.any([abortController.signal, AbortSignal.timeout(90_000)])`
- Lines 2242-2246: отдельная обработка `TimeoutError` с сообщением "Превышено время ожидания"

## Deferred (не в этот коммит)

| # | Issue | Severity |
|---|-------|----------|
| 1 | Express request timeout middleware | P1 |
| 2 | syncTopicAnswers не записывает файлы | P2 |
| 3 | Binary file excerpt guard | P2 |
| 4 | Server restart promise recovery | P3 |
| 5 | Python adapter subprocess timeout | P3 |

## Verification

1. `node --check asc-demo/src/llm.js asc-demo/src/router.js asc-demo/server.js`
2. Запустить сервер → загрузить файл → ответ за <35s (или fallback)
3. `./tests/run.sh --lane component --filter 'component_agent_factory_web' --json`

## Key Files

- `asc-demo/src/llm.js` — PRIMARY: timeout на OpenAI SDK
- `asc-demo/src/router.js` — statusFlow timeout wrapper
- `asc-demo/public/app.js` — frontend AbortSignal.timeout

---

## Execution Status (2026-03-19)

- [x] Fix 1: `asc-demo/src/llm.js` — добавлен SDK client timeout `30_000` и per-request timeout в `chat.completions.create(...)`
- [x] Fix 2: `asc-demo/src/router.js` — `statusFlow` ждёт `summaryPromise` через `withTimeout(..., 90_000, null)`
- [x] Fix 3: `asc-demo/public/app.js` — добавлен frontend auto-timeout `90_000` для `/api/turn` и явная обработка `TimeoutError`
- [x] Дополнительно: синхронизирован компонентный тест delivery на 4 артефакта (с учётом production-simulation)

### Verification (passed)

1. `node --check asc-demo/src/llm.js`
2. `node --check asc-demo/src/router.js`
3. `node --check asc-demo/public/app.js`
4. `bash tests/run.sh --lane component --filter 'component_agent_factory_web' --json`
5. `bash tests/integration_local/test_agent_factory_web_flow.sh`
6. `bash tests/integration_local/test_agent_factory_web_confirmation.sh`
7. `bash tests/integration_local/test_agent_factory_web_handoff.sh`
