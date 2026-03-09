# Contract: Worktree Readiness Report

## Canonical Fields

```json
{
  "worktree_path": "/absolute/path",
  "branch_name": "feature-or-existing-branch",
  "issue_id": "BD-123",
  "status": "created",
  "phase": "create",
  "boundary": "stop_after_create",
  "final_state": "handoff_needs_env_approval",
  "env_state": "approval_needed",
  "guard_state": "ok",
  "beads_state": "redirected",
  "handoff_mode": "manual",
  "approval_required": true,
  "launch_command": "cd /absolute/path && direnv allow",
  "next_steps": [
    "cd /absolute/path",
    "direnv allow",
    "codex"
  ],
  "warnings": [
    "Automatic terminal handoff is unavailable on this platform"
  ]
}
```

## Field Rules

- `worktree_path`: required absolute path
- `branch_name`: required resolved branch
- `issue_id`: optional
- `status`: required one of:
  - `created`
  - `needs_env_approval`
  - `ready_for_codex`
  - `drift_detected`
  - `action_required`
- `phase`: required one of:
  - `create`
  - `attach`
  - `doctor`
  - `handoff`
- `boundary`: required one of:
  - `stop_after_create`
  - `stop_after_attach`
  - `stop_after_handoff`
  - `none`
- `final_state`: required one of:
  - `handoff_ready`
  - `handoff_needs_env_approval`
  - `handoff_needs_manual_readiness`
  - `handoff_launched`
  - `blocked_guard_drift`
  - `blocked_missing_branch`
  - `blocked_action_required`
- `env_state`: required one of:
  - `unknown`
  - `no_envrc`
  - `approval_needed`
  - `approved_or_not_required`
- `guard_state`: required one of:
  - `unknown`
  - `missing`
  - `ok`
  - `drift`
- `beads_state`: required one of:
  - `shared`
  - `redirected`
  - `missing`
- `handoff_mode`: required one of:
  - `manual`
  - `terminal`
  - `codex`
- `approval_required`: required boolean
- `launch_command`: optional exact launch or approval command
- `repair_command`: optional exact corrective command for blocked states
- `next_steps`: required ordered list; must not be empty when `status != ready_for_codex`
- `warnings`: optional ordered list of user-facing caveats

## Status Mapping

- `ready_for_codex`: user can launch Codex immediately without another prerequisite step
- `needs_env_approval`: environment step must be completed before launch
- `created`: worktree exists but additional non-environment action is still required
- `drift_detected`: worktree or branch no longer matches expected guarded state
- `action_required`: generic fallback for cases that need a user-visible recovery step

## Final State Mapping

- `handoff_ready`: create/attach finished and the next session can launch immediately
- `handoff_needs_env_approval`: create/attach finished, but `direnv allow` or equivalent approval must happen before launch
- `handoff_needs_manual_readiness`: create/attach finished, but the environment probe remained unknown and the workflow must stop with manual next steps
- `handoff_launched`: a supported `terminal` or `codex` handoff successfully launched, and the originating session must stop
- `blocked_guard_drift`: the target worktree exists but guard drift must be resolved before continuing
- `blocked_missing_branch`: the requested existing branch is unavailable locally
- `blocked_action_required`: other blocked prerequisite state that still requires a precise recovery command
