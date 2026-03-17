# Промпты для Claude Code — пошаговое выполнение спринта

Копируй промпты в Claude Code последовательно. Каждый промпт — одна задача.

---

## ПРОМПТ 0 — Инициализация проекта

```
Прочитай CLAUDE.md в корне проекта. Затем выполни:

1. Создай package.json:
   - name: "asc-ai-fabrique-demo"
   - type: "module"
   - dependencies: express, @anthropic-ai/sdk, dotenv, cors, uuid
   - devDependencies: nodemon
   - scripts: { "dev": "nodemon server.js", "start": "node server.js" }

2. Создай .env с шаблоном:
   ANTHROPIC_API_KEY=sk-ant-PLACEHOLDER
   PORT=3000
   DEFAULT_MODEL=claude-sonnet-4-20250514

3. Создай структуру папок:
   src/prompts/
   src/demo-data/
   public/
   artifacts/

4. Скопируй index.html, app.css, app.js в public/

5. npm install

Не создавай server.js пока — это следующая задача.
```

---

## ПРОМПТ 1 — Бэкенд-сервер (Express)

```
Создай server.js — Express-сервер. Требования:

1. ESM imports (import express from 'express')
2. Загрузка .env через dotenv/config
3. Middleware: express.json({limit:'2mb'}), express.static('public'), cors()
4. Роуты:
   - GET / → public/index.html (через static)
   - POST /api/turn → пока вызывает handleTurn(req.body) из src/router.js
   - GET /api/session → вызывает getSession(req.query.session_id) из src/sessions.js
5. Порт из process.env.PORT || 3000

Создай src/sessions.js:
- Map<sessionId, sessionData> в памяти
- getSession(sessionId) → возвращает данные сессии или создаёт новую
- updateSession(sessionId, data) → обновляет
- Структура сессии:
  { sessionId, projectKey, status, discoveryHistory: [], briefData: null, artifacts: [], createdAt, updatedAt }

Создай src/router.js:
- export async function handleTurn(payload) — пока делает mock-ответ
- Парсит payload.web_conversation_envelope (ui_action, user_text, session_id)
- КРИТИЧЕСКИ ВАЖНО: формат ответа ТОЧНО как mockAdapterTurn() в public/app.js (строки 2001-2050)
- Пока верни hardcoded mock-ответ со статусом "awaiting_user_reply" и одним reply_card

Проверь: npm run dev → открой http://localhost:3000 → UI должен загрузиться и gate screen работать
```

---

## ПРОМПТ 2 — LLM-powered Discovery

```
Создай src/discovery.js — модуль discovery через Anthropic API. Требования:

1. import Anthropic from '@anthropic-ai/sdk'
2. Инициализация клиента: new Anthropic()

3. Список discovery-топиков (СОХРАНИ ТОЧНО как в app.js MOCK_DISCOVERY_TOPICS):
   - problem, target_users, current_workflow, input_examples, expected_outputs, branching_rules, success_metrics
   - У каждого: id, question, why, signals[]

4. Функция analyzeCoverage(discoveryHistory):
   - Принимает массив {role, text} из истории диалога
   - Вызывает LLM с system prompt:
     "Ты — аналитик покрытия discovery. Дан диалог между агентом и пользователем. Определи, какие из 7 топиков уже раскрыты в ответах пользователя. Верни JSON: { covered: ["problem", "target_users", ...], missing: ["branching_rules", ...] }"
   - Возвращает { covered: Set, missing: Topic[] }

5. Функция generateNextQuestion(discoveryHistory, coveredTopics, missingTopics):
   - Вызывает LLM с system prompt агента-архитектора Moltis (из src/prompts/architect-system.md)
   - В контексте: история диалога + что уже покрыто + что не покрыто
   - LLM формулирует естественный следующий вопрос
   - Возвращает { question, topic, whyAskingNow }

6. Функция isDiscoveryComplete(covered):
   - Возвращает true если covered.size >= 5 (не требуем все 7 для демо, достаточно 5)

Создай src/prompts/architect-system.md:
```
Ты — агент-архитектор Moltis в системе ASC AI Fabrique.
Твоя задача — провести structured discovery для сбора требований к автоматизации бизнес-процесса.

Правила:
- Общайся на русском языке
- Задавай по одному конкретному вопросу за раз
- Формулируй вопросы просто и понятно для бизнес-пользователя
- Не используй технический жаргон без необходимости
- Если ответ пользователя слишком общий — мягко попроси уточнить
- Связывай следующий вопрос с предыдущим ответом, чтобы диалог был естественным
- Признавай полезность ответа пользователя перед следующим вопросом
```

Обнови src/router.js:
- При ui_action === "submit_turn" и status === "discovery":
  1. Добавить сообщение пользователя в discoveryHistory сессии
  2. Вызвать analyzeCoverage
  3. Если discovery complete → перейти к brief (status = "awaiting_confirmation")
  4. Иначе → вызвать generateNextQuestion
  5. Собрать ответ в формате mockAdapterTurn
```

---

## ПРОМПТ 3 — Brief генерация

```
Создай src/brief.js — модуль генерации brief. Требования:

1. Функция generateBrief(discoveryHistory):
   - Вызывает LLM с system prompt:
     "На основе следующего discovery-диалога сформируй структурированный brief проекта автоматизации. Формат:
     
     **Проблема**: ...
     **Целевые пользователи**: ...
     **Текущий процесс**: ...
     **Входные данные**: ...
     **Ожидаемый результат**: ...
     **Бизнес-правила**: ...
     **Метрики успеха**: ...
     
     Будь конкретен. Используй формулировки пользователя."
   - Возвращает { briefId, version, content, generatedAt }

2. Функция reviseBrief(currentBrief, correctionText):
   - Принимает текущий brief и текст правки пользователя
   - Вызывает LLM для обновления brief с учётом правок
   - Инкрементирует version (v1 → v2)

Обнови src/router.js:
- При переходе в "awaiting_confirmation":
  1. Вызвать generateBrief(session.discoveryHistory)
  2. Сохранить brief в сессию
  3. Вернуть reply_cards с brief_summary_section и confirmation_prompt
  4. side_panel_mode = "brief_review"

- При ui_action === "confirm_brief":
  1. Статус → "generating" (промежуточный)
  2. Запустить генерацию summary (Задача 4)
  3. После завершения → status = "confirmed", download_readiness = "ready"

- При ui_action === "request_brief_correction":
  1. Вызвать reviseBrief с текстом пользователя
  2. Остаться в "awaiting_confirmation" с обновлённым brief
```

---

## ПРОМПТ 4 — One-page Summary генератор

```
Создай src/summary-generator.js — модуль генерации 4-секционного one-page summary.

1. Загрузи демо-данные клиента из src/demo-data/boku-do-manzh.json

2. Создай src/demo-data/boku-do-manzh.json — конвертируй CSV-данные клиента "Боку до манж" в JSON:
   {
     "client": {
       "name": "ООО \"Боку до манж\"",
       "inn": "5503815527",
       "segment": "Средние",
       "okk": "20.23.4",
       ... (все поля из секции "Данные по клиенту")
     },
     "deal": {
       "product": "Оборотный кредит",
       "mode": "ВКЛ",
       "amount": "300 000 000 руб.",
       ... (все поля из секции "Данные по сделке")
     },
     "pricing": { ... },
     "cooperation": { ... },
     "potential": { ... }
   }

3. Создай 4 файла промптов в src/prompts/ — СКОПИРУЙ ПРОМПТЫ ДОСЛОВНО из предоставленного документа с промптами:
   - src/prompts/client-info.md → секция "Данные по клиенту" (Роль + Задача + Критические инструкции)
   - src/prompts/deal-info.md → секция "Данные по сделке"
   - src/prompts/pricing-info.md → секция "Данные по цене"
   - src/prompts/cooperation-info.md → секция "Данные по сотрудничеству и потенциалу"

4. Функция generateOnePage(clientData):
   - Запускает 4 LLM-вызова ПАРАЛЛЕЛЬНО (Promise.all)
   - Каждый вызов: system = промпт из файла, user = JSON данных соответствующей секции
   - Собирает результаты в единый документ
   - Сохраняет как Markdown файл в artifacts/
   - Возвращает { artifactId, fileName, content, generatedAt }

5. Итоговый документ:
   # One-Page Summary: ООО "Боку до манж"
   *Подготовлено: [дата]*
   *Агент-архитектор: Moltis / ASC AI Fabrique*
   
   [ИНФОРМАЦИЯ ПО КЛИЕНТУ — результат LLM вызова 1]
   
   [ИНФОРМАЦИЯ ПО СДЕЛКЕ — результат LLM вызова 2]
   
   [ЦЕНООБРАЗОВАНИЕ И ДОХОДНОСТЬ — результат LLM вызова 3]
   
   [АНАЛИЗ СОТРУДНИЧЕСТВА И ВКЛАДА — результат LLM вызова 4]
```

---

## ПРОМПТ 5 — Сквозной pipeline

```
Интегрируй все модули в единый flow в src/router.js:

1. Полный маршрут сессии:
   gate_pending → discovery → awaiting_confirmation → generating → confirmed (downloads_ready)

2. handleTurn(payload) логика:

   switch(session.status) {
     case "gate_pending":
       → проверить token → если ОК, status = "discovery", вернуть первый вопрос
     
     case "discovery":
       → добавить в историю → analyzeCoverage → 
         если complete: generateBrief → status = "awaiting_confirmation"
         если нет: generateNextQuestion → вернуть вопрос
     
     case "awaiting_confirmation":
       switch(ui_action) {
         "confirm_brief": → status = "generating" → запустить generateOnePage → status = "confirmed"
         "request_brief_correction": → reviseBrief → остаться в awaiting_confirmation
         "reopen_brief": → status = "discovery" → вернуть следующий вопрос
       }
     
     case "confirmed":
       → вернуть download_artifacts с готовым файлом
   }

3. Добавь эндпоинт GET /api/artifact/:id:
   - Читает файл из artifacts/
   - Отдаёт с Content-Disposition: attachment

4. Модифицируй public/app.js МИНИМАЛЬНО:
   - В функции, которая обрабатывает download_artifact action, добавь:
     window.open('/api/artifact/' + artifactId, '_blank')
   - Это единственное изменение фронтенда

Проверь полный flow: gate → 5 вопросов → brief → confirm → summary ready → download
```

---

## ПРОМПТ 6 — Демо-данные и happy-path

```
Прогони полный happy-path сценарий:

1. Запусти сервер: npm run dev
2. Открой http://localhost:3000
3. Введи token: demo-access-token
4. Кликни пример "one-page summary по клиенту"
5. Ответь на вопросы агента:
   - "Нужно автоматизировать подготовку заключения клиентского подразделения для кредитного комитета"
   - "Основные пользователи — клиентские менеджеры среднего бизнеса Сбербанка"
   - "Сейчас менеджер вручную копирует данные из 5 систем в Word-шаблон, это занимает 2-3 часа"
   - "На вход подаются структурированные данные по клиенту, сделке, цене и сотрудничеству в CSV формате"
   - "На выходе — one-page summary с 4 секциями: клиент, сделка, цена, сотрудничество"
6. Проверь brief → подтверди
7. Дождись генерации → скачай артефакт

Если какой-то шаг ломается — поправь и продолжи.
Зафиксируй баги и workarounds.
```

---

## ПРОМПТ 7 — Артефакты и side panel

```
Убедись, что side panel корректно работает:

1. При status "awaiting_confirmation":
   - side_panel_mode = "brief_review"
   - panel-cards содержат brief с кнопками "Подтвердить" и "Внести правки"

2. При status "confirmed":
   - side_panel_mode = "downloads"
   - artifact-section видим
   - artifact-cards содержат:
     - { artifact_kind: "one_page_summary", download_name: "one-page-summary.md", download_status: "ready" }

3. Кнопка "Скачать" в artifact-card:
   - Открывает /api/artifact/{id} в новой вкладке
   - Файл скачивается с правильным именем

4. Кнопка "Brief и файлы" в workspace-topbar:
   - Показывается, когда есть панельный контент
   - Тоглит side panel

Если нужны минимальные правки app.js — делай, но только то, что необходимо для скачивания.
```

---

## ПРОМПТ 8 — Error states

```
Добавь минимальную обработку ошибок:

1. В discovery.js и summary-generator.js оберни LLM-вызовы в try/catch:
   - При ошибке API → вернуть fallback-ответ с текстом ошибки
   - При таймауте → "Агент-архитектор обрабатывает запрос. Подожди немного..."

2. В router.js:
   - Невалидный payload → 400 с понятным сообщением
   - Сессия не найдена → создать новую
   - Ошибка LLM → mock-fallback с пометкой "Локальный mock fallback"

3. В server.js:
   - Глобальный error handler
   - Логирование ошибок в консоль

4. Таймаут для LLM-вызовов: 30 секунд для discovery, 60 секунд для summary generation
```

---

## ПРОМПТ 9 — Финальная проверка

```
Выполни финальную проверку всего прототипа:

1. Перезапусти сервер чисто (rm artifacts/*, очисти localStorage в браузере)
2. Пройди полный сценарий от начала до конца
3. Проверь:
   - [ ] Gate screen работает с token "demo-access-token"
   - [ ] Пример-чип запускает discovery
   - [ ] Агент задаёт осмысленные вопросы
   - [ ] После 5+ ответов — переход к brief
   - [ ] Brief отображается в side panel
   - [ ] Подтверждение brief запускает генерацию
   - [ ] Артефакт появляется в side panel
   - [ ] Скачивание работает
   - [ ] Документ содержит 4 секции с корректными данными
   - [ ] Нет JS-ошибок в console

4. Если всё работает — зафиксируй:
   git init && git add -A && git commit -m "MVP0 prototype: one-day sprint complete"
```

---

## Чеклист готовности к демонстрации

- [ ] Сервер запускается одной командой `npm run dev`
- [ ] UI загружается без ошибок
- [ ] Gate → Discovery → Brief → Summary — полный путь работает
- [ ] Summary содержит реальные данные клиента "Боку до манж"
- [ ] Документ скачивается как markdown-файл
- [ ] Нет зависимостей от внешних сервисов кроме Anthropic API
- [ ] .env с API ключом — единственная настройка
