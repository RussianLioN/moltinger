# RCA: backend-state confirmation loop (web adapter)

## Контекст
- Компонент: `scripts/agent-factory-web-adapter.py`
- Цепочка: `build_discovery_request -> run_discovery_runtime -> apply_brief_section_updates_deterministically`
- Симптомы:
  - explicit `confirm_brief` не всегда приводит к `confirmed`
  - review-session может уходить из `awaiting_confirmation` в discovery-вопросы при `request_status`

## 5 Why

🤖 RCA АНАЛИЗ  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ ОШИБКА: `confirm_brief` с коротким ack (`"да"`, `"ок"`) интерпретировался как correction и повышал `brief_version` вместо `confirmed`.

📝 Вопрос 1: Почему `confirm_brief` не подтверждал brief?  
→ В `build_discovery_request` ветка `ui_action == "confirm_brief"` считала любой непустой текст без `is_text_brief_confirmation(...)` запросом правки.

📝 Вопрос 2: Почему короткий ack не считался подтверждением?  
→ `is_text_brief_confirmation` опирался только на ограниченный набор фраз (`подтверждаю`, `confirm brief`, ...), без коротких ack.

📝 Вопрос 3: Почему это приводило к реальному rollback в review-loop?  
→ Для такого текста заполнялись `brief_feedback_text`/`brief_section_updates`, затем runtime создавал новую revision (`awaiting_confirmation`/`reopened`), а не `confirmed`.

📝 Вопрос 4: Почему `request_status` мог срывать review-состояние в discovery?  
→ Guard `next_missing_required_topic` проверял в основном `requirement_topics[].summary`; при неполном/устаревшем `requirement_topics` игнорировался уже заполненный `requirement_brief`.

📝 Вопрос 5: Почему guard был слишком строгим к summary-слою?  
→ Предполагалось, что `requirement_topics` всегда синхронен с brief, но это не гарантируется для старых/минимальных сохранённых payload.

🎯 КОРНЕВАЯ ПРИЧИНА:  
1) Слишком узкая интерпретация confirmation intent в `confirm_brief`.  
2) Преcondition-guard опирался на неполный источник истинности (`requirement_topics`) вместо fallback на `requirement_brief`.

📋 ДЕЙСТВИЯ:
1. Добавить безопасный детектор `has_confirmation_intent_text` (`is_text_brief_confirmation || is_short_confirmation_ack`) и использовать его во всех confirm-ветках.
2. Для `ui_action=confirm_brief` трактовать текст как correction только при явном correction intent без confirmation intent.
3. Усилить `next_missing_required_topic`: fallback на заполненные поля `requirement_brief` + `captured_answers`.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Внесённые правки
- `scripts/agent-factory-web-adapter.py`
  - добавлены:
    - `SHORT_CONFIRMATION_ACK_MARKERS`
    - `is_short_confirmation_ack(...)`
    - `has_confirmation_intent_text(...)`
  - заменены проверки confirm-intent в:
    - `request_status`/`submit_turn` confirmation branches
    - `confirm_brief` branch
    - вспомогательные guard-ветки (`likely_brief_correction_submission`, status rewrite checks)
  - обновлён `next_missing_required_topic(...)`:
    - новый fallback на поля `requirement_brief` по required topics
    - учтён `captured_answers` как дополнительный источник

## Regression tests
- Файл: `tests/integration_local/test_agent_factory_web_confirmation.sh`
- Добавлены сценарии:
  - `integration_local_agent_factory_web_confirmation_treats_short_ack_as_explicit_confirm_action`
  - `integration_local_agent_factory_web_confirmation_request_status_keeps_review_mode_when_brief_is_complete`

## Проверка
- `python3 -m py_compile scripts/agent-factory-web-adapter.py`
- `bash -n tests/integration_local/test_agent_factory_web_confirmation.sh`
- `bash tests/integration_local/test_agent_factory_web_confirmation.sh` (11/11 PASS)
