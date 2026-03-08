# Data Model: Auto-Maintained Git Topology Registry

## Entity: LiveTopologySnapshot

- `snapshot_id` (string, required): deterministic hash of normalized topology data
- `generated_at` (datetime, optional): local generation time for non-committed state
- `worktrees` (array[WorktreeEntry], required)
- `local_branches` (array[LocalBranchEntry], required)
- `remote_unmerged_branches` (array[RemoteBranchEntry], required)
- `warnings` (array[string], optional)

## Entity: WorktreeEntry

- `worktree_id` (string, required): sanitized stable identifier used in the committed registry
- `branch` (string, required)
- `location_class` (enum, required): `primary` | `codex-managed` | `sibling-worktree` | `local-only` | `unknown`
- `status` (enum, required): `active` | `protected-from-cleanup` | `review-before-cleanup` | `historical` | `unknown`
- `is_current` (boolean, required)
- `raw_path` (string, optional, non-committed state only)

## Entity: LocalBranchEntry

- `branch` (string, required)
- `tracking` (string, optional)
- `tracking_state` (enum, required): `tracking` | `gone` | `none`
- `status` (enum, required): `active` | `historical` | `protected` | `needs-decision`
- `has_worktree` (boolean, required)

## Entity: RemoteBranchEntry

- `remote_ref` (string, required)
- `branch` (string, required)
- `status` (enum, required): `active` | `historical` | `extract-only` | `cleanup-candidate` | `needs-decision`

## Entity: TopologyIntentRecord

- `subject_type` (enum, required): `branch` | `worktree` | `remote`
- `subject_key` (string, required): stable key used to match generated rows
- `intent` (enum, required): `active` | `historical` | `extract-only` | `cleanup-candidate` | `protected` | `needs-decision`
- `note` (string, optional): short reviewed note safe to commit
- `pr` (integer, optional)

## Entity: TopologyRegistryDocument

- `title` (string, required)
- `scope_note` (string, required)
- `generated_sections` (array[string], required)
- `manual_policy_section` (string, required)

## Entity: TopologyRegistryHealth

- `status` (enum, required): `ok` | `stale` | `error`
- `current_hash` (string, required)
- `rendered_hash` (string, optional)
- `pending_events` (integer, optional)
- `last_success_at` (datetime, optional)
- `last_error` (string, optional)
