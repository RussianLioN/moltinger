# Agent Factory Fixtures

Эти fixtures поддерживают foundational и последующие тесты для `020-agent-factory-prototype`.

## Состав

- `concept-intake.json` — пример intake-запроса и ожидаемой концептуальной записи
- `defense-feedback.json` — пример review-цикла с `rework_requested`
- `swarm-evidence.json` — пример evidence-пакета для swarm run и playground package

## Правила

- Все данные только синтетические
- Идентификаторы и версии должны оставаться traceable между файлами
- Fixtures можно переиспользовать в component и integration_local тестах

