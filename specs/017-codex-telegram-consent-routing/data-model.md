# Data Model: Codex Telegram Consent Routing

## ConsentRequest

Represents one active interactive follow-up opened by a Codex watcher alert.

| Field | Type | Description |
| --- | --- | --- |
| `request_id` | string | Stable unique identifier for one consent interaction |
| `source` | enum | `codex_upstream_watcher` |
| `fingerprint` | string | Upstream fingerprint that triggered the alert |
| `chat_id` | string | Telegram chat id allowed to answer |
| `question_message_id` | integer | Telegram message id of the alert/question |
| `created_at` | string | ISO timestamp when the request was opened |
| `expires_at` | string | ISO timestamp after which the request is invalid |
| `status` | enum | `pending`, `accepted`, `declined`, `expired`, `delivered`, `failed` |
| `action_token` | string | Compact token embedded into callback data or fallback command |
| `question_text` | string | Human-facing Russian question shown to the user |
| `delivery_mode` | enum | `command_keyboard`, `command_fallback`, `one_way_only` |

## RecommendationPayload

Represents the project-facing guidance prepared by the watcher/advisor layer.

| Field | Type | Description |
| --- | --- | --- |
| `summary` | string | Short Russian explanation of why the project should care |
| `items` | array | Ordered recommendation items |

### RecommendationItem

| Field | Type | Description |
| --- | --- | --- |
| `title` | string | Recommendation title |
| `rationale` | string | Why this item matters |
| `impacted_paths` | array[string] | Repository paths likely to be affected |
| `next_steps` | array[string] | Practical next steps |

## ConsentDecision

Represents one resolved user action.

| Field | Type | Description |
| --- | --- | --- |
| `request_id` | string | Matched consent request id |
| `decision` | enum | `accept`, `decline`, `expired`, `invalid`, `duplicate` |
| `resolved_at` | string | ISO timestamp |
| `resolved_via` | enum | `callback_query`, `command_fallback`, `command_alias`, `operator_override` |
| `telegram_actor_id` | string | Telegram user/chat identity that triggered the decision |
| `raw_input` | string | Original callback payload or command text |
| `note` | string | Optional explanatory note for duplicate/invalid cases |

## ConsentStoreRecord

Top-level authoritative record shared between the main ingress and downstream follow-up delivery.

| Field | Type | Description |
| --- | --- | --- |
| `request` | ConsentRequest | Pending or resolved consent request |
| `recommendations` | RecommendationPayload | Prepared recommendation payload |
| `decision` | ConsentDecision or null | Latest resolved decision |
| `delivery` | ConsentDeliveryResult | Follow-up delivery outcome |
| `audit_notes` | array[string] | Compact operational notes |

## ConsentDeliveryResult

Tracks whether the second recommendation message was sent.

| Field | Type | Description |
| --- | --- | --- |
| `status` | enum | `not_sent`, `sent`, `suppressed`, `retry`, `failed` |
| `message_id` | integer or null | Telegram message id of the follow-up |
| `sent_at` | string | ISO timestamp |
| `error` | string | Delivery error if any |

## State Transitions

1. `pending` -> `accepted`
   Trigger: valid explicit user consent action.
2. `pending` -> `declined`
   Trigger: valid explicit decline action.
3. `pending` -> `expired`
   Trigger: action arrived after `expires_at` or sweeper closed the request.
4. `accepted` -> `delivered`
   Trigger: recommendations sent successfully.
5. `accepted` -> `failed` / `retry`
   Trigger: recommendation delivery failed.
6. Any resolved state + repeated identical action
   Result: `duplicate`, no duplicate send.

## Operational Notes

- Short chat-friendly commands such as `/codex_da` and `/codex_net` can resolve through chat-scoped lookup when exactly one pending request exists.
- `request_id` and `action_token` should be short enough for Telegram callback data constraints and rare fallback cases.
- The authoritative store should be append-safe and audit-friendly.
- Watcher-local pending consent is no longer sufficient as the only source of truth in production.
