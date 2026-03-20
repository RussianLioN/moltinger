# Data Model: Deterministic Beads Issues JSONL Ownership

## Overview

Модель данных описывает не бизнес-сущности Beads как таковые, а control-plane вокруг ownership/sync для tracked `.beads/issues.jsonl`.

## Entities

### WorktreeSyncContext

| Field | Type | Description |
|------|------|-------------|
| `repo_root` | path | Текущая worktree root path |
| `canonical_root` | path | Canonical git root |
| `current_branch` | string | Текущая branch identity |
| `context_kind` | enum | `canonical_root`, `dedicated_worktree`, `non_repo`, `detached`, `unknown` |
| `ownership_state` | enum | `current`, `legacy`, `partial`, `ambiguous`, `blocked` |
| `db_path` | path | Resolved runtime DB path |
| `jsonl_path` | path | Intended tracked `.beads/issues.jsonl` path |
| `topology_fingerprint` | string | Stable summary of worktree topology used for RCA and migration |

**Validation rules**

- `jsonl_path` must belong to `repo_root` for dedicated-worktree semantic sync.
- `canonical_root` and `repo_root` must be distinguished explicitly when they differ.

### SyncAuthorityDecision

| Field | Type | Description |
|------|------|-------------|
| `decision_code` | enum | `allow_semantic_sync`, `allow_root_explicit`, `block_root_leak`, `block_sibling_rewrite`, `block_ambiguous_owner`, `block_legacy_migration_required`, `block_noise_only_rewrite` |
| `allow_write` | boolean | Whether the operation may mutate JSONL |
| `target_jsonl_path` | path | Only set when rewrite is allowed |
| `reason_summary` | string | Human-readable short explanation |
| `recovery_hint` | string | Next operator step when blocked |
| `root_cleanup_notice` | string | Optional reminder that root cleanup is separate |

**Validation rules**

- `allow_write=true` requires a single `target_jsonl_path`.
- `allow_write=false` requires `reason_summary`.

### JsonlRewriteEvidence

| Field | Type | Description |
|------|------|-------------|
| `run_id` | string | Stable RCA or sync evidence identifier |
| `scenario_id` | string | Fixture or operator scenario name |
| `before_hash` | string | Hash of source JSONL before action |
| `after_hash` | string | Hash after attempted action |
| `rewrite_kind` | enum | `semantic`, `noise_only`, `blocked`, `migration`, `rollback` |
| `changed_issue_ids` | list<string> | Issues whose semantic payload changed |
| `changed_worktrees` | list<path> | Worktrees touched or proposed |
| `decision_code` | string | Link back to `SyncAuthorityDecision` |
| `log_path` | path | Human/machine-readable journal location |

**Validation rules**

- `rewrite_kind=blocked` must not list touched target files as mutated.
- `noise_only` must have empty semantic issue delta.

### RcaReproductionRun

| Field | Type | Description |
|------|------|-------------|
| `scenario_id` | string | Unique reproduction scenario |
| `fixture_name` | string | Fixture family used |
| `steps` | list<string> | Deterministic operator/test steps |
| `expected_decision_code` | string | Expected authority decision |
| `expected_verdict` | enum | `leakage`, `noise_only`, `safe_semantic`, `ambiguous`, `legacy_migration` |
| `artifacts` | list<path> | Journals, snapshots, diffs, hashes |

### MigrationCandidate

| Field | Type | Description |
|------|------|-------------|
| `worktree_path` | path | Candidate worktree |
| `ownership_state` | enum | `current`, `legacy`, `partial`, `ambiguous`, `damaged` |
| `issue_family_scope` | enum | `safe_subset`, `duplicate_subset`, `blocked_subset`, `orphan_subset` |
| `planned_action` | enum | `none`, `normalize`, `localize`, `apply_safe`, `manual_only`, `defer` |
| `snapshot_path` | path | Pre-change backup location |
| `blocker_summary` | string | Why automation cannot proceed safely |

### MigrationJournal

| Field | Type | Description |
|------|------|-------------|
| `journal_id` | string | Migration run identifier |
| `mode` | enum | `audit`, `apply`, `verify`, `rollback` |
| `candidates` | list<MigrationCandidate> | Classified worktrees |
| `blocked_count` | integer | Number of blocked candidates |
| `safe_count` | integer | Number of safely automatable candidates |
| `evidence_paths` | list<path> | Snapshots and logs |

### RolloutCheckpoint

| Field | Type | Description |
|------|------|-------------|
| `stage` | enum | `report_only`, `controlled_enforcement`, `verification`, `rollback_ready` |
| `entry_criteria` | list<string> | What must be true before entering stage |
| `success_signals` | list<string> | Metrics/logs that prove stage success |
| `rollback_trigger` | list<string> | Conditions that require rollback |

### RollbackPackage

| Field | Type | Description |
|------|------|-------------|
| `previous_mode` | string | Last known-good enforcement mode |
| `restore_commands` | list<string> | Planned operator commands |
| `restore_inputs` | list<path> | Snapshots or config surfaces needed |
| `preserved_evidence` | list<path> | Artifacts that must survive rollback |

## Relationships

- One `WorktreeSyncContext` produces one `SyncAuthorityDecision` per mutating attempt.
- One `SyncAuthorityDecision` may emit one `JsonlRewriteEvidence` record.
- One `RcaReproductionRun` references one or more `JsonlRewriteEvidence` records.
- One `MigrationJournal` aggregates many `MigrationCandidate` records.
- Rollout and rollback operate on `MigrationJournal` evidence and `RolloutCheckpoint` gates.

## State Transitions

### Sync Authority

`current context` -> `decision computed` -> `allow semantic sync` or `block with evidence`

Allowed path:

`allow_semantic_sync` -> `canonicalize` -> `write target JSONL` -> `emit evidence`

Blocked path:

`ownership ambiguity / root leak / sibling rewrite / noise-only rewrite` -> `no write` -> `emit evidence + recovery hint`

### Migration

`audit` -> `candidate classification` -> `safe apply subset` or `manual-only blocked subset` -> `verify` -> optional `rollback`
