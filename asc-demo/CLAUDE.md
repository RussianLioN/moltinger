# CLAUDE.md — ASC AI Fabrique Demo Prototype

## Проект
Прототип AI-приложения "ASC AI Fabrique Demo" — демонстрация пользовательской истории фабрики цифровых сотрудников. Web-приложение, в котором агент-архитектор Moltis проводит пользователя через discovery, формирует brief и генерирует one-page summary для кредитного комитета.

## Стек
- **Frontend**: Vanilla HTML/CSS/JS (уже готов, менять минимально)
- **Backend**: Node.js + Express
- **AI**: OpenAI-compatible API (Fireworks `glm-5` по умолчанию)
- **Хранение**: In-memory (сессии, артефакты)
- **Деплой**: Локальный dev-сервер (порт 3000)

## Структура проекта
```
asc-demo/                        # Корень Node.js проекта (рабочая директория)
├── CLAUDE.md                    # Этот файл
├── package.json
├── .env                         # OPENAI_API_KEY (не коммитить)
├── server.js                    # Express-сервер, роуты
├── src/
│   ├── sessions.js              # In-memory хранилище сессий
│   ├── discovery.js             # LLM-powered discovery flow
│   ├── brief.js                 # Генерация brief из диалога
│   ├── summary-generator.js     # 4-секционный one-page summary
│   ├── prompts/
│   │   ├── architect-system.md  # System prompt агента-архитектора
│   │   ├── client-info.md       # Промпт: ИНФОРМАЦИЯ ПО КЛИЕНТУ
│   │   ├── deal-info.md         # Промпт: ИНФОРМАЦИЯ ПО СДЕЛКЕ
│   │   ├── pricing-info.md      # Промпт: ЦЕНООБРАЗОВАНИЕ И ДОХОДНОСТЬ
│   │   └── cooperation-info.md  # Промпт: АНАЛИЗ СОТРУДНИЧЕСТВА
│   └── demo-data/
│       └── boku-do-manzh.json   # Демо-данные клиента "Боку до манж"
├── public/                      # Статика (СУЩЕСТВУЮЩИЙ UI, НЕ МЕНЯТЬ БЕЗ НЕОБХОДИМОСТИ)
│   ├── index.html               #  ← источник: ../web/agent-factory-demo/index.html
│   ├── app.css                  #  ← источник: ../web/agent-factory-demo/app.css
│   └── app.js                   #  ← источник: ../web/agent-factory-demo/app.js
└── artifacts/                   # Сгенерированные артефакты (runtime)
```

## Пути к исходным артефактам (относительно корня репозитория)
```
web/agent-factory-demo/          # ← источник для public/ (скопировать при инициализации)
asc-demo/demo-client-data.csv    # Демо-данные CSV (уже в проекте)
asc-demo/generation-prompts.md   # 4 промпта для секций (уже в проекте)
docs/concept/asc-ai-fabrique-2-0-user-story-q-and-a.md  # Q&A-спека
docs/concept/specs/001-approval-level-user-story-bpmn/spec.md          # Feature spec
docs/concept/specs/001-approval-level-user-story-bpmn/factory-e2e.bpmn # BPMN E2E
```

## Критические правила

### 1. Формат ответа API
Бэкенд MUST возвращать ответы в ТОЧНО ТОМ ЖЕ формате, что и функция `mockAdapterTurn()` в `public/app.js` (строки 1922–2050). Структура ответа:
```json
{
  "status": "awaiting_user_reply | awaiting_confirmation | confirmed",
  "next_action": "continue_discovery | await_for_confirmation | start_concept_pack_handoff",
  "next_topic": "",
  "next_question": "...",
  "access_gate": { "granted": true, "reason": "" },
  "web_demo_session": { ... },
  "browser_project_pointer": { ... },
  "status_snapshot": { ... },
  "reply_cards": [ ... ],
  "download_artifacts": [ ... ],
  "uploaded_files": [ ... ],
  "discovery_runtime_state": { ... },
  "ui_projection": { ... }
}
```

### 2. Discovery flow
7 discovery-топиков (из MOCK_DISCOVERY_TOPICS в app.js):
1. `problem` — бизнес-проблема
2. `target_users` — пользователи/выгодоприобретатели
3. `current_workflow` — текущий процесс и потери
4. `input_examples` — входные данные
5. `expected_outputs` — ожидаемый результат
6. `branching_rules` — ветвления и бизнес-правила
7. `success_metrics` — метрики успеха

LLM определяет покрытие по содержимому ответов пользователя. Когда все топики покрыты → переход к brief.

### 3. One-page summary
4 секции генерируются параллельно, каждая своим промптом:
- ИНФОРМАЦИЯ ПО КЛИЕНТУ
- ИНФОРМАЦИЯ ПО СДЕЛКЕ
- ЦЕНООБРАЗОВАНИЕ И ДОХОДНОСТЬ
- АНАЛИЗ СОТРУДНИЧЕСТВА И ВКЛАДА

Входные данные — структурированный CSV/JSON клиента "Боку до манж".

### 4. UI контракт
Фронтенд отправляет на POST `/api/turn`:
```json
{
  "web_conversation_envelope": {
    "ui_action": "submit_turn | confirm_brief | request_brief_correction | ...",
    "user_text": "текст пользователя",
    "request_id": "browser-project-turn-0001",
    "session_id": "web-demo-session-project",
    "project_key": "factory-...",
    "active_project_key": "...",
    "selection_mode": "continue_active"
  },
  "discovery_runtime_state": { ... },
  "uploaded_files": [ ... ]
}
```

### 5. Access token
Простая проверка: token === "demo-access-token" → granted: true.

## Команды
```bash
npm install          # Установка зависимостей
npm run dev          # Запуск dev-сервера (nodemon)
npm start            # Запуск production
```

## Переменные окружения (.env)
```
OPENAI_API_KEY=fw_...
OPENAI_BASE_URL=https://api.fireworks.ai/inference/v1
MODEL_NAME=accounts/fireworks/models/glm-5
DEMO_ACCESS_TOKEN=demo-access-token
DEMO_DOMAIN=demo.ainetic.tech
DEMO_PUBLIC_BASE_URL=https://demo.ainetic.tech
PORT=3000
```

## Контекст предметной области
Система предназначена для финтех-среды (Сбербанк). Агент-архитектор Moltis — это AI-агент, который:
- Принимает описание задачи автоматизации от сотрудника
- Проводит structured discovery (интервью)
- Формирует brief с требованиями
- Передаёт brief "в фабрику" для генерации артефактов
- В данном прототипе: генерирует one-page summary по клиенту

## Стиль кода
- ESM modules (import/export)
- async/await
- Без TypeScript (прототип за 1 день)
- Комментарии на русском для бизнес-логики, на английском для технической
- Минимум абстракций, максимум читаемости
