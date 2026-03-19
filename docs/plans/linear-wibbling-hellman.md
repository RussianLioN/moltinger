# Plan: Full Review & Critical Fixes — ASC Demo Factory Prototype

## Context

ASC Demo — прототип AI Agent Factory для демо через несколько часов. Timeout-фиксы (commit `77e58d9`) уже применены. Теперь нужно устранить критические проблемы, которые ломают **полный цикл** фабрики: discovery → brief → artifacts.

Цель: минимальные точечные правки, которые делают весь цикл рабочим и надёжным.

---

## Findings (приоритизировано по влиянию на демо)

### P0 — Ломает демо

**F1. Brief не использует `topicAnswers` — только историю чата** (`brief.js:37-46,68`)
- `generateBrief()` передаёт LLM только `conversationHistory` через `buildConversationSummary()`
- `topicAnswers` (структурированные ответы по темам) и `uploadedFiles` — игнорируются
- Fallback brief (`brief.js:14-24`) использует `topicAnswers`, но если LLM сгенерировал brief — данные из topicAnswers потеряны
- **Результат**: brief может быть неполным, особенно если `input_examples` покрыт файлом без текста

**F2. `syncTopicAnswers` не записывает файлы** (`discovery.js:151-161`)
- Когда пользователь загружает файл без текста, `syncTopicAnswers` получает пустой `userText` и bail out на line 153
- `topicAnswers.input_examples` остаётся `""` → в fallback brief и презентации секция "Входные данные" показывает "Требуется уточнение"
- **Результат**: артефакты (presentation, fallback brief) показывают пустые секции

**F3. Presentation и Agent Spec используют `topicAnswers` напрямую** (`summary-generator.js:134-154`)
- `buildPresentation()` берёт `session.topicAnswers?.problem` и т.д.
- Если topicAnswers пустые из-за F2 → "Требуется уточнение" на всех слайдах
- **Результат**: скачиваемые артефакты выглядят сломанными

### P1 — Заметно при демо

**F4. System prompt архитектора слишком короткий** (`prompts/architect-system.md`, 22 строки)
- Нет описания тем (LLM не знает, что значит `input_examples` vs `expected_outputs`)
- Нет примеров хороших/плохих ответов
- Нет инструкции про файлы
- **Результат**: LLM слабо оценивает покрытие тем и задаёт нерелевантные вопросы

**F5. Discovery может зациклиться на одном вопросе** (`discovery.js:184-196`)
- Когда LLM fallback (ошибка/timeout) ставит `lowSignal=false`, `finalizeDiscoveryStep` на line 184 проверяет `activeTopicCovered`, но если текст не содержит сигналов текущей темы → тема НЕ закрывается
- LLM fallback выбирает тот же `nextTopic` (первый незакрытый) → пользователь видит тот же вопрос
- **Результат**: ощущение что фабрика зависла

**F6. `reviseBrief()` не передаёт контекст discovery** (`brief.js:94-114`)
- Только текущий brief + текст правки. LLM не видит ни `topicAnswers`, ни историю
- Если пользователь просит "добавь подробности про входные данные" → LLM галлюцинирует
- **Результат**: правки brief могут содержать выдуманные факты

**F7. Два файла `app.js` расходятся** (`asc-demo/public/app.js` vs `web/agent-factory-demo/app.js`)
- `web/` версия имеет `IS_AUTOMATION` detection + conditional timeout, sidebar resizer
- `asc-demo/` версия не имеет этого
- **Результат**: при деплое непонятно какой файл правильный

### P2 — Косметика / resilience (deferred)

- F8. `statusFlow` confirmed без promise → нет recovery `runSummaryGeneration()` (`router.js:293`)
- F9. `loadDemoData()` не кэшируется (`summary-generator.js:42-46`)
- F10. One-page summary всегда генерируется из hardcoded demo-data, а не из brief (`summary-generator.js:157`)
- F11. Token length timing leak в `validAccessToken()` (`router.js:65-68`)

---

## Implementation Plan

### Commit 1: Fix data flow through full cycle (F1, F2, F3)

#### 1.1 Fix `syncTopicAnswers` для файлов (`discovery.js:151-161`)

Добавить `uploadedFiles` параметр. Если text пустой но есть файлы → записать имена файлов:

```javascript
function syncTopicAnswers(session, userText, newCoverage, uploadedFiles = []) {
  const text = normalizeText(userText);
  const fileNames = (uploadedFiles || []).map((f) => f.name).filter(Boolean);
  const effectiveText = text
    || (fileNames.length ? `Приложены файлы: ${fileNames.join(", ")}` : "");
  if (!effectiveText) return;
  newCoverage.forEach((topicId) => {
    if (!session.topicAnswers[topicId]) {
      session.topicAnswers[topicId] = effectiveText;
    }
  });
}
```

Обновить вызов на line 322: передать `uploadedFiles`.

#### 1.2 Fix `generateBrief` — включить topicAnswers (`brief.js:48-80`)

Добавить структурированный контекст из `topicAnswers` в user message:

```javascript
// После line 67, перед buildConversationSummary:
buildTopicSummary(session),  // NEW
"",
"Полная история диалога:",
buildConversationSummary(session),
```

Где `buildTopicSummary` форматирует `topicAnswers` в markdown:

```javascript
function buildTopicSummary(session) {
  const answers = session.topicAnswers || {};
  const lines = ["Собранные ответы по темам:"];
  BRIEF_SECTION_ORDER.forEach(([topicId, title]) => {
    const answer = normalizeText(answers[topicId]);
    if (answer) lines.push(`- ${title}: ${answer}`);
  });
  if (session.uploadedFiles?.length) {
    lines.push(`- Загруженные файлы: ${session.uploadedFiles.map(f => f.name).join(", ")}`);
  }
  return lines.join("\n");
}
```

#### 1.3 Fix `reviseBrief` — добавить контекст (`brief.js:94-114`)

В user message (line 106-113) добавить `buildTopicSummary(session)` перед текущим brief. Минимальное изменение — одна строка.

### Commit 2: Fix discovery quality (F4, F5)

#### 2.1 Расширить system prompt (`prompts/architect-system.md`)

Добавить:
- Описание каждой из 7 тем (1-2 строки на тему)
- Правило: "Если пользователь приложил файлы, тема `input_examples` считается закрытой"
- Правило: "НЕ возвращай в `next_topic` тему, которая уже в `covered_topics`"
- Пример хорошего ответа (JSON)

Объём: ~50 строк (вместо текущих 22). Не over-engineering — просто достаточный контекст.

#### 2.2 Guard против зацикливания (`discovery.js:184-196`)

После `finalizeDiscoveryStep`, добавить проверку: если `nextTopic` === предыдущий `session.currentTopic` И вопрос тот же → принудительно продвинуть на следующую незакрытую тему:

```javascript
// After line 215, before return
if (result.nextTopic === session.currentTopic
    && normalizeText(result.nextQuestion) === normalizeText(session.currentQuestion)) {
  const fallback = defaultQuestion(result.coveredTopics);
  if (fallback.nextTopic && fallback.nextTopic !== result.nextTopic) {
    result.nextTopic = fallback.nextTopic;
    result.nextQuestion = getTopicById(fallback.nextTopic)?.question || fallback.nextQuestion;
    result.whyAskingNow = getTopicById(fallback.nextTopic)?.why || fallback.whyAskingNow;
  }
}
```

### Commit 3: Sync frontend files (F7)

Скопировать `web/agent-factory-demo/app.js` → `asc-demo/public/app.js`. Файл `web/` — canonical source (документировано в `asc-demo/CLAUDE.md`).

---

## Phase 2: UX — Preview, Factory Result Focus, Cleanup (NEW)

### Context

E2E прошёл на demo.ainetic.tech. Пользователь просит:
1. **Preview в браузере** — возможность просмотреть артефакты (особенно OnePage) прямо в side panel, а не только скачивать
2. **Фокус на результат фабрики** — после confirm brief фабрика должна спросить "Готовы протестировать цифровой актив?" → после подтверждения → показать сгенерированный OnePage
3. **Иерархия артефактов** — OnePage summary как главный результат (крупно, preview+download), остальные артефакты — мелко, без карточного оформления
4. **Убрать избыточный дизайн** — остальные артефакты без облачков/карточек, простой список

### UX1: Добавить preview endpoint (`asc-demo/server.js`)

Новый route `GET /api/preview/:sessionId/:artifactKind`:
```
- Content-Type: text/html (markdown rendered to HTML)
- Без Content-Disposition: attachment (открывается в браузере)
- Простая обёртка: <html><body style="...">{markdown→html}</body></html>
- Использовать тот же getArtifact() что и download
- Markdown→HTML: простой regex для ## → h2, - → li, \n\n → <p> (прототип, без библиотек)
```

### UX2: Промежуточный шаг "протестировать актив" (`asc-demo/src/router.js`)

После `confirm_brief` → `runSummaryGeneration()` → вместо прямого перехода в `downloads_ready`:

1. Новый stage: `testing_prompt` (после генерации артефактов)
2. Ответ: "Фабрика создала цифровой актив. Хочешь протестировать его в работе?"
3. Action: `test_asset` → показать OnePage preview в side panel + download
4. Остальные артефакты доступны как secondary downloads

**Минимальная реализация**: вместо нового stage, используем существующий `downloads_ready` но меняем reply_cards:
- Главный card: `factory_result_prompt` — "Цифровой актив создан. Посмотри результат работы фабрики."
- Action: `preview_one_page` — открывает preview в side panel
- Secondary: список остальных артефактов как текст (не карточки)

### UX3: Рефакторинг side panel для preview (`asc-demo/public/app.js`, `index.html`, `app.css`)

**Side panel modes** (добавить `preview`):
```
hidden → brief_review → downloads → preview (NEW)
```

**Preview mode**:
- iframe или div с rendered markdown OnePage summary
- Кнопка "Скачать" под preview
- Под preview — компактный список остальных артефактов (plain links, без карточек)

**Downloads mode** (переделать):
- OnePage summary — крупная карточка с кнопками "Просмотреть" + "Скачать"
- Остальные 3 артефакта — простой список ссылок, мелкий шрифт, без card оформления

### UX4: Изменить `buildDownloadsReadyResponse` (`response-builder.js`)

Вместо generic "Артефакты готовы":
```javascript
reply_cards: [
  {
    card_kind: "factory_result",
    title: "Цифровой актив создан",
    body_text: "Фабрика завершила работу. Посмотри результат — OnePage Summary по клиенту.",
    action_hints: ["preview_one_page", "download_artifact"],
  },
]
```

И в `ui_projection`:
```javascript
preferred_ui_action: "preview_one_page",
side_panel_mode: "downloads",
primary_artifact: "one_page_summary",  // NEW — фронтенд знает какой артефакт главный
```

## Deferred (не блокирует демо)

| # | Issue | Why deferred |
|---|-------|-------------|
| F8 | statusFlow recovery при рестарте | Прототип, рестарт маловероятен |
| F9 | Кэш loadDemoData | Микро-оптимизация |
| F11 | Token length timing | Прототип |

## Verification

1. `node --check` для всех изменённых файлов
2. Ручной прогон полного цикла: gate → discovery → brief → confirm → preview OnePage → download
3. Проверить: OnePage рендерится в side panel как HTML
4. Проверить: остальные артефакты — мелкий список без карточек
5. `./tests/run.sh --lane component --filter 'component_agent_factory_web' --json`

## Key Files

- `asc-demo/src/discovery.js` — syncTopicAnswers fix, anti-loop guard
- `asc-demo/src/brief.js` — topicAnswers в prompt, reviseBrief context
- `asc-demo/src/prompts/architect-system.md` — расширенный system prompt
- `asc-demo/server.js` — NEW: preview endpoint
- `asc-demo/src/response-builder.js` — factory_result card, primary_artifact
- `asc-demo/public/app.js` — preview mode в side panel, компактные артефакты
- `asc-demo/public/index.html` — preview container в side panel template
- `asc-demo/public/app.css` — стили preview, компактный список артефактов

---

## Execution Status (2026-03-19)

- [x] Fix 1: `asc-demo/src/llm.js` — SDK client timeout `30_000` и per-request timeout (prev commit)
- [x] Fix 2: `asc-demo/src/router.js` — `statusFlow` timeout wrapper (prev commit)
- [x] Fix 3: `asc-demo/public/app.js` — frontend auto-timeout `90_000` (prev commit)
- [x] F1+F2+F3: Data flow через полный цикл (brief, topicAnswers, files)
- [x] F4+F5: Discovery quality (prompt, anti-loop)
- [x] F7: Sync frontend files
- [x] UX1: Preview endpoint `/api/preview/:sessionId/:artifactKind`
- [x] UX2/UX4: Factory-result first response + `preview_one_page` + `primary_artifact`
- [x] UX3: Side-panel preview mode + primary one-page card + compact secondary artifacts list
- [x] `molt-0sx`: semantic routing conversational brief corrections (LLM guidance + deterministic fallback mapping)
