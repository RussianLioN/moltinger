# Master Plan: ASC Demo Clean-Room Parity & Stabilization

**Дата**: 2026-03-21  
**Статус**: Master Execution Plan  
**Связанные slices**: `024-web-factory-demo-adapter`, `025-asc-demo-llm-backend`  
**Приоритет**: P0 для логики и happy path, P1 для UX/UI parity

---

## Кратко

Этот документ фиксирует основной план доведения `demo.ainetic.tech` до рабочего состояния.

Главная цель:

1. стабилизировать полный цикл `gate -> discovery -> brief -> corrections -> confirm -> preview/download -> production simulation`
2. устранить главный разрыв `frontend action routing <-> backend state machine`
3. довести UX/UI до clean-room parity с эталонным приложением на уровне паттернов поведения, структуры и визуальной иерархии
4. только после этого принять отдельное решение о возможном переходе на `Next.js + TypeScript`

Документ intentionally разделяет:

- **logic stabilization**
- **result-flow stabilization**
- **UX/UI parity**
- **migration gate**

---

## Консолидированный вердикт консилиума

### Что делать сейчас

1. Не мигрировать demo shell на `Next.js + TypeScript` до закрытия P0/P1 логических проблем.
2. Сразу использовать парадигму `$clean-room-ui-clone` как основу для:
   - reference capture
   - clone brief
   - parity matrix
   - visual verification
3. Для внешнего эталона использовать clean-room подход только как **pattern parity**, а не как перенос чужого кода, ассетов и бренд-материалов.

### Почему

- текущий demo уже жёстко связан с существующим `HTML/CSS/JS` shell и backend contract
- главный риск сейчас не в фреймворке, а в логике переходов состояний
- миграция до стабилизации только увеличит число moving parts
- целевой UX/UI можно воспроизвести и в текущем shell-стеке, если сначала привести в порядок state model и interaction model

---

## Архитектурный принцип выполнения

Работа должна идти в четыре волны:

1. `backlog harvest`
2. `P0 logic fix wave`
3. `P1 parity fix wave`
4. `migration gate`

Критическое правило:

- пока не собран полный backlog первой волны, исправления не распыляются по всему продукту
- после завершения harvest сначала чинится только главный источник поломок: `frontend action routing <-> backend state machine`

---

## Фаза 0. Preparation & Governance

### Цель

Подготовить единый управляющий контур, в котором все дальнейшие исправления будут происходить без потери контекста.

### Действия

1. Признать этот документ главным execution-plan для web demo stabilization.
2. Считать `web/agent-factory-demo/*` каноническим frontend source.
3. Считать `asc-demo/public/*` синхронной deploy-проекцией frontend shell.
4. Считать `asc-demo/src/router.js`, `response-builder.js`, `discovery.js`, `brief.js`, `summary-generator.js` каноническим backend runtime слоем.
5. Считать публичный API неизменяемым на период стабилизации:
   - `/api/turn`
   - `/api/session`
   - `/api/preview/:sessionId/:artifactKind`
   - `/api/download/:sessionId/:artifactKind`
6. Вести три параллельных списка:
   - logic backlog
   - UX/UI backlog
   - clean-room reference artifacts

### Acceptance

- есть один master-plan
- все рабочие документы ссылаются на него
- зафиксирован canonical source для frontend и backend

---

## Фаза 1. Clean-Room Reference Capture

### Цель

Создать воспроизводимый reference-пакет для UX/UI parity без нарушения clean-room границ.

### Правила

1. Не копировать чужой исходный код.
2. Не сохранять чужие raw assets, иконки, шрифты, видео и bundle-файлы.
3. Сохранять только:
   - screenshots
   - DOM snapshots
   - whitelisted computed styles
   - hashes и manifests
   - trace
   - parity notes

### Артефакты

Reference артефакты должны лежать вне git как runtime artifacts в формате:

```text
artifacts/ref/<reference-name>/
├── screenshots/
├── trace.zip
├── dom.json
├── computed-styles.json
├── assets-manifest.json
├── capture-manifest.json
├── clone-input.json
├── clone-plan.md
├── clone-plan.json
└── parity-matrix.md
```

### Что захватывать

1. empty workspace
2. active chat
3. left sidebar expanded
4. left sidebar collapsed
5. right panel hidden
6. right panel expanded
7. right panel wide/fullscreen-like mode
8. brief review state
9. preview/result state
10. long transcript state
11. loading/thinking state

### Инструменты

Использовать:

- `$clean-room-ui-clone` для `capture`, `plan-clone`, `verify`
- `Playwright CLI Skill` для управляемых глазных прогонов
- `Playwright MCP` только как вспомогательный инструмент, если нет session instability

### Acceptance

- собран полный reference-пакет
- сгенерирован `clone-plan.md`
- готова `parity-matrix.md`

---

## Фаза 2. Backlog Harvest без исправлений

### Цель

Собрать полный backlog по всему пользовательскому сценарию и по эталонному UX/UI, не распыляясь на ранние фиксы.

### Обязательные сценарии harvest

1. gate и вход по токену
2. новый проект без дублей
3. первый содержательный ответ и автоименование проекта
4. discovery с текстом
5. discovery с файлом
6. закрытие `input_examples` при валидном обезличенном примере
7. brief review
8. две итерации brief correction
9. confirm brief
10. preview one-page
11. download главного артефакта и secondary artifacts
12. production simulation
13. refresh/resume
14. collapsible panels
15. resize + reset divider behavior
16. sticky topbar
17. scroll anchoring
18. visible thinking state

### Формат backlog item

Каждый дефект должен содержать:

1. stage
2. steps to reproduce
3. expected
4. actual
5. severity
6. evidence
7. root-cause hypothesis
8. dependency group

### Классы дефектов

- `P0 logic/state`
- `P0 happy-path break`
- `P1 result quality`
- `P1 UX parity`
- `P2 visual polish`

### Acceptance

- весь сценарий пройден до конца хотя бы один раз
- все пользовательские замечания добавлены в backlog
- каждый P0/P1 defect имеет evidence

---

## Фаза 3. P0 Fix Wave — Routing / State Machine

### Главная цель

Устранить разрыв между frontend routing и backend state machine.

### Что именно исправлять

1. Свести к одной truth-модели:
   - `status`
   - `next_action`
   - `status_snapshot.next_recommended_action`
   - `ui_projection.preferred_ui_action`
   - `ui_projection.side_panel_mode`
2. Зафиксировать явную transition matrix:
   - `incoming ui_action`
   - `session.stage`
   - `allowed transitions`
   - `frontend panel/composer state`
3. Убрать ситуации, где frontend “угадывает” режим из нескольких полей одновременно.
4. Убрать повторные вопросы, зависания и incorrect resumes.
5. Убрать ошибки привязки scroll и активного вопроса после отправки сообщения.

### Ожидаемый эффект

- ни один шаг не зависает без видимого следующего действия
- backend и frontend одинаково понимают текущее состояние
- после valid ответа пользователь всегда видит корректный следующий шаг

---

## Фаза 4. P0 Fix Wave — Result Flow

### Цель

Сделать happy path фабрики рабочим и понятным.

### Что исправлять

1. `confirm_brief` должен переводить пользователя в result-flow без тупика.
2. Главный артефакт для текущего кейса — `one_page_summary`.
3. После confirm:
   - автоматически раскрывается правый контекст результата
   - preview доступен сразу
   - download работает
4. production simulation должен запускаться из подтверждённого brief, а не быть пустой имитацией.
5. feedback на результат должен сохраняться как контекст следующей версии.

### Acceptance

- preview не пустой
- download выдаёт реальный файл
- handoff и production simulation проходят без ручного копипаста

---

## Фаза 5. P1 Fix Wave — Discovery / Brief / Architect Logic

### Цель

Сделать поведение агента-архитектора адаптивным, но логически устойчивым.

### Что исправлять

1. Архитектор не должен попугайски копировать ответы пользователя.
2. Вопросы должны быть строго server-driven и закрывать discovery-темы по одной.
3. `input_examples` должна закрываться по прикреплённому обезличенному примеру без повторных доказательств.
4. `brief revision` должна менять нужную секцию, а не дописывать текст пользователя в конец.
5. История правок brief должна сохраняться между версиями.
6. Выходной документ должен поддерживать минимум две итерации доработки формы результата.

### Acceptance

- нет повторного запроса уже закрытого вопроса
- нет append-попугайства в brief
- нет потери контекста corrections

---

## Фаза 6. P1 Fix Wave — UX/UI Parity

### Цель

Максимально приблизить структуру и поведение интерфейса к эталонному приложению по clean-room parity matrix.

### Что исправлять

1. Sticky topbar всегда виден и содержит:
   - left toggle
   - project title
   - hover-only project actions
   - right panel toggle
   - thinking state
2. Left sidebar:
   - скрывается полностью
   - остаётся компактная кнопка
   - divider работает по hover
   - double click сбрасывает ширину
3. Right panel:
   - toggle всегда сверху
   - видимое active/inactive состояние
   - можно сильно расширять
   - divider невидим в покое
4. Transcript:
   - меньше служебного мусора
   - понятное разделение “подтверждение” и “следующий вопрос”
   - главный результат визуально важнее service noise
5. Composer:
   - one-line start
   - auto-grow
   - compact attach control
   - send/stop state
   - мгновенный локальный echo
6. Thinking state:
   - всегда виден во время ответа сервера
   - не спрятан глубоко внизу
   - минимальная заметная анимация

### Acceptance

- UX/UI проходит review against parity matrix
- поведение панелей и topbar соответствует эталонным паттернам

---

## Фаза 7. Verification & Deployment

### Цель

Подтвердить, что после каждой волны продукт реально работает локально и на `demo.ainetic.tech`.

### Обязательные проверки

1. component checks
2. integration checks
3. browser e2e
4. live smoke
5. parity review screenshots
6. full manual/Playwright walkthrough

### Ключевые regression cases

1. нет duplicate question после valid answer
2. нет stuck state после file upload
3. preview открывается после confirm
4. download выдаёт non-empty artifact
5. handoff стартует из confirmed brief
6. refresh корректно восстанавливает состояние
7. sticky topbar не уезжает
8. current question остаётся видимым после отправки

---

## Фаза 8. Migration Gate: Next.js + TypeScript

### Когда поднимать вопрос о миграции

Только после закрытия P0/P1.

### Условия для positive decision

1. текущий shell остаётся слишком хрупким
2. компонентная декомпозиция критична для дальнейших задач
3. parity проще добивать в component-driven stack
4. verify cycle на текущем shell слишком дорог в сопровождении

### Если migration gate пройден

Открывается отдельный Speckit slice на UI migration.

### Если migration gate не пройден

Текущий shell остаётся основным target.

---

## Speckit-ориентированная инструкция по имплементации

### Рекомендуемый подход

Да, этот план целесообразно исполнять через Speckit workflow.

### Как именно

1. Использовать текущий slice `024-web-factory-demo-adapter` как родительский контекст для web demo.
2. Не перегружать `024` всеми новыми задачами напрямую.
3. Создать отдельный execution slice под stabilization/parity работу, если объём задач начнёт смешивать:
   - logic stabilization
   - result flow
   - clean-room parity
   - migration gate
4. В Speckit вести последовательность:
   - `specify` для уточнения execution scope
   - `plan` для decomposition по фазам
   - `tasks` для dependency-ordered implementation
   - `analyze` для cross-artifact consistency
   - `tobeads` или `taskstoissues` для трекинга

### Рекомендуемая декомпозиция задач в Speckit

1. `logic-state-sync`
2. `result-preview-download-flow`
3. `architect-discovery-brief-quality`
4. `ux-ui-parity-shell`
5. `clean-room-reference-verify`
6. `migration-gate-evaluation`

### Правило исполнения

- каждая задача должна закрываться только после verify pass
- если defect не решается с первого цикла, обязательно делать RCA и возвращать в новый fix cycle
- до конца P0/P1 не открывать framework migration implementation

---

## Критерии завершения

План считается реализованным только когда:

1. полный пользовательский цикл проходит без логических сбоев
2. пользователь может получить preview и download главного результата
3. production simulation проходит
4. UX/UI проходит parity-review по reference artifacts
5. backlog P0/P1 закрыт
6. migration gate formally пройден или отклонён отдельным verdict

---

## Связанные документы

- [specs/024-web-factory-demo-adapter/plan.md](/Users/rl/coding/moltinger/moltinger-019-asc-fabrique-prototype/specs/024-web-factory-demo-adapter/plan.md)
- [docs/plans/linear-wibbling-hellman.md](/Users/rl/coding/moltinger/moltinger-019-asc-fabrique-prototype/docs/plans/linear-wibbling-hellman.md)
- [docs/runbooks/agent-factory-web-demo.md](/Users/rl/coding/moltinger/moltinger-019-asc-fabrique-prototype/docs/runbooks/agent-factory-web-demo.md)
- [docs/concept/INDEX.md](/Users/rl/coding/moltinger/moltinger-019-asc-fabrique-prototype/docs/concept/INDEX.md)
- [docs/asc-roadmap/INDEX.md](/Users/rl/coding/moltinger/moltinger-019-asc-fabrique-prototype/docs/asc-roadmap/INDEX.md)
