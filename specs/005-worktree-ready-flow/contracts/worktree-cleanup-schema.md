# Contract: Worktree Cleanup Schema

Schema id: `worktree-cleanup/v1`

## Purpose

Defines the helper-emitted lifecycle contract for `scripts/worktree-ready.sh cleanup ...`.

Cleanup is not a readiness handoff. It reports lifecycle state for:

- linked worktree removal
- optional local branch deletion
- optional remote branch deletion
- merge-proof evidence used for safe remote deletion

## Required Fields

- `schema`
  - must equal `worktree-cleanup/v1`
- `phase`
  - must equal `cleanup`
- `boundary`
  - must equal `none`
- `final_state`
  - `cleanup_complete` or `cleanup_blocked`
- `worktree`
  - absolute resolved target path or `n/a`
- `preview`
  - path preview or `n/a`
- `branch`
  - resolved branch name or `n/a`
- `status`
  - `cleanup_complete` or `cleanup_blocked`
- `topology_state`
  - `clean`, `stale`, or `unknown`
- `worktree_action`
  - `removed`, `already_missing`, `blocked`, or `failed`
- `local_branch_action`
  - `deleted`, `already_missing`, `blocked`, or `not_requested`
- `remote_branch_action`
  - `deleted`, `already_missing`, `blocked`, or `not_requested`
- `merge_check`
  - `git_ancestor_local`
  - `git_ancestor_remote`
  - `github_pr_merged`
  - `github_pr_ambiguous`
  - `github_unavailable`
  - `missing_branch_tip`
  - `not_merged`
  - `not_requested`

## Optional Fields

- `default_branch`
  - resolved remote default branch when available
- `repair_command`
  - exact retry command when the helper blocks cleanup
- `next_<n>`
  - shell-safe next-step commands or manual verification steps
- `warning_<n>`
  - warnings that explain degraded or blocked cleanup state

## Behavioral Rules

- The helper must emit shell-safe `key=value` lines under `--format env`.
- Cleanup must be canonical-root-only for mutations. Non-canonical invocations must return `cleanup_blocked` with an exact canonical-root retry command.
- Worktree removal must be verified against `git worktree list --porcelain`; a successful `bd worktree remove` call alone is insufficient proof.
- Already-missing worktrees and branches are idempotent outcomes, not errors by themselves.
- Local branch deletion may use force-delete semantics only when the GitHub merged-PR fallback proves the exact branch tip was already merged through a squash/rebase workflow.
- Remote branch deletion must remain fail-closed unless merge safety is proven by git ancestry or the GitHub merged-PR fallback.
