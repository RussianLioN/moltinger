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

## Existing Branch Routing

When the input is `/worktree start --existing <branch>` or `/worktree attach <branch>`:
1. Treat the branch as pre-existing and do not derive a new branch name.
2. Resolve whether the branch exists locally before proposing a worktree action.
3. Derive a sanitized sibling-path preview from the branch name for user-facing output.
4. Ask `scripts/worktree-ready.sh` for the actual branch-to-worktree mapping.
5. If the branch is already attached elsewhere, prefer the reported existing path over the derived preview.
6. If the branch is missing locally, return `action_required` with one exact corrective next step instead of suggesting a low-level create command.

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

## Handoff Profiles

Supported handoff profiles:
- `manual` - always available; print copy-paste next steps only
- `terminal` - opt-in automation for opening a new Terminal.app session at the target worktree
- `codex` - opt-in automation for opening Terminal.app and launching `codex` in the target worktree

Behavior rules:
- Only attempt automatic handoff when the user explicitly asks for it via `--handoff ...` or equivalent natural-language intent.
- Keep `manual` as the default even on supported systems.
- Treat helper-selected fallback as authoritative. If the helper downgrades the request to `manual`, surface both the effective and requested handoff modes.

Platform limits:
- Automatic `terminal` and `codex` handoff are currently macOS-first and rely on `osascript` + `Terminal.app`.
- If `osascript` is unavailable, keep the requested profile visible and fall back to `manual`.
- `terminal` handoff requires a usable target path.
- `codex` handoff requires a usable target path, the `codex` CLI to be installed, and readiness status `ready_for_codex`.

Safety boundaries:
- Never run automatic handoff unless the user explicitly requested `--handoff terminal` or `--handoff codex`.
- Never auto-run `direnv allow` or any other trust-establishing environment command.
- Never claim success for automatic handoff if the helper had to fall back to `manual`.
- If readiness is degraded (`needs_env_approval`, `drift_detected`, `action_required`), prefer the exact corrective next step over automation.
- Preserve the low-level workflow for advanced users; handoff automation is additive, not mandatory.

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

Routing rules for these flows:
1. Do not translate them into the "new branch from main" workflow.
2. Do not invent a new branch name from the issue or slug.
3. Use the helper result as authoritative when the branch is already attached to another worktree.
4. Only fall back to `bd worktree create` when the branch exists locally and no existing attachment is reported.

Examples:

```text
/worktree attach codex/gitops-metrics-fix
Preview: ../moltinger-codex-gitops-metrics-fix
Worktree: /Users/rl/coding/moltinger-codex-gitops-metrics-fix
Status: created
Next:
  1. cd /Users/rl/coding/moltinger-codex-gitops-metrics-fix
  2. direnv allow # if prompted
  3. codex
```

```text
/worktree attach codex/full-review
Preview: ../moltinger-codex-full-review
Worktree: /Users/rl/.codex/worktrees/da4f/moltinger
Status: action_required
Next:
  1. cd /Users/rl/.codex/worktrees/da4f/moltinger
  2. Inspect the existing worktree and fix the reported prerequisites
```

## Doctor Workflow

Usage:
- `/worktree doctor <branch-or-path>`
- `/worktree doctor /absolute/path/to/worktree`
- `/worktree doctor` (fallback to the current branch or current repository context when possible)

Intent:
1. Resolve the branch or worktree target.
2. Run the helper diagnostics flow:
   - `scripts/worktree-ready.sh doctor --branch <branch>`
   - or `scripts/worktree-ready.sh doctor --path <absolute-path>`
3. Prefer a branch target when the user names a branch; prefer a path target when the user gives a path.
4. Return the helper report with branch mapping, beads state, guard state, environment state, and one exact next action for any failed probe.
5. If the helper is unavailable, fall back to a manual status block with at least one exact next action.

Related diagnostics rules:
- Use `doctor` for "why is this worktree not ready?" questions, not only for hard failures.
- If the named branch is already attached elsewhere, report the discovered path instead of the derived preview path.
- If the user is already inside the target worktree, `doctor` should work without forcing them to re-enter the path manually.
- Keep the result compact; prefer one corrective path over a long troubleshooting checklist.

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

## Completion Rules

- Do not treat the workflow as complete until the final reply includes a readiness status from the canonical helper vocabulary.
- If the helper returns `ready_for_codex`, keep the response short and provide the direct launch command.
- If the helper returns `needs_env_approval`, the response must show `direnv allow` before any Codex launch step.
- If the helper returns `drift_detected` or `action_required`, the response must include the concrete corrective next step instead of a generic success message.
- Do not downgrade `ready_for_codex` or `needs_env_approval` back to a vague `created` summary in prose.

## Manual Handoff Examples

Ready environment:

```text
Status: ready_for_codex
Next:
  1. cd /Users/rl/coding/moltinger-codex-gitops-metrics-fix && codex
```

Blocked environment:

```text
Status: needs_env_approval
Next:
  1. cd /Users/rl/coding/moltinger-codex-gitops-metrics-fix && direnv allow
  2. codex
```

Recovery guidance:

Occupied branch:

```text
/worktree attach codex/full-review
Worktree: /Users/rl/.codex/worktrees/da4f/moltinger
Status: action_required
Next:
  1. cd /Users/rl/.codex/worktrees/da4f/moltinger
  2. Inspect the existing worktree and fix the reported prerequisites
Warnings:
  - Branch 'codex/full-review' is already attached at /Users/rl/.codex/worktrees/da4f/moltinger
```

Guard drift during doctor:

```text
/worktree doctor /Users/rl/coding/moltinger-codex-gitops-metrics-fix
Status: drift_detected
Next:
  1. cd /Users/rl/coding/moltinger-codex-gitops-metrics-fix
  2. ./scripts/git-session-guard.sh --refresh
Warnings:
  - Guard probe detected branch/worktree drift for the target
```

Optional helper detail lines may also include:
- `Env: <unknown|no_envrc|approval_needed|approved_or_not_required>`
- `Guard: <unknown|missing|ok|drift>`
- `Beads: <shared|redirected|missing>`
- `Handoff: <manual|terminal|codex>`
- `Warnings:`
