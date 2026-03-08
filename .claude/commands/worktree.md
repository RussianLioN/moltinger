---
description: Smart worktree workflow with readiness-aware start/attach/doctor flows for parallel development
argument-hint: "[start|attach|doctor|finish|create|remove|list|cleanup] [issue-or-name] [optional text]"
---

# Worktree Command

Fast worktree lifecycle for Codex CLI/App with minimal typing.

This command supports:
- Empty input (`/worktree`) to suggest or auto-start from context.
- Natural language input (`/worktree создай для BD-123 auth`).
- Short explicit flows (`start`, `attach`, `doctor`, `finish`, `cleanup`).
- Legacy compatibility (`create`, `remove`, `list`, `cleanup`).

## Quick Usage

```bash
/worktree
/worktree start BD-123 auth
/worktree start --existing codex/gitops-metrics-fix
/worktree attach codex/gitops-metrics-fix
/worktree attach codex/gitops-metrics-fix --handoff codex
/worktree doctor codex/gitops-metrics-fix
/worktree finish BD-123
/worktree cleanup BD-123 --delete-branch
/worktree list
/worktree create auth
/worktree remove moltinger-bd-123-auth
```

## Intent Routing

Treat these as `start`:
- `start`, `create`, `new`, `begin`, `создай`, `сделай`, `начни`

Treat these as `attach`:
- `attach`, `existing`, `resume`, `подключи`, `для ветки`

Treat these as `doctor`:
- `doctor`, `check`, `status`, `проверь`, `диагностика`

Treat these as `finish`:
- `finish`, `close`, `done`, `ship`, `заверши`, `закрой`

If command is empty (`/worktree`):
1. Try to detect issue id from recent context or current branch.
2. If missing, run `bd ready` and pick the top ready issue.
3. If multiple equal candidates exist, ask one short clarification.
4. If one strong candidate exists, continue with `start` automatically.

Issue id regex: `[A-Za-z]+-[0-9]+`

## Helper Integration

Readiness, path normalization, and handoff generation are being centralized in `scripts/worktree-ready.sh`.

Treat the helper as the source of truth for readiness-aware status blocks whenever it is available:

```bash
scripts/worktree-ready.sh create --branch <branch> --path <path> --handoff manual
scripts/worktree-ready.sh attach --branch <existing-branch> --handoff manual
scripts/worktree-ready.sh doctor --branch <branch-or-path>
```

The command artifact continues to own natural-language routing. The helper owns deterministic path normalization, discovery, guard parsing, and readiness reporting.

Canonical readiness vocabulary:
- `created`
- `needs_env_approval`
- `ready_for_codex`
- `drift_detected`
- `action_required`

Until environment probes land, the helper may still report `Env: unknown` while using the canonical readiness vocabulary above.

Fallback rules:
- If the helper is unavailable, return a manual status block using the same readiness vocabulary.
- Manual handoff is always valid, even when `terminal` or `codex` automation is unsupported.
- Never hide a failed probe behind a generic "created" message.

## Start Workflow

Inputs:
- `ISSUE_ID` optional (recommended)
- `slug` optional free text (short task label)

Defaults:
- `base branch`: `main` (fallback: current default branch)
- `branch`: `feat/<issue-lower>-<slug>`
- `worktree dir`: `../<repo>-<issue-lower>-<slug>`

Process:
1. Verify git repository and project root.
2. `git fetch origin`
3. `git switch main && git pull --rebase` (if `main` exists)
4. Build slug:
   - from explicit argument, else from issue title via `bd show <ISSUE_ID>`, else `task`
5. Create worktree with beads integration:
   - `bd worktree create ../<repo>-<issue-lower>-<slug> --branch <branch>`
6. Enter worktree.
7. If issue id exists: `bd update <ISSUE_ID> --status in_progress`
8. If script exists: `scripts/git-session-guard.sh --refresh`
9. If helper exists, run:
   - `scripts/worktree-ready.sh create --branch <branch> --path <worktree-path> --handoff <manual|terminal|codex>`
10. If helper is unavailable, return a manual fallback status block with exact next steps.

For existing branches, prefer:
- `/worktree start --existing <branch>`
- `/worktree attach <branch>`

These flows should create or reuse a worktree for an already existing branch and then hand off to the helper for readiness output when available.

## Doctor Workflow

Usage:
- `/worktree doctor <branch-or-path>`

Intent:
1. Resolve the branch or worktree target.
2. Run the helper diagnostics flow:
   - `scripts/worktree-ready.sh doctor --branch <branch>`
   - or `scripts/worktree-ready.sh doctor --path <absolute-path>`
3. Return the helper report.
4. If the helper is unavailable, fall back to a manual status block with at least one exact next action.

## Finish Workflow

Inputs:
- `ISSUE_ID` optional (infer from branch if possible)
- optional close reason (default: `Done`)

Process:
1. Resolve issue id.
2. Run quality gate:
   - `bd preflight --check`
   - if unavailable, fallback to project default fast checks.
3. `bd sync`
4. If working tree has changes:
   - create commit message (short, include issue id)
   - `git add -A && git commit -m "..."`
5. `git pull --rebase`
6. `bd sync`
7. `git push -u origin <current-branch>`
8. `bd close <ISSUE_ID> --reason "<reason>"`
9. Print final status including push result.

Do not auto-delete branch/worktree in `finish` unless user explicitly asks `cleanup`.

## Cleanup Workflow

Usage:
- `/worktree cleanup <issue-or-worktree> [--delete-branch]`

Process:
1. Resolve target worktree name/path.
2. `bd worktree remove <name>` (safety checks enabled).
3. If `--delete-branch`:
   - verify branch is merged into `origin/main`
   - delete local + remote branch
4. Print cleanup report.

## Legacy Commands

- `create` -> alias to `start` without issue id.
- `remove` -> alias to `cleanup` (without branch delete).
- `list` -> run `bd worktree list`.
- `cleanup` -> as defined above.

## Safety Rules

- Never force-delete branches/worktrees unless user explicitly requests force.
- Never delete remote branch without merged check against `origin/main`.
- Stop and report on failed quality gates, rebase conflicts, or push failures.
- Prefer the helper status over ad hoc prose when both are available.
- Fall back to manual instructions if `terminal` or `codex` automation is unavailable.
- Keep output short and actionable.

## Output Format

```text
Worktree: <absolute-path>
Branch: <branch-name>
Issue: <id or n/a>
Status: <created|needs_env_approval|ready_for_codex|drift_detected|action_required>
Next:
  1. <first exact step>
  2. <second exact step if needed>
```

Optional helper detail lines may also include:
- `Env: <unknown|no_envrc|approval_needed|approved_or_not_required>`
- `Guard: <unknown|missing|ok|drift>`
- `Beads: <shared|redirected|missing>`
- `Handoff: <manual|terminal|codex>`
- `Warnings:`
