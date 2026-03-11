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
- `base_ref`
- `base_sha`
- `worktree_action`
- `issue`
- `issue_title`
- `issue_artifact_count`
- `issue_artifact_<N>`
- `status`
- `topology_state`
- `env_state`
- `guard_state`
- `beads_state`
- `bootstrap_source`
- `bootstrap_file_count`
- `bootstrap_file_<N>`
- `launch_command`
- `repair_command`
- `requested_handoff`
- `pending`
- `phase_b_seed_payload`
- `next_count`
- `next_<N>`
- `warning_count`
- `warning_<N>`

## Notes

- `pending` is the concise one-sentence deferred Phase B summary when the originating request already described downstream work.
- `phase_b_seed_payload` is the richer deferred Phase B carrier for structured downstream intent such as exact feature descriptions, defaults, boundaries, and stop conditions.
- For manual handoff, the human-facing helper output remains canonical. It may render `Pending` plus a separate richer deferred payload block, but both must still preserve the hard Phase A stop boundary.

## Example

```text
schema=worktree-handoff/v1
phase=create
boundary=stop_after_create
decision=create_clean
base_ref=main
base_sha=0123456789abcdef
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
pending=Start\ Speckit\ for\ the\ OpenClaw\ Control\ Plane\ epic\ in\ the\ target\ worktree.
phase_b_seed_payload=Feature\ Description:\ Create\ a\ feature\ for\ hardening\ the\ command-worktree\ boundary.$'\n'Defaults:\ manual\ handoff\ remains\ default.$'\n'Stop\ Conditions:\ do\ not\ continue\ Phase\ B\ in\ the\ originating\ session.
bootstrap_source=origin/006-git-topology-registry
bootstrap_file_count=2
bootstrap_file_1=.beads/issues.jsonl
bootstrap_file_2=docs/plans/codex-cli-update-monitoring-speckit-seed.md
next_count=4
next_1=cd\ /Users/rl/coding/moltinger-remote-uat-hardening
next_2=git\ checkout\ origin/006-git-topology-registry\ --\ .beads/issues.jsonl\ docs/plans/codex-cli-update-monitoring-speckit-seed.md
next_3=direnv\ allow
next_4=codex
warning_count=1
warning_1=Environment\ approval\ is\ required\ before\ launching\ the\ session.
```

## Human Manual-Handoff Rendering

When `handoff_mode=manual`, the helper human output is the canonical operator payload. If `phase_b_seed_payload` is present, the human output may append a dedicated deferred block after the fenced `bash` block:

```text
Phase B Seed Payload (deferred, not executed).
Worktree: /Users/rl/coding/moltinger-remote-uat-hardening
Branch: feat/remote-uat-hardening
Pending Summary: Start Speckit for the OpenClaw Control Plane epic in the target worktree.
Payload:
Feature Description: Create a feature for hardening the command-worktree boundary.
Defaults: manual handoff remains default.
Stop Conditions: do not continue Phase B in the originating session.
Phase A is complete. Do not repeat worktree setup in the originating session.
```

## Exit Codes

- `0`: `handoff_ready`, `handoff_needs_env_approval`, `handoff_needs_manual_readiness`, `handoff_launched`
- `10`: planning returned `needs_clarification`
- `21`: `blocked_guard_drift`
- `22`: `blocked_missing_branch`
- `23`: `blocked_action_required`
- `30`: unexpected helper failure
