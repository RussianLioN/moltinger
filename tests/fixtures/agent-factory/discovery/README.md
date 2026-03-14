# Discovery Fixtures

Эти fixtures поддерживают `022-telegram-ba-intake` как legacy feature id и фактический scope factory business-analyst intake:

- guided discovery interview
- draft/confirmed requirements brief
- clarification loop
- downstream handoff в существующий concept-pack pipeline

## Состав

- `session-new.json` — стартовая discovery-сессия после сырой идеи пользователя
- `session-awaiting-clarification.json` — частично заполненная сессия с открытыми вопросами и sanitized examples
- `brief-awaiting-confirmation.json` — draft brief, готовый к пользовательской проверке и подтверждению
- `brief-confirmed-handoff.json` — confirmed brief с snapshot и handoff record для downstream pipeline

## Правила

- Все примеры synthetic или sanitized
- Один и тот же `project_key` и связанный `brief_id` должны оставаться traceable между файлами
- Discovery fixtures не должны содержать production secrets или реальные клиентские данные
