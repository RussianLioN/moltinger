# Data Model: UX-Safe Beads Local Ownership

## OwnershipContract

- **Purpose**: Represents the local worktree conditions that prove Beads ownership is safe.
- **Fields**:
  - `worktree_root`: absolute path to the current worktree root
  - `config_path`: expected path to `.beads/config.yaml`
  - `issues_path`: expected path to `.beads/issues.jsonl`
  - `db_path`: expected path to `.beads/beads.db`
  - `redirect_state`: `absent` | `present_legacy`
  - `foundation_state`: `complete` | `partial` | `missing`
  - `ownership_scope`: `dedicated_worktree` | `canonical_root` | `unknown`

## BdDispatchRequest

- **Purpose**: Captures what plain `bd` is being asked to do and whether the command can mutate state.
- **Fields**:
  - `argv`: original command-line arguments
  - `command_name`: top-level `bd` subcommand or empty for help/version flows
  - `mode`: `mutating` | `read_only` | `diagnostic`
  - `cwd`: working directory where the command was invoked
  - `active_bd_binary`: resolved executable path that the session is using

## BdDispatchDecision

- **Purpose**: Represents the authoritative result of safe ownership resolution before command execution.
- **Fields**:
  - `decision`: `execute_local` | `block_missing_foundation` | `block_legacy_redirect` | `block_unresolved_ownership` | `block_root_fallback` | `allow_explicit_troubleshooting`
  - `db_path`: resolved local DB path when execution is allowed
  - `user_message`: exact human-facing explanation
  - `recovery_hint`: exact next step when blocked
  - `root_cleanup_notice`: optional separate reminder if root residue is observed but not blocking the local fix

## SessionBootstrapState

- **Purpose**: Describes whether the current session makes plain `bd` resolve to the repo-local shim.
- **Fields**:
  - `path_mode`: `repo_local_shim` | `system_bd` | `unknown`
  - `bootstrap_source`: `direnv` | `managed_handoff` | `codex_launcher` | `manual_shell` | `unknown`
  - `status`: `ready` | `not_bootstrapped` | `ambiguous`
  - `recommended_action`: exact next step when plain `bd` is not yet safe

## CompatibilityMigrationState

- **Purpose**: Tracks whether an existing worktree already satisfies the ownership contract or needs localization.
- **Fields**:
  - `state`: `current` | `migratable_legacy` | `partial_foundation` | `damaged_blocked`
  - `can_localize_in_place`: boolean
  - `requires_manual_attention`: boolean
  - `migration_action`: `none` | `localize_in_place` | `rebuild_local_foundation` | `stop_and_report`
  - `notes`: concise explanation of why this state exists

## RootCleanupBoundary

- **Purpose**: Separates residual root concerns from the dedicated-worktree ownership fix.
- **Fields**:
  - `status`: `none` | `notice_only` | `separate_follow_up_required`
  - `blocks_local_fix`: boolean, expected to remain `false` for this feature’s normal scope
  - `follow_up_path`: optional separate cleanup workflow or issue reference
  - `reported_to_user`: boolean
