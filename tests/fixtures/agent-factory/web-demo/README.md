# Web Demo Fixtures

Эти fixtures поддерживают `024-web-factory-demo-adapter` как primary browser-accessible demo path для фабричного агента-бизнес-аналитика на `Moltis`.

## Состав

- `session-new.json` — новый browser session envelope для старта discovery из web UI
- `session-discovery-answer.json` — browser turn с очередным бизнес-ответом пользователя
- `session-awaiting-confirmation.json` — browser session в состоянии review/confirmation brief
- `session-download-ready.json` — browser session после downstream handoff с готовыми concept-pack downloads и browser delivery metadata для `/api/download`

## Правила

- Все данные только synthetic или sanitized
- `browser_session_id`, `project_key`, `brief_id` и downstream provenance должны оставаться traceable между файлами
- Fixtures описывают только adapter envelope и user-safe projections; discovery/core semantics остаются совместимыми с `022-telegram-ba-intake`
- Нельзя включать production secrets, реальные client payloads или прямые workstation-specific paths
