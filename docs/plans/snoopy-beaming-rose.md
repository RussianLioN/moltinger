# Ревью и обновлённый план: ASC Demo Stabilization

**Дата**: 2026-03-21
**Исходный документ**: `docs/plans/asc-demo-clean-room-parity-implementation-master-plan.md`
**Ветка**: `024-web-factory-demo-adapter`

---

## Контекст

Master plan описывает 8 фаз стабилизации `demo.ainetic.tech`. После детального анализа кодовой базы, Beads-трекера (16 in-progress issues), спецификации (Phase 9, T063-T080), и связанных документов выявлены структурные проблемы плана, требующие обновления.

---

## Ревью: проблемы текущего плана

### 1. Фантомная зависимость: `$clean-room-ui-clone` не существует

Навык `$clean-room-ui-clone` упоминается в фазах 1 и в консолидированном вердикте, но **не создан** — нет ни SKILL.md, ни command-файла. Весь Phase 1 (Reference Capture) заблокирован этой зависимостью.

### 2. Неназванный эталон (RESOLVED)

Эталон: **Codex App** (Version 26.318.11754 (1100)). Видео-референс: `/Users/rl/Movies/2026-03-20 01-09-26.mp4`. UX-контракт зафиксирован в `docs/reports/codex-ui-reference-behavior-2026-03-20.md`. Панельные user stories US-01..US-05 уже реализованы (sidebar toggle, hover divider, double-click reset, drag-resize, fullscreen right panel). Открытый P0/P1 backlog из reference: sticky composer, chat-first фокус, читаемость transcript.

### 3. Backlog Harvest (Phase 2) уже выполнен на ~80%

В Beads-трекере 16 in-progress issues, покрывающих основные P0/P1 дефекты. Phase 2 «сначала собрать, потом чинить» избыточна — harvest уже произошёл.

### 4. Дублирование с Phase 9 спецификации

`specs/024-web-factory-demo-adapter/tasks.md` содержит Phase 9 (T063-T080) — «P0 Clarification Hardening». Эти задачи пересекаются с Phases 3-5 master plan, но с другой декомпозицией. Нет маппинга.

### 5. Нет привязки к файлам и Beads issues

Plan описывает ЧТО чинить, но не КАК — нет указаний на конкретные файлы, функции и строки кода. Нет маппинга `molt-*` issues к фазам.

### 6. Verification вынесена в отдельную фазу

Phase 7 (Verification) после всех волн фиксов — слишком поздно. Verification должна быть встроена в каждую волну.

### 7. Migration Gate преждевременна

Phase 8 не имеет входных данных до закрытия P0/P1. Занимает место в плане без actionable-контента.

---

## Обновлённый план: 5 волн с интегрированной верификацией

### Архитектурное понимание

**State flow**: `gate_pending` → `discovery` → `awaiting_confirmation` → `confirmed` → `downloads_ready`

**Корневая проблема routing**: Frontend определяет `sidePanelMode()` из нескольких перекрывающихся полей (`ui_projection.side_panel_mode`, наличие `download_artifacts`, `reply_cards[].card_kind`), а backend задаёт `preferred_ui_action` и `side_panel_mode` через отдельные builder-функции. Нет единой transition matrix.

**Корневая проблема OnePage**: `summary-generator.js:generateArtifacts()` вызывает `loadDemoData()`, читающий `boku-do-manzh.json` — захардкоженные данные клиента. 4 секции генерируются из этих данных с нулевой привязкой к ответам пользователя из discovery и brief.

### Canonical source files

| Слой | Файлы |
|------|--------|
| Frontend shell | `web/agent-factory-demo/{index.html, app.css, app.js}` |
| Deploy copy | `asc-demo/public/` (синхронизируется из `web/agent-factory-demo/`) |
| Action routing | `asc-demo/src/router.js` |
| API envelopes | `asc-demo/src/response-builder.js` |
| Discovery | `asc-demo/src/discovery.js` |
| Brief | `asc-demo/src/brief.js` |
| Artifacts | `asc-demo/src/summary-generator.js` |
| LLM client | `asc-demo/src/llm.js` |
| Sessions | `asc-demo/src/sessions.js` |
| Prompts | `asc-demo/src/prompts/*.md` |

---

### Wave 0: Инструментарий и baseline (предусловие)

**Цель**: Создать навык `clean-room-ui-clone`, зафиксировать baseline-скриншоты текущего состояния.

#### 0.1 Создать `clean-room-ui-clone` skill

**Файл**: `.claude/skills/clean-room-ui-clone/SKILL.md`

Skill оборачивает Playwright MCP tools в три операции:

- **`capture <url>`**: Навигация → скриншоты 11 состояний (empty workspace, active chat, sidebar expanded/collapsed, right panel states, brief review, preview, long transcript, loading) → DOM snapshot через `mcp__playwright__browser_snapshot` → computed styles через `mcp__playwright__browser_evaluate` → сохранение в `artifacts/ref/<name>/`
- **`plan-clone <ref-name>`**: Анализ captured артефактов → генерация `clone-plan.md` (упорядоченный список UI-элементов для воспроизведения) и `parity-matrix.md` (поэлементная таблица сравнения)
- **`verify <ref-name>`**: Прогон тех же состояний на demo app → скриншоты → сравнение с parity matrix

Паттерн для структуры: `.claude/skills/webapp-testing/SKILL.md`

Артефакты (вне git): `artifacts/ref/<reference-name>/screenshots/`, `dom.json`, `computed-styles.json`, `assets-manifest.json`, `capture-manifest.json`, `clone-plan.md`, `parity-matrix.md`

#### 0.2 Baseline capture текущего demo

Снять 5+ скриншотов текущего `demo.ainetic.tech` для regression-сравнения после фиксов.

#### 0.3 Reference capture Codex App (если доступен)

Эталон: **Codex App** (Version 26.318.11754 (1100)).
Видео-референс: `/Users/rl/Movies/2026-03-20 01-09-26.mp4`.
UX-контракт: `docs/reports/codex-ui-reference-behavior-2026-03-20.md`.

Если Codex App доступен в браузере — выполнить `capture` через skill. Если только desktop app — использовать существующее видео и UX-контракт как source of truth.

Уже реализованные Codex-паттерны (US-01..US-05): sidebar toggle, hover divider, double-click reset, drag-resize, fullscreen right panel.

Открытые parity items из Codex reference:
- P0: Sticky composer, chat-first фокус, компактная лента
- P1: Увеличение line-height/плотности текста, discoverability кнопок, copy action на сообщениях

**Acceptance**: SKILL.md создан; baseline demo-скриншоты зафиксированы; parity matrix обновлена с учётом Codex reference.

---

### Wave 1: P0 Routing и State Machine

**Цель**: Устранить разрывы между frontend action routing и backend state machine. Починить главные happy-path breaks.

| # | Задача | Beads | Spec T# | Файлы |
|---|--------|-------|---------|-------|
| 1.1 | Text-based confirm_brief detection | `molt-d2r` | T076 | `router.js` |
| 1.2 | input_examples deadlock после CSV upload | `molt-kft` | T067, T075 | `discovery.js`, `router.js` |
| 1.3 | Переход к brief после success_metrics | `molt-ypy`, `molt-oub` | — | `discovery.js`, `router.js` |
| 1.4 | Attachment chip persistence | `molt-gyw` | — | `app.js` |

#### 1.1 Text-based confirm_brief (router.js)

В `router.js:458` routing проверяет `action === "confirm_brief"`, но action приходит из `ui_action` в envelope. Если пользователь пишет «Подтверждаю» текстом, action = `submit_turn`.

**Изменение**: Добавить `CONFIRM_BRIEF_MARKERS` (по аналогии с `BRIEF_CORRECTION_MARKERS` на строке 177) и `isLikelyConfirmBriefText()`. В блоке routing (строка ~458): когда `session.stage === "awaiting_confirmation"` и `isLikelyConfirmBriefText(userText)`, обрабатывать как `confirm_brief`.

#### 1.2 input_examples deadlock (discovery.js, router.js)

После CSV upload `router.js:319-320` ставит `coveredTopics.add("input_examples")`, но это происходит ДО вызова `processDiscoveryTurn()`, который может переопределить nextTopic обратно на `input_examples`.

**Изменение**: В `discovery.js:processDiscoveryTurn()` — после шага LLM, если `session.coveredTopics.has("input_examples")` и step.nextTopic === `input_examples`, принудительно сдвинуть на следующий uncovered topic. Усилить `applyAntiLoopGuard()` для проверки не только repeated question, но и re-ask covered topic.

#### 1.3 Post-success_metrics переход к brief (discovery.js, router.js)

После ответа на success_metrics discovery может не завершиться, если `completionReached()` (discovery.js) не считает тему покрытой из-за heuristic text matching.

**Изменение**: В `finalizeDiscoveryStep()` — когда `lowSignal === false` и это последний uncovered topic, всегда считать его покрытым, не зависимо от `meaningfulTextForCurrentTopic`.

#### 1.4 Attachment chip (app.js)

**Изменение**: В send handler после успешного submit очищать `project.pendingUploads = []` и вызывать `renderAttachmentList(project)`.

#### Verification Wave 1

- Manual walkthrough: gate → 7 тем → auto-transition to brief
- CSV upload → нет re-ask input_examples
- Текст «подтверждаю» в awaiting_confirmation → confirm_brief transition
- Скриншоты через clean-room-ui-clone capture

---

### Wave 2: P0 Result Flow и OnePage Quality

**Цель**: Сделать post-confirm flow рабочим с реальными данными пользователя.

| # | Задача | Beads | Spec T# | Файлы |
|---|--------|-------|---------|-------|
| 2.1 | Right panel auto-open после confirm | `molt-2xg.1` | T077 | `app.js` |
| 2.2 | Empty preview fix | `molt-2xg.2` | T068 | `app.js`, `server.js` |
| 2.3 | OnePage из данных пользователя (не demo data) | `molt-2xg.3` | T069, T078, T079 | `summary-generator.js` |
| 2.4 | Сбор result_format в discovery | `molt-2xg.4` | — | `discovery.js` |

#### 2.1 Right panel auto-open (app.js)

Backend уже ставит `side_panel_mode: "downloads"` в `buildHandoffRunningResponse()` (response-builder.js). Frontend не реагирует.

**Изменение**: В response sync logic, при `sourceAction === "confirm_brief"`, вызывать `openPanelMode(project, "downloads")`.

#### 2.2 Empty preview (app.js, server.js)

**Изменение**: В `renderPreviewPanel()` проверить iframe src с корректным session ID. В `server.js` preview endpoint — проверить, что artifact.content не пустой.

#### 2.3 OnePage из реальных данных (summary-generator.js) — КРИТИЧЕСКАЯ ЗАДАЧА

Сейчас `generateArtifacts()` загружает `boku-do-manzh.json` и генерирует 4 секции из статических данных. Данные пользователя (brief, topicAnswers, uploaded files excerpts) полностью игнорируются.

**Изменение — два пути**:

**Путь A (есть uploaded CSV/data)**: Парсить `session.uploadedFiles[].excerpt` (до 1200 chars, router.js:87) в структуру, аналогичную `boku-do-manzh.json`. Подавать в существующий `SECTION_CONFIG` pipeline. Дополнять из brief/topicAnswers.

**Путь B (только текстовый discovery)**: Новая функция `generateOnePageFromBrief(session)` — генерация OnePage напрямую из `session.briefText` + `session.topicAnswers` + `session.conversationHistory` через LLM-промпт.

В `generateArtifacts()`: проверить наличие usable excerpts в `session.uploadedFiles` → Путь A или B → always pass session для обогащения.

#### 2.4 result_format в discovery (discovery.js)

Не добавлять новый topic (ломает 7-topic completion). Расширить prompt для `expected_outputs`, чтобы явно спрашивать о формате.

#### Verification Wave 2

- confirm_brief → right panel auto-opens «preparing artifacts»
- Preview показывает реальный контент из discovery данных
- OnePage содержит факты из brief, а не «Боку до манж»
- Download выдаёт .md с session-specific контентом

---

### Wave 3: P1 Discovery / Brief / Architect Logic

**Цель**: Улучшить качество вопросов и точность revision.

| # | Задача | Beads | Spec T# | Файлы |
|---|--------|-------|---------|-------|
| 3.1 | Brief edit в неправильную секцию | `molt-khh` | T066, T073 | `brief.js` |
| 3.2 | Service phrases в brief | `molt-hzn` | T074 | `brief.js`, `response-builder.js` |
| 3.3 | In-flight agent indicator | `molt-d07` | T072 | `app.js`, `index.html` |

#### 3.1 Section-targeted brief edit (brief.js)

`inferCorrectionTargets()` (строка ~180) маппит keywords → topic IDs. Проблема в LLM prompt: не запрещает менять другие секции.

**Изменение**: Усилить system prompt в `reviseBrief()`: «ONLY modify the sections listed in correction guidance.» Добавить diff-based проверку в `sanitizeRevisedBrief()`: отклонять изменения в секциях, не входящих в correction targets.

#### 3.2 Service phrases (brief.js, response-builder.js)

«Требуется уточнение», «Файлы в discovery не загружались» протекают в видимый brief.

**Изменение**: В `fallbackBrief()` заменить «Требуется уточнение.» на нейтральный текст. Добавить post-processing `normalizeBrief()` для strip known service phrases.

#### 3.3 In-flight indicator (app.js)

`workspace-agent-state` элемент (index.html:125-128) и `composer-thinking` (index.html:166-168) уже существуют, но скрыты.

**Изменение**: В send handler сразу после API request — `dom.agentStatus.hidden = false`. На response — `dom.agentStatus.hidden = true`. Привязать `renderAgentStatus()` (app.js:1353) к lifecycle запроса.

#### Verification Wave 3

- «измени метрики успеха» → меняется только эта секция
- Нет service phrases в rendered brief cards
- Spinner видим при LLM processing, скрыт после response

---

### Wave 4: P1 UX/UI Stabilization + Codex Parity

**Цель**: Исправить layout, поведение панелей, и довести UX до Codex parity (P0/P1 items из reference).

**Codex reference**: `docs/reports/codex-ui-reference-behavior-2026-03-20.md`
**Уже реализовано** (US-01..US-05): sidebar toggle, hover divider, double-click reset, drag-resize, right panel fullscreen.

| # | Задача | Beads | Spec T# | Файлы |
|---|--------|-------|---------|-------|
| 4.1 | Sticky topbar | `molt-sus`, `molt-n4m` | T064, T070 | `app.css`, `index.html` |
| 4.2 | Scroll anchoring | `molt-4dp` | T065, T071 | `app.js` |
| 4.3 | Sticky composer + chat-first фокус | — (Codex P0) | — | `app.css`, `app.js` |
| 4.4 | Компактность transcript | — (Codex P1) | — | `app.css` |

#### 4.1 Sticky topbar (app.css, index.html)

**Изменение**: `header.workspace-topbar` → `position: sticky; top: 0; z-index: 10;`. Родитель `.workspace` не должен иметь `overflow: hidden`. Brief/panel toggle button (`data-role="side-panel-toggle"`) уже в topbar → станет sticky автоматически.

#### 4.2 Scroll anchoring (app.js)

`scheduleScrollChatToBottom()` (строки ~1826-1877) сбрасывает позицию при layout shift от sidebar resize.

**Изменение**: Auto-scroll только если пользователь в пределах ~80px от низа. `ResizeObserver` на chat log container для сохранения относительной позиции при layout changes.

#### 4.3 Sticky composer + chat-first (app.css, app.js)

Codex P0: composer всегда виден внизу, chat scroll не уезжает под него.

**Изменение**: `.composer-dock` → `position: sticky; bottom: 0;`. Thread panel получает `flex: 1; overflow-y: auto;` чтобы скроллился только chat log, а composer оставался на месте. Auto-focus input при загрузке workspace.

#### 4.4 Компактность transcript (app.css)

Codex P1: меньше служебного мусора, понятное разделение подтверждений и вопросов.

**Изменение**: Увеличить `line-height` текста сообщений, уменьшить padding карточек, ослабить визуальный шум secondary elements (timestamps, badges). Добавить визуальное разделение между confirmation messages и next question.

#### Verification Wave 4

- Topbar sticky при скролле длинного transcript
- Composer sticky внизу при скролле
- Sidebar collapse/expand не прыгает scroll
- New messages auto-scroll только при bottom position
- Transcript визуально чище, вопрос выделяется от confirmation

---

### Wave 5: Sync, Deploy, E2E Verification

**Цель**: Зафиксировать фиксы на `demo.ainetic.tech`.

| # | Задача | Файлы |
|---|--------|-------|
| 5.1 | Sync frontend | Копия `web/agent-factory-demo/*` → `asc-demo/public/` |
| 5.2 | Commit + push + remote deploy | Per RCA remote bundle drift |
| 5.3 | Full walkthrough на demo.ainetic.tech | gate → discovery → brief → corrections → confirm → preview → download |
| 5.4 | Parity screenshot comparison | clean-room-ui-clone verify vs baseline |

**Acceptance**: Все P0 Beads issues закрыты. Полный цикл завершается без stuck states на production.

---

### Консолидированный маппинг: Beads ↔ Waves ↔ Spec Tasks

| Beads ID | Wave | Задача | Spec T# |
|----------|------|--------|---------|
| `molt-d2r` | 1 | 1.1 Text confirm_brief | T076 |
| `molt-kft` | 1 | 1.2 input_examples deadlock | T067, T075 |
| `molt-ypy` | 1 | 1.3 Post-success_metrics | — |
| `molt-oub` | 1 | 1.3 Brief-review message | — |
| `molt-gyw` | 1 | 1.4 Attachment chip | — |
| `molt-2xg.1` | 2 | 2.1 Right panel auto-open | T077 |
| `molt-2xg.2` | 2 | 2.2 Empty preview | T068 |
| `molt-2xg.3` | 2 | 2.3 OnePage из реальных данных | T069, T078, T079 |
| `molt-2xg.4` | 2 | 2.4 result_format collection | — |
| `molt-khh` | 3 | 3.1 Brief section targeting | T066, T073 |
| `molt-hzn` | 3 | 3.2 Service phrases | T074 |
| `molt-d07` | 3 | 3.3 In-flight indicator | T072 |
| `molt-sus` | 4 | 4.1 Sticky topbar | T064, T070 |
| `molt-n4m` | 4 | 4.1 Brief button in topbar | T064, T070 |
| `molt-4dp` | 4 | 4.2 Scroll anchoring | T065, T071 |

### Отложенные задачи (не в этом плане)

| Задача | Причина |
|--------|---------|
| Полный Codex capture (если desktop-only) | Видео-референс уже есть, browser capture зависит от доступности |
| Phase 8 Migration Gate (Next.js) | Преждевременно — P0/P1 не закрыты |
| `molt-6xx` Live smoke checks | Зависит от стабилизации API |
| `molt-7x7` Persist access hash | Ops task, не blocking |
| `molt-svm` CI-managed rollout | Infra, не blocking |
| `molt-x3o` Playwright e2e runtime | Зависит от стабилизации |
| Session persistence (in-memory) | Приемлемо для demo |

---

## Порядок зависимостей

```
Wave 0 (инструментарий)
  │
  ├── Wave 1 (routing/state machine) ← блокирует всё остальное
  │     │
  │     ├── Wave 2 (result flow/OnePage) ← зависит от корректных transitions
  │     │     │
  │     │     └── Wave 3 (brief/discovery quality) ← зависит от рабочего result flow
  │     │
  │     └── Wave 4 (UX/UI) ← может идти параллельно с Wave 3
  │
  └── Wave 5 (deploy + e2e) ← после всех waves
```

Wave 0 можно делать параллельно с Wave 1 (разные файлы).
Wave 3 и Wave 4 можно делать параллельно (backend vs CSS/scroll).

---

## Верификация end-to-end

После каждой волны:
1. Component check: тип-проверка отсутствует (vanilla JS), ручной review
2. Local walkthrough: `cd asc-demo && npm run dev`, пройти полный сценарий
3. Скриншоты: capture текущего состояния через clean-room-ui-clone
4. Beads update: закрыть решённые issues

После Wave 5 (финально):
5. Remote walkthrough на `demo.ainetic.tech`
6. Regression cases: нет duplicate question, нет stuck state, preview работает, download non-empty, refresh восстанавливает, topbar sticky
