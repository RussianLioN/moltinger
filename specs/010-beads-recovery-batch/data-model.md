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
- `issue_digest` (string, required): digest of the exact root JSONL record seen during audit
- `source_state` (enum, required): `root_only` | `already_present_in_target` | `already_present_in_owner_branch` | `missing_from_root`
- `owner_branch` (string, optional)
- `owner_worktree` (string, optional)
- `confidence` (enum, required): `high` | `blocked`
- `blockers` (array[string], required)
- `requires_localization` (boolean, required)
- `validation_contract` (ValidationContract, optional): candidate-scoped proof bundle used by `apply`

## Entity: ValidationContract

- `issue_id` (string, required)
- `source_issue` (SourceIssueContract, required)
- `owner_branch` (string, required)
- `owner_worktree` (string, required)
- `beads_state` (enum, required): `local` | `redirected` | `missing`
- `redirect_target` (string, optional)
- `target_issue_present` (boolean, required)

## Entity: SourceIssueContract

- `state` (enum, required): `present` | `missing` | `duplicate`
- `digest` (string, optional): digest of the source issue payload when exactly one source record exists
- `title` (string, optional)
- `priority` (string, optional)
- `status` (string, optional)

## Entity: RecoveryPlan

- `schema` (string, required): artifact schema identifier
- `generated_at` (datetime, required)
- `canonical_root` (string, required)
- `source_jsonl` (string, required)
- `source_jsonl_digest` (string, required): digest of the exact source snapshot used during audit
- `topology_epoch` (string, required): advisory hash of full live topology at audit time
- `topology_fingerprint` (string, required): legacy-compatible alias of `topology_epoch`
- `ownership_map` (string, optional): override file used during audit
- `ownership_map_digest` (string, optional): digest of the override file used during audit
- `candidates` (array[RecoveryCandidate], required)
- `safe_count` (integer, required)
- `blocked_count` (integer, required)

## Entity: RecoveryAction

- `issue_id` (string, required)
- `target_worktree` (string, required)
- `localized` (boolean, required)
- `backup_path` (string, required)
- `result` (enum, required): `imported` | `imported_jsonl_only` | `already_present` | `blocked_topology_drift` | `failed`
- `details` (string, optional)
- `validation` (ValidationResult, optional)

## Entity: ValidationResult

- `status` (enum, required): `ok` | `already_present` | `blocked`
- `message` (string, required)
- `reasons` (array[string], required)
- `current` (LiveCandidateState, required)

## Entity: LiveCandidateState

- `issue_id` (string, required)
- `source_issue` (SourceIssueContract, required)
- `owner_state` (enum, required): `resolved` | `missing_owner_branch` | `blocked` | `missing_worktree` | `already_present_in_owner_branch` | `ambiguous_worktree`
- `owner_blocker` (string, optional)
- `owner_branch` (string, optional)
- `ownership_reason` (string, optional)
- `owner_worktree` (string, optional)
- `beads_state` (string, optional)
- `redirect_target` (string, optional)
- `target_issue_present` (boolean, required)

## Entity: RecoveryJournal

- `schema` (string, required)
- `mode` (enum, required): `audit` | `apply`
- `started_at` (datetime, required)
- `finished_at` (datetime, required)
- `plan_path` (string, optional)
- `plan_schema` (string, optional)
- `topology_epoch` (string, required)
- `plan_topology_epoch` (string, optional)
- `topology_fingerprint` (string, required): legacy-compatible alias of `topology_epoch`
- `topology_drift_detected` (boolean, required): advisory full-topology drift signal
- `canonical_root_cleanup_allowed` (boolean, required)
- `actions` (array[RecoveryAction], required)
- `blocked` (array[RecoveryCandidate], required)

## Entity: RecoveryBackup

- `worktree` (string, required)
- `issues_jsonl_backup` (string, required)
- `created_at` (datetime, required)
- `plan_action_ids` (array[string], required)
