# Plan: ASC Demo Backend — Code Review Fixes

## Context

Code review выявил 16 замечаний разной критичности в `asc-demo/` backend.
Цель — устранить P0-P2 замечания, повысив безопасность, надёжность и качество кода прототипа без over-engineering.

---

## Task 1: Вынести `normalizeText` в shared utils (P1, дублирование)

**Проблема**: 5 идентичных копий `normalizeText` в `router.js`, `discovery.js`, `response-builder.js`, `brief.js`, `summary-generator.js`.

**Действие**:
1. Создать `asc-demo/src/utils.js` с единственным экспортом `normalizeText`
2. Заменить локальные определения на `import { normalizeText } from "./utils.js"` во всех 5 файлах
3. Удалить локальные копии функции

**Файлы**:
- `asc-demo/src/utils.js` (новый)
- `asc-demo/src/router.js` (строки 7-16)
- `asc-demo/src/discovery.js` (строки 60-69)
- `asc-demo/src/response-builder.js` (строки 15-24)
- `asc-demo/src/brief.js` (строки 13-22)
- `asc-demo/src/summary-generator.js` (строки 36-45)

---

## Task 2: Персистентность сессий на файловой системе (P1, memory leak + durability)

**Проблема**: `sessions` Map живёт только в RAM — при рестарте сервера все сессии теряются, а при длительной работе Map растёт бесконечно.

**Требование пользователя**: Пользователи должны иметь возможность вернуться к любому проекту в любое время.

**Действие**:
1. В `asc-demo/src/sessions.js` добавить файловую персистентность:
   - При каждом `updateSession`/`setSessionResponse`/`setSessionArtifacts` — сериализовать сессию в JSON-файл: `asc-demo/data/sessions/<sessionId>.json`
   - При `getSession` — если нет в Map, попытаться загрузить из файла
   - При старте сервера — НЕ загружать все сессии в память (lazy load)
2. Обработка несериализуемых полей:
   - `summaryPromise` → не сохранять (transient, при загрузке = null)
   - `coveredTopics` (Set) → сохранять как Array, при загрузке восстанавливать в Set
3. Добавить мягкий eviction из RAM (но НЕ с диска): сессии без обращений >1 час выгружать из Map, оставляя файл
4. Создать директорию `asc-demo/data/sessions/` и добавить `asc-demo/data/` в `.gitignore`

**Файлы**:
- `asc-demo/src/sessions.js` (основные изменения)
- `asc-demo/.gitignore` (новый или обновить, добавить `data/`)

---

## Task 3: Логирование ошибок LLM (P2)

**Проблема**: `void runSummaryGeneration()` и catch-блоки в `brief.js`, `discovery.js`, `summary-generator.js` глотают ошибки без логирования.

**Действие**:
1. Добавить `console.error` в catch-блоки:
   - `router.js:172` (runSummaryGeneration catch)
   - `brief.js:86` (generateBrief catch)
   - `brief.js:128` (reviseBrief catch)
   - `discovery.js:259` (llmDiscoveryStep catch в processDiscoveryTurn)
   - `summary-generator.js:98` (generateSection catch)
2. Формат: `console.error("[asc-demo] <context>:", error?.message || error)`

**Файлы**:
- `asc-demo/src/router.js`
- `asc-demo/src/brief.js`
- `asc-demo/src/discovery.js`
- `asc-demo/src/summary-generator.js`

---

## Task 4: HTTP status для ошибок бэкенда (P0)

**Проблема**: `server.js:57` — внутренние ошибки отдаются как 200, скрывая их от мониторинга.

**Действие**:
1. В `server.js` catch-блок `/api/turn`: изменить `res.status(200)` на `res.status(500)`
2. Добавить `console.error` перед отправкой fallback

**Файлы**:
- `asc-demo/server.js` (строка 57)

---

## Task 5: Timing-safe сравнение токена (P0)

**Проблема**: `router.js:65` — прямое `===` сравнение токена уязвимо к timing attack.

**Действие**:
1. Импортировать `import { timingSafeEqual } from "node:crypto"` в `router.js`
2. Заменить `token === expected` на timing-safe сравнение через Buffer:
```js
function validAccessToken(token) {
  const expected = normalizeText(process.env.DEMO_ACCESS_TOKEN, "demo-access-token");
  if (!token || !expected) return false;
  if (token.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(token), Buffer.from(expected));
}
```

**Файлы**:
- `asc-demo/src/router.js` (строки 63-66)

---

## Task 6: Guard от concurrent confirm_brief (P2)

**Проблема**: Два одновременных `confirm_brief` могут запустить генерацию дважды.

**Действие**:
1. В `router.js` функция `runSummaryGeneration`: установить `session.summaryState = "running"` ДО async операций (уже сделано на строке 162, но проверка в handleTurn на строке 328 проверяет `summaryPromise` — race window между `void runSummaryGeneration()` и установкой promise)
2. Переставить: сначала создать promise, затем `setSessionSummaryPromise`, затем запустить async тело
3. Или проще: в handleTurn перед вызовом добавить `session.summaryState = "running"` и проверять только по `summaryState`

**Файлы**:
- `asc-demo/src/router.js` (строки 325-331)

---

## Не включено (осознанно)

| Замечание | Причина пропуска |
|-----------|-----------------|
| CORS без ограничений | Демо-прототип, ожидаемое поведение |
| Path traversal в download | Безопасно при in-memory хранении |
| `cachedClient` не сбрасывается | env не меняется на лету |
| `summaryPromise` не сериализуем | In-memory only |
| Фронтенд монолит 2500 строк | Отдельная задача, не backend review |
| `DEFAULT_ACCESS_TOKEN` в фронтенде | Задокументировано, демо-режим |
| Health check для LLM API | Over-engineering для прототипа |
| `heuristicCoverage` false positives | Компенсируется LLM-верификацией |
| `syncTopicAnswers` перезапись | Приемлемое упрощение для 7-топиков |
| `buildConversationSummary` лимит 24 | Достаточно для discovery flow |

---

## Трекинг: Beads Epic

**Epic**: `molt-n5l` — Code Review Fixes: ASC Demo Backend (P2)

| Beads ID | Task | Priority |
|----------|------|----------|
| `molt-286` | Extract normalizeText to shared utils | P2 |
| `molt-njq` | Add file-based session persistence | P1 |
| `molt-c8b` | Add LLM error logging in catch blocks | P2 |
| `molt-755` | Return HTTP 500 for backend errors | P0 |
| `molt-8wb` | Use timing-safe token comparison | P0 |
| `molt-l4j` | Guard concurrent confirm_brief race | P2 |

---

## Verification

```bash
cd asc-demo
node --check server.js
node --check src/utils.js
node --check src/router.js
node --check src/sessions.js
node --check src/discovery.js
node --check src/brief.js
node --check src/summary-generator.js
node --check src/response-builder.js
npm start  # smoke test: health endpoint
```

Smoke test API:
```bash
curl -s http://localhost:3000/health | jq .
curl -s -X POST http://localhost:3000/api/turn \
  -H 'Content-Type: application/json' \
  -d '{"web_conversation_envelope":{"ui_action":"request_demo_access"},"demo_access_grant":{"grant_value":"demo-access-token"}}' | jq .status
```
