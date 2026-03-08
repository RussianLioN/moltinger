# Data Model: Worktree Ready UX

## WorktreeIntent

- **Purpose**: Captures what the user is asking the `worktree` workflow to do.
- **Fields**:
  - `mode`: `start_new` | `start_existing` | `finish` | `cleanup` | `doctor` | `list`
  - `issue_id`: optional task/issue reference
  - `branch_name`: optional explicit branch target
  - `slug`: optional human-readable task label
  - `handoff_mode`: `manual` | `terminal` | `codex`
  - `delete_branch`: boolean for cleanup flows

## WorktreeTarget

- **Purpose**: Represents the resolved filesystem and git target for the request.
- **Fields**:
  - `branch_name`: git branch to attach or create
  - `worktree_path`: absolute path of the target worktree
  - `path_preview`: user-facing sanitized path preview
  - `existing_worktree_path`: optional path if branch is already attached elsewhere
  - `issue_id`: optional issue reference carried into the worktree

## ReadinessReport

- **Purpose**: The authoritative user-facing state after creation or diagnosis.
- **Fields**:
  - `status`: `created` | `needs_env_approval` | `ready_for_codex` | `drift_detected` | `action_required`
  - `branch_name`: resolved branch
  - `worktree_path`: resolved path
  - `env_state`: `unknown` | `no_envrc` | `approval_needed` | `approved_or_not_required`
  - `guard_state`: `unknown` | `missing` | `ok` | `drift`
  - `beads_state`: `shared` | `redirected` | `missing`
  - `next_steps`: ordered list of user-facing actions
  - `warnings`: optional list of caveats or degraded capabilities

## HandoffProfile

- **Purpose**: Describes how the workflow should transition the user from result output to an active session.
- **Fields**:
  - `mode`: `manual` | `terminal` | `codex`
  - `platform_support`: `available` | `unsupported` | `unknown`
  - `launch_command`: shell command or platform-specific automation command
  - `fallback_command`: manual equivalent if automation is unavailable

## DoctorCheck

- **Purpose**: Represents one readiness diagnostic probe and its outcome.
- **Fields**:
  - `name`: check identifier, such as `branch_mapping`, `beads_redirect`, `session_guard`, `environment_approval`
  - `status`: `pass` | `warn` | `fail`
  - `details`: short human-readable explanation
  - `recommended_action`: exact next action when status is not `pass`
