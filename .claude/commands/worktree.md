---
description: Smart worktree workflow with short natural-language start/finish flows for parallel development
argument-hint: "[start|finish|create|remove|list|cleanup] [issue-or-name] [optional text]"
---

# Worktree Command

Fast worktree lifecycle for Codex CLI/App with minimal typing.

This command supports:
- Empty input (`/worktree`) to suggest or auto-start from context.
- Natural language input (`/worktree создай для BD-123 auth`).
- Short explicit flows (`start`, `finish`, `cleanup`).
- Legacy compatibility (`create`, `remove`, `list`, `cleanup`).

## Quick Usage

```bash
/worktree
/worktree start BD-123 auth
/worktree finish BD-123
/worktree cleanup BD-123 --delete-branch
/worktree list
/worktree create auth
/worktree remove moltinger-bd-123-auth
```

## Intent Routing

Treat these as `start`:
- `start`, `create`, `new`, `begin`, `создай`, `сделай`, `начни`

Treat these as `finish`:
- `finish`, `close`, `done`, `ship`, `заверши`, `закрой`

If command is empty (`/worktree`):
1. Try to detect issue id from recent context or current branch.
2. If missing, run `bd ready` and pick the top ready issue.
3. If multiple equal candidates exist, ask one short clarification.
4. If one strong candidate exists, continue with `start` automatically.

Issue id regex: `[A-Za-z]+-[0-9]+`

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
2. If `scripts/git-topology-registry.sh` exists, run `scripts/git-topology-registry.sh doctor --prune` as a non-blocking preflight.
3. `git fetch origin`
4. `git switch main && git pull --rebase` (if `main` exists)
5. Build slug:
   - from explicit argument, else from issue title via `bd show <ISSUE_ID>`, else `task`
6. Create worktree with beads integration:
   - `bd worktree create ../<repo>-<issue-lower>-<slug> --branch <branch>`
7. If `scripts/git-topology-registry.sh` exists, run `scripts/git-topology-registry.sh refresh --write-doc` before entering the new worktree so the topology mutation is captured immediately.
8. Enter worktree.
9. If issue id exists: `bd update <ISSUE_ID> --status in_progress`
10. If script exists: `scripts/git-session-guard.sh --refresh`
11. Return short status block.

If the registry refresh fails, stop and report the exact command needed to reconcile it. Do not hand-edit `docs/GIT-TOPOLOGY-REGISTRY.md`.

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
8. If `scripts/git-topology-registry.sh` exists, run `scripts/git-topology-registry.sh check`
   - if stale, report: `Run /session-summary or scripts/git-topology-registry.sh refresh --write-doc from the authoritative worktree before ending the session`
9. `bd close <ISSUE_ID> --reason "<reason>"`
10. Print final status including push result and topology status.

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
4. If `scripts/git-topology-registry.sh` exists, run `scripts/git-topology-registry.sh refresh --write-doc`
5. Print cleanup report.

## Legacy Commands

- `create` -> alias to `start` without issue id.
- `remove` -> alias to `cleanup` (without branch delete).
- `list` -> run `bd worktree list`.
- `cleanup` -> as defined above.

## Safety Rules

- Never force-delete branches/worktrees unless user explicitly requests force.
- Never delete remote branch without merged check against `origin/main`.
- Stop and report on failed quality gates, rebase conflicts, or push failures.
- Keep output short and actionable.

## Output Format

```text
Worktree: <path>
Branch: <branch>
Issue: <id or n/a>
Status: <created|updated|finished|cleaned>
Next: <one short next action>
```
