# Data Model: Codex CLI Update Advisor

## Entities

### MonitorSnapshot

Represents the normalized input taken from the completed update monitor.

| Field | Type | Description |
|-------|------|-------------|
| `local_version` | string | Local Codex CLI version from the monitor |
| `latest_version` | string | Latest checked upstream version from the monitor |
| `version_status` | enum | `ahead`, `current`, `behind`, or `unknown` |
| `recommendation` | enum | `upgrade-now`, `upgrade-later`, `ignore`, or `investigate` |
| `relevant_changes` | object[] | Relevant change entries from the monitor |
| `repo_workflow_traits` | string[] | Repository workflow traits from the monitor |
| `evidence` | string[] | Supporting evidence carried into advisor decisions |

### NotificationFingerprint

Represents the stable actionable identity of the current advisor result.

| Field | Type | Description |
|-------|------|-------------|
| `value` | string | Stable digest derived from recommendation, relevant change IDs, and latest version |
| `reason_parts` | string[] | Human-readable fragments used to explain what contributed to the fingerprint |

### AdvisorState

Represents the locally persisted memory used to suppress duplicate alerts.

| Field | Type | Description |
|-------|------|-------------|
| `last_fingerprint` | string | Last notify-worthy fingerprint recorded by the advisor |
| `last_recommendation` | string | Last recommendation that triggered notification logic |
| `last_notified_at` | string | Timestamp of the last notify-worthy run |
| `last_issue_target` | string | Most recent Beads target if one was created or updated |
| `notes` | string[] | State load or migration notes |

### NotificationDecision

Represents the user-facing noise-control outcome for the current run.

| Field | Type | Description |
|-------|------|-------------|
| `status` | enum | `notify`, `suppressed`, `none`, or `investigate` |
| `changed` | boolean | Whether the current actionable fingerprint differs from the persisted one |
| `threshold` | string | Configured notification threshold used by the run |
| `reason` | string | Plain-language explanation of the decision |
| `notes` | string[] | Additional details about state handling or threshold evaluation |

### ProjectChangeSuggestion

Represents one repository-specific follow-up suggestion derived from the monitor evidence.

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stable identifier for the suggestion |
| `title` | string | Plain-language follow-up title |
| `priority` | enum | `high`, `medium`, or `low` |
| `category` | string | Suggestion grouping such as `docs`, `workflow`, `tooling`, or `investigation` |
| `rationale` | string | Why this repository should care about the suggestion |
| `impacted_paths` | string[] | Repository paths or surfaces likely affected |
| `next_steps` | string[] | Concrete human follow-up actions |

### ImplementationBrief

Represents the grouped handoff payload for human review or tracker sync.

| Field | Type | Description |
|-------|------|-------------|
| `summary` | string | Short plain-language explanation of what changed |
| `top_priorities` | string[] | Highest-signal next actions |
| `impacted_paths` | string[] | De-duplicated set of impacted repository paths |
| `notes` | string[] | Additional caveats for backlog or implementation planning |

### AdvisorIssueAction

Represents the resulting tracker action for the advisor run.

| Field | Type | Description |
|-------|------|-------------|
| `mode` | enum | `none`, `suggested`, `created`, `updated`, or `skipped` |
| `requested` | boolean | Whether tracker sync was explicitly requested |
| `target` | string | Beads issue identifier if known |
| `notes` | string[] | Audit trail for why the action happened or was skipped |

### AdvisorRunReport

Represents the top-level output contract for every advisor run.

| Field | Type | Description |
|-------|------|-------------|
| `checked_at` | string | Advisor run timestamp |
| `monitor_snapshot` | MonitorSnapshot | Normalized baseline evidence from the update monitor |
| `notification` | NotificationDecision | Low-noise notification result for the run |
| `project_change_suggestions` | ProjectChangeSuggestion[] | Repository-specific follow-up suggestions |
| `implementation_brief` | ImplementationBrief | Grouped next-step handoff payload |
| `issue_action` | AdvisorIssueAction | Tracker mutation result or suggestion |

## Relationships

- `AdvisorRunReport` owns one `MonitorSnapshot`, one `NotificationDecision`, one `ImplementationBrief`, and one `AdvisorIssueAction`.
- `AdvisorRunReport` may include zero or more `ProjectChangeSuggestion` records.
- `NotificationDecision` depends on `MonitorSnapshot`, `NotificationFingerprint`, and optional `AdvisorState`.
- `ImplementationBrief` is derived from `MonitorSnapshot` plus the chosen `ProjectChangeSuggestion` records.
- `AdvisorIssueAction` depends on both `NotificationDecision` and the explicit operator sync request.

## State Notes

- Missing or malformed `AdvisorState` must be treated as recoverable and recorded in `notification.notes`.
- `notification.status=suppressed` means the current actionable state matches the last recorded notify-worthy fingerprint.
- `notification.status=none` is the expected default when monitor evidence is below the configured threshold.
- `notification.status=investigate` is the safe fallback when the monitor input is incomplete or contradictory.
