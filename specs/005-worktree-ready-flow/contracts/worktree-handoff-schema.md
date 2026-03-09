# Contract: Worktree Handoff Schema

## Purpose

Provide a shell-safe, machine-readable handoff block for `create`, `attach`, and explicit `handoff` flows so higher-level orchestration can stop at the right boundary instead of continuing in the originating session.

## Format

- Output format: `key=value`
- Values are shell-escaped via `%q`
- Schema id: `worktree-handoff/v1`

## Required Keys

- `schema`
- `phase`
- `boundary`
- `final_state`
- `branch`
- `worktree`
- `handoff_mode`
- `approval_required`

## Optional Keys

- `decision`
- `worktree_action`
- `issue`
- `status`
- `topology_state`
- `env_state`
- `guard_state`
- `beads_state`
- `launch_command`
- `repair_command`
- `requested_handoff`
- `pending`
- `next_count`
- `next_<N>`
- `warning_count`
- `warning_<N>`

## Example

```text
schema=worktree-handoff/v1
phase=create
boundary=stop_after_create
decision=create_clean
worktree_action=created
final_state=handoff_needs_env_approval
branch=feat/remote-uat-hardening
worktree=/Users/rl/coding/moltinger-remote-uat-hardening
issue=n/a
status=needs_env_approval
topology_state=ok
env_state=approval_needed
guard_state=missing
beads_state=shared
handoff_mode=manual
approval_required=true
launch_command=cd\ /Users/rl/coding/moltinger-remote-uat-hardening\ \&\&\ direnv\ allow
pending=Continue\ the\ requested\ downstream\ task\ from\ the\ target\ worktree\ after\ handoff.
next_count=2
next_1=cd\ /Users/rl/coding/moltinger-remote-uat-hardening\ \&\&\ direnv\ allow
next_2=codex
warning_count=1
warning_1=Environment\ approval\ is\ required\ before\ launching\ the\ session.
```

## Exit Codes

- `0`: `handoff_ready`, `handoff_needs_env_approval`, `handoff_needs_manual_readiness`, `handoff_launched`
- `10`: planning returned `needs_clarification`
- `21`: `blocked_guard_drift`
- `22`: `blocked_missing_branch`
- `23`: `blocked_action_required`
- `30`: unexpected helper failure
