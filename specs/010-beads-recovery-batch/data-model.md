# Data Model: Safe Batch Recovery of Leaked Beads Issues

## Entity: OwnershipOverrideMap

- `version` (integer, required): schema version for the override file
- `entries` (array[OwnershipOverrideEntry], required)

## Entity: OwnershipOverrideEntry

- `issue_id` (string, required): leaked issue identifier
- `branch` (string, required): owner branch selected by maintainers
- `worktree_hint` (string, optional): expected worktree path suffix or name for better diagnostics
- `reason` (string, required): why this override is safe

## Entity: RecoveryCandidate

- `issue_id` (string, required)
- `title` (string, required)
- `source_state` (enum, required): `root_only` | `already_present_in_target` | `missing_from_root`
- `owner_branch` (string, optional)
- `owner_worktree` (string, optional)
- `confidence` (enum, required): `high` | `blocked`
- `blockers` (array[string], required)
- `requires_localization` (boolean, required)

## Entity: RecoveryPlan

- `schema` (string, required): artifact schema identifier
- `generated_at` (datetime, required)
- `canonical_root` (string, required)
- `source_jsonl` (string, required)
- `topology_fingerprint` (string, required): hash of live topology used during audit
- `ownership_map` (string, optional): override file used during audit
- `candidates` (array[RecoveryCandidate], required)
- `safe_count` (integer, required)
- `blocked_count` (integer, required)

## Entity: RecoveryAction

- `issue_id` (string, required)
- `target_worktree` (string, required)
- `localized` (boolean, required)
- `backup_path` (string, required)
- `result` (enum, required): `imported` | `imported_jsonl_only` | `already_present` | `blocked` | `failed`
- `details` (string, optional)

## Entity: RecoveryJournal

- `schema` (string, required)
- `mode` (enum, required): `audit` | `apply`
- `started_at` (datetime, required)
- `finished_at` (datetime, required)
- `plan_path` (string, optional)
- `topology_fingerprint` (string, required)
- `canonical_root_cleanup_allowed` (boolean, required)
- `actions` (array[RecoveryAction], required)
- `blocked` (array[RecoveryCandidate], required)

## Entity: RecoveryBackup

- `worktree` (string, required)
- `issues_jsonl_backup` (string, required)
- `created_at` (datetime, required)
- `plan_action_ids` (array[string], required)
