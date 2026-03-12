# Data Model: Moltis-Native Codex Update Advisory Flow

## Entities

### CodexAdvisoryEvent

Producer-side normalized event emitted by repo tooling and consumed by Moltis.

Fields:

- `event_id`
- `created_at`
- `source`
- `upstream_fingerprint`
- `latest_version`
- `severity`
- `summary_ru`
- `highlights_ru[]`
- `recommendation_status`
- `recommendation_payload`
- `links[]`

### MoltisAdvisoryAlert

Telegram-facing alert created from one `CodexAdvisoryEvent`.

Fields:

- `alert_id`
- `event_id`
- `chat_id`
- `message_id`
- `delivery_mode`
- `interactive_mode`
- `created_at`
- `status`

### AdvisoryConsentSession

Interactive pending state owned by Moltis.

Fields:

- `session_id`
- `alert_id`
- `chat_id`
- `callback_token`
- `expires_at`
- `status`
- `resolved_at`

Statuses:

- `pending`
- `accepted`
- `declined`
- `expired`
- `invalid`
- `duplicate`

### RecommendationEnvelope

Project-facing follow-up payload delivered after acceptance.

Fields:

- `event_id`
- `chat_id`
- `headline_ru`
- `summary_ru`
- `priority_checks[]`
- `impacted_surfaces[]`
- `raw_reference_path`

### AdvisoryInteractionRecord

Audit record that captures the full flow.

Fields:

- `event_id`
- `alert_id`
- `chat_id`
- `message_id`
- `interactive_mode`
- `decision`
- `decision_source`
- `followup_status`
- `degraded_reason`
- `created_at`
- `resolved_at`

## Relationships

- One `CodexAdvisoryEvent` can create one or more `MoltisAdvisoryAlert` records for different chats.
- One `MoltisAdvisoryAlert` has at most one active `AdvisoryConsentSession`.
- One accepted `AdvisoryConsentSession` consumes one `RecommendationEnvelope`.
- One `AdvisoryInteractionRecord` summarizes one alert lifecycle end-to-end.

## State Rules

- If interactive mode is not confirmed healthy, `MoltisAdvisoryAlert.interactive_mode = one_way_only`.
- If callback routing succeeds, the generic chat path must not also respond.
- If the same callback is repeated, the interaction record must transition to `duplicate` instead of sending another follow-up.
- If recommendations are missing, Moltis may still send the alert, but the interaction record must show why follow-up is unavailable.
