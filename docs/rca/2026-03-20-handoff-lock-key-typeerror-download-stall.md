title: "Handoff lock key TypeError переводил confirmed brief в ложный handoff_running и срывал download-ready"
severity: "P1"
category: "process"
tags: [web-demo, handoff, download, regression, runtime, ux]
status: "resolved"
root_cause: "Регрессия в helper-функции lock-key вызвала исключение в download generation; ошибка маскировалась как промежуточный handoff state"

# RCA: Handoff lock key TypeError переводил confirmed brief в ложный handoff_running и срывал download-ready

Date: 2026-03-20  
Feature: `024-web-factory-demo-adapter`  
Target: `https://demo.ainetic.tech`

## Ошибка

После `confirm_brief` UI показывал `Фабрика обрабатывает brief` вместо `Brief подтвержден`,  
а post-confirmation `request_status`/simulation-path не переходил в `download_ready`.

Фактически flow застревал между `confirmed` и `handoff_running` без доступных артефактов.

## 5 Why

1. Почему flow застревал без `download_ready`?
   - Генерация browser downloads завершалась с исключением и не возвращала артефакты.
2. Почему генерация падала?
   - В `get_session_handoff_lock()` был неверный вызов `normalize_text(..., default)`, что давало `TypeError`.
3. Почему это влияло на UX как «фабрика обрабатывает»?
   - Исключение ловилось верхним `except`, после чего runtime переводился в промежуточный статус (`handoff_running`/`request_status`) без явного завершения handoff.
4. Почему подтверждённый brief визуально терял статус `Brief подтвержден`?
   - Маппинг `user_visible_status` трактовал `next_action=start_concept_pack_handoff` как `handoff_running`, даже когда runtime оставался `confirmed`.
5. Почему дефект дошёл до регрессии?
   - Не было отдельного guard-теста на связку: `confirmed -> request_status -> download_ready` при реальном вызове handoff lock helper + строгой проверке user-visible label сразу после confirm.

## Корневая причина

Комбинация двух регрессий:
1. Неправильная сигнатура вызова helper-функции lock-key (`TypeError` в runtime path).  
2. Слишком агрессивная UX-классификация handoff по `next_action`, а не по фактическому runtime status.

## Принятые меры

1. **Немедленное исправление**
   - Исправлен lock-key helper:
     - `scripts/agent-factory-web-adapter.py`  
       `key = normalize_text(web_demo_session_id) or "anonymous-session"`
2. **Предотвращение**
   - Уточнена status-классификация:
     - `scripts/agent_factory_common.py`
     - `start_concept_pack_handoff` исключён из автоматического перевода в `handoff_running` для user-visible/session-runtime mapping.
3. **Валидация**
   - Прогнаны регрессионные проверки:
     - `tests/integration_local/test_agent_factory_web_confirmation.sh` (4/4 PASS)
     - `tests/component/test_agent_factory_web_brief.sh` (3/3 PASS)
     - `python3 -m py_compile scripts/agent-factory-web-adapter.py scripts/agent_factory_common.py` (PASS)

## Профилактика

1. Добавлять integration-assert на label сразу после `confirm_brief` (`Brief подтвержден`), до первого `request_status`.
2. Для post-confirmation ветки держать отдельный тест на инвариант `simulation submit_turn -> status=download_ready`.
3. При runtime exception в delivery path логировать первичную причину как отдельный audit marker, а не только как косвенный pending-state.

## Уроки

1. Helper-функции в критическом пути handoff/download должны покрываться тестом на фактический runtime-вызов, а не только на косвенный UI-результат.
2. Нельзя приравнивать `next_action=start_concept_pack_handoff` к `handoff_running`, если фактический runtime status ещё `confirmed`.
3. Для UX-инвариантов post-confirmation нужен обязательный regression-тест целой цепочки (`confirm -> status refresh -> simulation -> downloads`), иначе дефекты маскируются «ожиданием обработки».
