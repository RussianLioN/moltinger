# Data Model: Beads Dolt-Native Migration

## Entities

### 1. BeadsTargetContract

| Field | Type | Description |
|---|---|---|
| `name` | string | Short label for the target repo-level Beads contract |
| `upstream_direction` | string | The upstream model this repo is aligning to |
| `primary_issue_state_path` | string | The authoritative issue-state path under the target contract |
| `jsonl_role` | enum | Role of `.beads/issues.jsonl` after migration: `removed`, `export_only`, `backup_only`, `bounded_other` |
| `operator_flow` | string | Human/agent workflow for create/update/review/sync |
| `worktree_policy` | string | Expected ownership/isolation behavior across worktrees |

### 2. LegacySurfaceInventoryItem

| Field | Type | Description |
|---|---|---|
| `surface_id` | string | Stable identifier for one repo-local legacy surface |
| `path` | string | File or workflow path |
| `surface_type` | enum | `wrapper`, `hook`, `doc`, `skill`, `config`, `test`, `script`, `bootstrap`, `tracked_artifact` |
| `current_behavior` | string | What the surface currently encourages or enforces |
| `classification` | enum | `must-migrate`, `can-bridge`, `can-remove`, `already-compatible`, `blocked` |
| `required_action` | string | The action needed before cutover |
| `blocking_reason` | string? | Why this surface blocks migration, if applicable |

### 3. MigrationReadinessReport

| Field | Type | Description |
|---|---|---|
| `report_id` | string | Stable report identifier |
| `scope` | enum | `repo`, `worktree`, `pilot`, `rollout-batch` |
| `generated_at` | datetime | Timestamp |
| `critical_blockers` | integer | Count of blocking items |
| `warning_count` | integer | Count of non-blocking warnings |
| `ready_for_stage` | enum | `report-only`, `pilot`, `cutover`, `verification`, `none` |
| `inventory_items` | array<LegacySurfaceInventoryItem> | Classified legacy surfaces |
| `notes` | string | Human-readable summary |

### 4. PilotCutoverRun

| Field | Type | Description |
|---|---|---|
| `pilot_id` | string | Stable pilot run identifier |
| `worktree_path` | string | Pilot worktree |
| `preconditions_met` | boolean | Whether readiness gate passed |
| `lifecycle_steps` | array<string> | Executed operator steps |
| `legacy_surface_hits` | array<string> | Any blocked or intercepted legacy actions |
| `review_surface_result` | string | Output of the new operator/review surface |
| `verdict` | enum | `pass`, `fail`, `blocked` |

### 5. WorktreeCutoverStatus

| Field | Type | Description |
|---|---|---|
| `worktree_key` | string | Stable worktree identifier |
| `branch` | string | Git branch name |
| `stage` | enum | `report-only`, `ready`, `pilot`, `cutover`, `blocked`, `rolled-back` |
| `reason` | string | Human-readable status reason |
| `last_verified_at` | datetime? | Last verification timestamp |

### 6. OperatorReviewSurface

| Field | Type | Description |
|---|---|---|
| `surface_name` | string | Name of the replacement review/inspection method |
| `inputs` | array<string> | Required inputs |
| `outputs` | array<string> | Expected human/agent-visible outputs |
| `covers_primary_flow` | boolean | Whether it covers daily review needs |
| `requires_legacy_jsonl` | boolean | Must be false for full cutover |

### 7. RollbackPackage

| Field | Type | Description |
|---|---|---|
| `package_id` | string | Stable rollback package ID |
| `snapshot_paths` | array<string> | Saved artifacts before cutover |
| `restores_operator_flow` | boolean | Whether rollback restores a usable operator path |
| `restores_worktree_statuses` | boolean | Whether worktree states are explicitly re-verified |
| `evidence_retained` | boolean | Whether migration evidence is preserved |

## Relationships

- One `BeadsTargetContract` governs many `LegacySurfaceInventoryItem`.
- One `MigrationReadinessReport` includes many `LegacySurfaceInventoryItem`.
- One `PilotCutoverRun` operates on one `WorktreeCutoverStatus`.
- One `RollbackPackage` corresponds to one cutover stage or pilot.
- One `OperatorReviewSurface` must be compatible with the `BeadsTargetContract`.

## State Transitions

### WorktreeCutoverStatus

`report-only -> ready -> pilot -> cutover -> verification`

Failure paths:

- `report-only -> blocked`
- `ready -> blocked`
- `pilot -> blocked`
- `cutover -> rolled-back`

### PilotCutoverRun Verdict

`preconditions_met=false -> blocked`

`preconditions_met=true -> pass | fail`
