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
| `highlights` | string[] | Plain-language summary points about notable upstream changes |

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
| `last_status` | enum | `delivered`, `suppressed`, `failed`, `investigate`, or `unknown` |
| `last_checked_at` | string | Timestamp of the last watcher run |
| `notes` | string[] | Watcher audit trail and failure details |

### WatcherDecision

Represents the outcome of one watcher run.

| Field | Type | Description |
|-------|------|-------------|
| `status` | enum | `deliver`, `suppress`, `retry`, or `investigate` |
| `reason` | string | Plain-language explanation of the current watcher decision |
| `changed` | boolean | Whether the watcher sees the upstream fingerprint as fresh |

### WatcherTelegramTarget

Represents Telegram delivery configuration for scheduled alerts.

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | boolean | Whether Telegram delivery is enabled for this run |
| `chat_id` | string | Destination chat or user id |
| `silent` | boolean | Whether scheduled alerts should use silent mode |
| `env_file` | string | Optional env file path used to load bot credentials |

### WatcherRunReport

Represents the top-level machine-readable output from the watcher.

| Field | Type | Description |
|-------|------|-------------|
| `checked_at` | string | Watcher run timestamp |
| `snapshot` | UpstreamSnapshot | Normalized upstream Codex state |
| `fingerprint` | string | Stable upstream fingerprint for this run |
| `decision` | WatcherDecision | Freshness/delivery decision for the run |
| `state` | WatcherState | Persisted watcher state after the run |
| `telegram_target` | WatcherTelegramTarget | Telegram configuration when delivery is enabled |
| `notes` | string[] | Overall warnings, delivery notes, and failure details |

## Relationships

- `WatcherRunReport` owns one `UpstreamSnapshot`, one `WatcherDecision`, and one persisted `WatcherState` summary.
- `WatcherDecision` is derived from the current `UpstreamSnapshot`, `UpstreamFingerprint`, and prior `WatcherState`.
- `WatcherTelegramTarget` affects only delivery behavior and does not redefine the upstream fingerprint itself.

## State Notes

- The same upstream fingerprint may be `known` for the watcher while still being “not yet reviewed locally” in a future local applicability flow.
- A failed Telegram send must preserve retryability for the same upstream fingerprint.
- Partial or malformed source evidence should not be collapsed into a silent success state.
