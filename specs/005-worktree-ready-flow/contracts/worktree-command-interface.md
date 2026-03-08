# Contract: Worktree Command Interface

## Supported Intents

- `/worktree`
- `/worktree start <issue-or-slug>`
- `/worktree start <slug-only>`
- `/worktree start --existing <branch>`
- `/worktree attach <branch>`
- `/worktree doctor <branch-or-path>`
- `/worktree finish <issue-or-branch>`
- `/worktree cleanup <issue-or-worktree> [--delete-branch]`
- `/worktree list`

## Intent Semantics

### `start`

- Creates a new worktree for a new task/branch workflow.
- May derive issue, slug, branch, and path automatically.
- May accept slug-only natural-language input without an issue id.
- Must consult live `git` state before deciding whether the request is a clean create, an attach/reuse, or an ambiguity that needs one short clarification.
- Must conclude with a readiness report and next-step handoff.

### `start --existing` / `attach`

- Creates a new worktree for an already existing branch.
- Must not imply creation of a new branch.
- Must detect when the branch is already attached to another worktree and report that path.

### `doctor`

- Evaluates an existing worktree or branch target.
- Must report readiness status plus exact next action for any failed probe.

## Handoff Flags

- `--handoff manual` (default)
- `--handoff terminal`
- `--handoff codex`

If explicit flags are not used, natural-language requests such as "открой в новой вкладке" or "сразу запусти codex" may map to the corresponding handoff mode.

## Output Block

```text
Worktree: <absolute-path>
Branch: <branch-name>
Issue: <issue-id-or-n/a>
Status: <created|needs_env_approval|ready_for_codex|action_required>
Next:
  1. <first exact step>
  2. <second exact step if needed>
```

## Behavioral Guarantees

- The final `Status` must reflect actual readiness, not just successful filesystem creation.
- `Next` must always contain at least one exact action when `Status` is not `ready_for_codex`.
- Manual handoff must remain available even if terminal/Codex automation is unsupported.
- Existing low-level `bd worktree` semantics remain valid under the hood.
- Slug-only start flows must derive a safe default branch/path template automatically.
- The workflow must not ask more than one clarification question when exact or similar-name collisions are detected.
