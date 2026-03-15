# Data Model: Codex Update Delivery UX

## Entities

### AdvisorSnapshot

Represents the advisor result consumed by the delivery layer.

| Field | Type | Description |
|-------|------|-------------|
| `recommendation` | enum | `upgrade-now`, `upgrade-later`, `ignore`, or `investigate` |
| `notification_status` | enum | Advisor freshness signal such as `notify`, `suppressed`, `none`, or `investigate` |
| `project_change_suggestions` | object[] | Repository-specific follow-up suggestions from the advisor |
| `implementation_brief` | object | Grouped summary and next steps from the advisor |

### DeliveryFingerprint

Represents the actionable state being delivered across surfaces.

| Field | Type | Description |
|-------|------|-------------|
| `value` | string | Stable digest for the current advisor state |
| `advisor_checked_at` | string | Timestamp of the advisor result used to derive the fingerprint |

### DeliverySurfaceState

Represents delivery memory for one surface.

| Field | Type | Description |
|-------|------|-------------|
| `surface` | enum | `on-demand`, `launcher`, or `telegram` |
| `last_delivered_fingerprint` | string | Last fingerprint successfully delivered to this surface |
| `last_delivered_at` | string | Timestamp of the successful delivery |
| `last_status` | enum | `delivered`, `suppressed`, `failed`, or `unknown` |
| `notes` | string[] | Surface-specific audit trail |

### DeliveryDecision

Represents the current outcome for one delivery surface.

| Field | Type | Description |
|-------|------|-------------|
| `surface` | enum | `on-demand`, `launcher`, or `telegram` |
| `status` | enum | `deliver`, `suppress`, `retry`, or `investigate` |
| `reason` | string | Plain-language explanation |
| `changed` | boolean | Whether this surface sees the state as fresh |

### TelegramDeliveryTarget

Represents Telegram delivery configuration.

| Field | Type | Description |
|-------|------|-------------|
| `chat_id` | string | Destination chat or user id |
| `enabled` | boolean | Whether Telegram delivery is enabled |
| `silent` | boolean | Whether Telegram delivery should use silent mode |
| `env_file` | string | Optional env file used to resolve the bot token |

### DeliveryRunReport

Represents the top-level delivery output.

| Field | Type | Description |
|-------|------|-------------|
| `checked_at` | string | Delivery run timestamp |
| `advisor_snapshot` | AdvisorSnapshot | Advisor result consumed by delivery |
| `fingerprint` | string | Shared actionable fingerprint |
| `surface_decisions` | DeliveryDecision[] | Per-surface decisions for this run |
| `surface_state` | DeliverySurfaceState[] | Current persisted state summary |
| `telegram_target` | TelegramDeliveryTarget | Telegram config summary if enabled |
| `notes` | string[] | Overall delivery notes and failures |

## Relationships

- `DeliveryRunReport` owns one `AdvisorSnapshot` and one shared fingerprint.
- `DeliveryRunReport` contains zero or more `DeliveryDecision` and `DeliverySurfaceState` records.
- `DeliveryDecision` is derived from the `AdvisorSnapshot`, `DeliveryFingerprint`, and relevant `DeliverySurfaceState`.
- `TelegramDeliveryTarget` affects only the Telegram surface decision and outcome.

## State Notes

- On-demand requests may still return a report even when the corresponding surface decision is `suppress`.
- Launcher delivery must be fail-open: delivery failure must not be treated as startup failure.
- Telegram surface state should distinguish `failed` from `suppressed` so retry logic remains possible.
