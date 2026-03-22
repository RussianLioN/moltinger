# Runbook: Agent Factory Telegram Adapter

## Цель

`scripts/agent-factory-telegram-adapter.py` — тонкий transport/routing слой для Telegram поверх discovery runtime (`scripts/agent-factory-discovery.py`).

Адаптер:

1. нормализует входящий Telegram update в `TelegramUpdateEnvelope`
2. определяет intent (`start_project`, `answer_discovery_question`, `request_status`, и т.д.)
3. поддерживает pointer и session state
4. делегирует discovery-ход в channel-neutral runtime
5. возвращает user-facing `reply_payloads` без утечек внутренних путей
6. после explicit brief confirm запускает downstream handoff (`intake -> artifacts`) и формирует delivery payloads

## Точки входа

```bash
python3 scripts/agent-factory-telegram-adapter.py handle-update \
  --source tests/fixtures/agent-factory/telegram/update-new-project.json \
  --state-root data/agent-factory/telegram \
  --output /tmp/telegram-adapter-out.json
```

Параметры:

- `--source` — JSON update payload
- `--output` — путь для JSON ответа (если не указан, выводится в stdout)
- `--state-root` — корень состояния адаптера (по умолчанию `data/agent-factory/telegram`)
- `--transport-mode` — `webhook | synthetic_fixture | live_probe`

## Хранилище состояния

Корень: `data/agent-factory/telegram/`

- `sessions/` — текущие snapshots сессий (`tg-session-*.json`)
- `history/` — JSONL audit trail по сессии (`tg-session-*.jsonl`)
- `deliveries/` — зарезервировано под delivery артефактов следующими фазами
- `deliveries/` — хранилище concept-pack delivery по сессии (`delivery-index.json`, `concept-pack.json`, `downloads/`)

Ключевые объекты в `sessions/*.json`:

- `telegram_adapter_session`
- `active_project_pointer`
- `project_registry` (active key + project snapshots для resume/switch)
- `discovery_state`
- `last_runtime_response`
- `status_snapshot`
- `last_intent`

## Routing contract

Поддержанные update-модели на foundation этапе:

- `message.text`
- `message.caption`
- `callback_query.data`

Неподдержанные update типы получают в ответ безопасный fallback (`reply_kind=error_message`) без silent drop.

### Поддержанные intent на этапе live discovery

- `start_project` — старт нового проекта (`/start`, `/new`, `новый проект`, либо первое свободное сообщение).
- `answer_discovery_question` — свободный ответ пользователя в активной discovery-сессии.
- `request_status` — быстрый статус (`/status`, `статус`).
- `list_projects` — список известных проектов и текущий активный (`/projects`).
- `select_project` — переключение активного проекта (`/project <project_key>`).
- `request_help` — краткая подсказка по диалогу (`/help`, `помощь`).
- `confirm_brief` — явное подтверждение brief (`подтверждаю`, `confirm brief`).
- `reopen_brief` — запрос на переоткрытие/правку brief (`переоткрыть`, `исправить`, `правка`).

## UX правила live discovery

- После каждого пользовательского сообщения адаптер возвращает:
  - `status_update` с коротким статусом и следующим действием.
  - `discovery_question` или `clarification_prompt`, если нужно продолжить сбор контекста.
- Для активной сессии free-form сообщение всегда трактуется как ответ на текущий discovery topic.
- Ответы пользователя и статус-снимок сессии сохраняются в `sessions/` и `history/`, чтобы `/status` не мутировал состояние.

## Brief review / confirm / reopen

- Когда runtime возвращает `status=awaiting_confirmation` или `status=reopened`, адаптер:
  - отправляет `brief_summary` чанками (Telegram-readable формат),
  - отправляет `confirmation_prompt` с инструкцией подтвердить brief или внести правку.
- Явные фразы подтверждения (`подтверждаю`, `confirm brief`) превращаются в `confirmation_reply`.
- Сообщение с маркерами правки/переоткрытия (`исправь`, `правка`, `переоткрыть`) превращается в `brief_feedback_text` + `brief_section_updates`, чтобы discovery runtime выпустил новую версию brief.
- После подтверждения текущей версии адаптер переводит поток в downstream handoff (`run_factory_intake`).

## Downstream handoff и delivery

- После explicit `confirm_brief` адаптер автоматически:
  1. прогоняет ready handoff replay в discovery (если текущий turn дал только `status=confirmed`);
  2. запускает `scripts/agent-factory-intake.py`;
  3. запускает `scripts/agent-factory-artifacts.py generate`;
  4. пишет delivery index в `data/agent-factory/telegram/deliveries/<session-id>/delivery-index.json`;
  5. возвращает `artifact_delivery` payload в Telegram.
- Для повторных `/status` adapter переиспользует сохраненный delivery index и не пересобирает артефакты без необходимости.
- Режим отправки документов:
  - `MOLTIS_TELEGRAM_DELIVERY_MODE=dry_run` (по умолчанию) — только dry-run вызовы delivery helper.
  - `MOLTIS_TELEGRAM_DELIVERY_MODE=live` — фактический sendDocument через Bot API helper.

## Resume / Reopen / Project selection

- Адаптер хранит per-project снапшоты в `project_registry.projects[]` внутри `sessions/<tg-session>.json`.
- `/projects` возвращает список проектов с user-facing статусом и brief version.
- `/project <project_key>` переключает активный pointer, поднимает сохраненный runtime и продолжает discovery с нужной точки без потери истории.
- `/status` всегда показывает состояние активного проекта из `project_registry.active_project_key`.
- Для `brief.status=reopened` в Telegram-статусе показывается отдельная формулировка про повторное подтверждение.

## Safety правила

- Reply payloads всегда проходят текстовую санитизацию от внутренних путей (`/Users/*`, `/opt/*`, `.beads/*`, `data/agent-factory/*`).
- User-facing тексты не должны содержать stack traces, repo paths, секреты.
- Все fixture и тестовые данные — только синтетические/обезличенные.

## Локальные проверки

```bash
bash -n tests/component/test_agent_factory_telegram_routing.sh
bash -n tests/component/test_agent_factory_telegram_intents.sh
bash -n tests/component/test_agent_factory_telegram_brief.sh
bash -n tests/component/test_agent_factory_telegram_delivery.sh
bash -n tests/integration_local/test_agent_factory_telegram_flow.sh
bash -n tests/integration_local/test_agent_factory_telegram_discovery.sh
bash -n tests/integration_local/test_agent_factory_telegram_confirmation.sh
bash -n tests/integration_local/test_agent_factory_telegram_handoff.sh
bash -n tests/integration_local/test_agent_factory_telegram_resume.sh
./tests/run.sh --lane component --filter agent_factory_telegram_routing --json
./tests/run.sh --lane component --filter agent_factory_telegram_intents --json
./tests/run.sh --lane component --filter agent_factory_telegram_brief --json
./tests/run.sh --lane component --filter agent_factory_telegram_delivery --json
./tests/run.sh --lane integration_local --filter agent_factory_telegram_flow --json
./tests/run.sh --lane integration_local --filter agent_factory_telegram_discovery --json
./tests/run.sh --lane integration_local --filter agent_factory_telegram_confirmation --json
./tests/run.sh --lane integration_local --filter agent_factory_telegram_handoff --json
./tests/run.sh --lane integration_local --filter agent_factory_telegram_resume --json
```
