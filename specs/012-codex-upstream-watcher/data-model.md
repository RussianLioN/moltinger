# Data Model: Codex Upstream Watcher

## Entities

### UpstreamSnapshot

Represents the normalized upstream Codex state derived from official sources.

| Field | Type | Description |
|-------|------|-------------|
| `latest_version` | string | Latest upstream version discovered from the primary release source |
| `release_status` | enum | `new`, `known`, `investigate`, or `unavailable` |
| `primary_source` | object | Status and metadata for the primary changelog source |
| `advisory_sources` | object[] | Optional advisory source summaries such as issue feeds |
| `advisory_items` | object[] | Normalized advisory issue items used as context |
| `highlights` | string[] | Raw upstream highlights from the primary source |
| `highlight_explanations` | string[] | Russian plain-language explanations derived from the highlights |
| `recent_releases` | object[] | Recent normalized release entries used for digest output |

### UpstreamFingerprint

Represents the stable identity of the current upstream Codex state.

| Field | Type | Description |
|-------|------|-------------|
| `value` | string | Stable digest computed from normalized upstream data |
| `checked_at` | string | Timestamp of the watcher run that derived this fingerprint |

### WatcherState

Represents persisted memory for scheduled upstream watching.

| Field | Type | Description |
|-------|------|-------------|
| `last_seen_fingerprint` | string | Most recent upstream fingerprint observed |
| `last_delivered_fingerprint` | string | Most recent upstream fingerprint successfully delivered to Telegram |
| `last_status` | enum | `delivered`, `suppressed`, `failed`, `investigate`, `queued`, or `unknown` |
| `last_checked_at` | string | Timestamp of the last watcher run |
| `delivered_fingerprints` | string[] | Rolling memory of fingerprints already delivered to Telegram |
| `digest_pending` | object[] | Pending digest items for non-critical upstream events |
| `last_digest_sent_at` | string | Timestamp of the last combined digest delivery |
| `last_update_id` | integer | Last processed Telegram Bot API update id |
| `pending_consent` | object | Pending Telegram yes/no follow-up for practical recommendations |
| `notes` | string[] | Watcher audit trail and failure details |

### WatcherDecision

Represents the outcome of one watcher run.

| Field | Type | Description |
|-------|------|-------------|
| `status` | enum | `deliver`, `suppress`, `retry`, `investigate`, or `queued` |
| `reason` | string | Plain-language explanation of the current watcher decision |
| `changed` | boolean | Whether the watcher sees the upstream fingerprint as fresh |
| `delivery_mode` | enum | `immediate` or `digest` |

### WatcherSeverity

Represents the importance of the current upstream state.

| Field | Type | Description |
|-------|------|-------------|
| `level` | enum | `info`, `important`, `critical`, or `investigate` |
| `reason` | string | Why the watcher assigned this severity |

### WatcherAdvisorBridge

Represents project-facing recommendations prepared through the existing advisor layer.

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | boolean | Whether the advisor bridge is active for this run |
| `status` | enum | `disabled`, `unavailable`, `investigate`, or `ready` |
| `summary` | string | Short Russian explanation of whether practical recommendations are available |
| `top_priorities` | string[] | Top project-facing recommendations in plain language |
| `practical_recommendations` | object[] | Detailed recommendation objects with rationale, impacted paths, and next steps |
| `question` | string | Telegram question shown to the user before sending recommendations |

### WatcherTelegramTarget

Represents Telegram delivery configuration for scheduled alerts.

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | boolean | Whether Telegram delivery is enabled for this run |
| `consent_enabled` | boolean | Whether the watcher should ask about practical recommendations in Telegram |
| `chat_id` | string | Destination chat or user id |
| `silent` | boolean | Whether scheduled alerts should use silent mode |
| `env_file` | string | Optional env file path used to load bot credentials |

### WatcherRunReport

Represents the top-level machine-readable output from the watcher.

| Field | Type | Description |
|-------|------|-------------|
| `checked_at` | string | Watcher run timestamp |
| `feature_explanation` | string[] | Simple Russian explanation of the new watcher capabilities |
| `snapshot` | UpstreamSnapshot | Normalized upstream Codex state |
| `fingerprint` | string | Stable upstream fingerprint for this run |
| `severity` | WatcherSeverity | Importance of the current upstream state |
| `decision` | WatcherDecision | Freshness/delivery decision for the run |
| `advisor_bridge` | WatcherAdvisorBridge | Project-facing practical guidance derived from the advisor layer |
| `followup` | object | Digest and Telegram consent state for the current run |
| `automation` | object | Concrete alert/recommendation actions the runtime should perform |
| `state` | WatcherState | Persisted watcher state after the run |
| `telegram_target` | WatcherTelegramTarget | Telegram configuration when delivery is enabled |
| `notes` | string[] | Overall warnings, delivery notes, and failure details |

## Relationships

- `WatcherRunReport` owns one `UpstreamSnapshot`, one `WatcherSeverity`, one `WatcherDecision`, one `WatcherAdvisorBridge`, and one persisted `WatcherState` summary.
- `WatcherDecision` is derived from the current `UpstreamSnapshot`, `UpstreamFingerprint`, and prior `WatcherState`.
- `WatcherTelegramTarget` affects delivery behavior and consent follow-up, but does not redefine the upstream fingerprint itself.
- `WatcherAdvisorBridge` depends on the existing local monitor/advisor stack and is intentionally separated from the upstream watcher core.

## State Notes

- The same upstream fingerprint may be `known` for the watcher while still being “not yet reviewed locally” in a future local applicability flow.
- A failed Telegram send must preserve retryability for the same upstream fingerprint.
- Partial or malformed source evidence should not be collapsed into a silent success state.
- Digest mode keeps non-critical fingerprints pending until the batching threshold is reached.
- Practical recommendations are only sent after explicit user consent in Telegram.
