# Contract: Worktree Readiness Report

## Canonical Fields

```json
{
  "worktree_path": "/absolute/path",
  "branch_name": "feature-or-existing-branch",
  "issue_id": "BD-123",
  "status": "created",
  "env_state": "approval_needed",
  "guard_state": "ok",
  "beads_state": "redirected",
  "handoff_mode": "manual",
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
- `next_steps`: required ordered list; must not be empty when `status != ready_for_codex`
- `warnings`: optional ordered list of user-facing caveats

## Status Mapping

- `ready_for_codex`: user can launch Codex immediately without another prerequisite step
- `needs_env_approval`: environment step must be completed before launch
- `created`: worktree exists but additional non-environment action is still required
- `drift_detected`: worktree or branch no longer matches expected guarded state
- `action_required`: generic fallback for cases that need a user-visible recovery step
