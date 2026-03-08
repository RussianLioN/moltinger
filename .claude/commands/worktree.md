---
description: Smart worktree workflow with one-shot start/attach/doctor flows for parallel development
argument-hint: "[start|attach|doctor|finish|create|remove|list|cleanup] [issue-or-name] [optional text]"
---

# Worktree Command

Fast worktree lifecycle for Codex CLI/App with minimal typing, honest readiness handoff, and topology-aware conflict detection.

## Codex Note

- In Claude-style clients, examples below use `/worktree`.
- In Codex CLI, invoke this workflow via the bridged skill `command-worktree`.
- If the user says "используй навык worktree" or asks to create/open/check a worktree in plain language, map that request to `command-worktree`.
- Do not assume `/worktree` is registered as a native Codex slash command.

## Quick Usage

```bash
/worktree
/worktree start BD-123 auth
/worktree start remote-uat-hardening
/worktree attach codex/gitops-metrics-fix
/worktree doctor codex/gitops-metrics-fix
/worktree finish BD-123
/worktree cleanup BD-123 --delete-branch
/worktree list
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

## One-Shot Start Rules

Treat short requests like these as valid `start` flows:
- `/worktree remote-uat-hardening`
- `/worktree создай новый worktree remote-uat-hardening`
- `Используй command-worktree и создай новый worktree remote-uat-hardening`
- `/worktree start moltinger-dmi telegram-webhook-rollout`

When the user gives a slug without an issue id:
1. Do not ask for an issue id just to satisfy a template.
2. Derive a clean proposal automatically:
   - branch: `feat/<slug>`
   - worktree dir: `../<repo>-<slug>`
3. Check for exact or similar conflicts before mutating git state.
4. Ask one short clarification only if the request is genuinely ambiguous.

When the user gives an issue id and slug:
1. Use the issue-aware template:
   - branch: `feat/<issue-lower>-<slug>`
   - worktree dir: `../<repo>-<issue-short>-<slug>`
2. If the issue title lookup is needed and `bd show <ISSUE_ID>` fails because SQLite is readonly/locked/unavailable, retry with `bd show --no-db <ISSUE_ID>` from the canonical root worktree.

## Helper Integration

Deterministic readiness, naming, and ambiguity detection are centralized in `scripts/worktree-ready.sh`.

Treat the helper as the source of truth whenever it is available:

```bash
scripts/worktree-ready.sh plan --slug <slug> [--issue <id>]
scripts/worktree-ready.sh create --branch <branch> --path <path> --handoff manual
scripts/worktree-ready.sh attach --branch <existing-branch> --handoff manual
scripts/worktree-ready.sh doctor --branch <branch-or-path>
```

Helper responsibilities:
- deterministic branch/path derivation
- exact worktree/branch detection
- similar-name discovery
- readiness status and next-step generation
- honest environment and handoff reporting

Canonical readiness vocabulary:
- `created`
- `needs_env_approval`
- `ready_for_codex`
- `drift_detected`
- `action_required`

Planning decisions from `scripts/worktree-ready.sh plan`:
- `create_clean`
- `attach_existing_branch`
- `reuse_existing`
- `needs_clarification`

If `scripts/git-topology-registry.sh` exists:
- run `scripts/git-topology-registry.sh check` as a non-blocking preflight
- if registry is `stale`, do not block the start flow on the markdown snapshot
- use live `git` for collision detection and refresh the registry after the mutation

## Start Workflow

Inputs:
- `ISSUE_ID` optional
- `slug` optional free text
- optional handoff intent from natural language or `--handoff`

Defaults:
- `base branch`: `main` (fallback: current default branch)
- with issue id:
  - `branch`: `feat/<issue-lower>-<slug>`
  - `worktree dir`: `../<repo>-<issue-short>-<slug>`
- without issue id:
  - `branch`: `feat/<slug>`
  - `worktree dir`: `../<repo>-<slug>`

Process:
1. Verify git repository, invoking worktree, and canonical root worktree.
2. If `scripts/git-topology-registry.sh` exists in the invoking worktree, run `scripts/git-topology-registry.sh check` as a non-blocking preflight.
3. Parse the request into one of:
   - issue + slug
   - slug-only clean start
   - existing branch attach
4. For slug-only or ambiguous natural-language requests, run:
   - `scripts/worktree-ready.sh plan --slug <slug> [--issue <id>]`
5. Interpret the helper plan:
   - `create_clean`: continue automatically with the proposed branch and worktree path
   - `attach_existing_branch`: continue automatically with an existing-branch flow for that branch
   - `reuse_existing`: do not create a duplicate; report the existing path and next step
   - `needs_clarification`: ask exactly one short question that includes:
     - the clean new branch option
     - the top similar candidates
6. Refresh the base branch from the canonical root worktree using this exact sequence:
   - `git -C <canonical-root> fetch origin`
   - `git -C <canonical-root> branch --show-current`
   - if the canonical root is not already on `main`, run `git -C <canonical-root> switch main`
   - `git -C <canonical-root> pull --rebase`
   - Do not run `git pull --rebase origin main` for this workflow; rely on the configured upstream of `main`.
7. If issue id exists and the slug was omitted, derive the slug from the issue title using `bd show`, with `--no-db` fallback if needed.
8. Create or attach the worktree with beads integration:
   - new branch: `bd worktree create ../<repo>-<suffix> --branch <branch>`
   - existing local branch: create the worktree for that branch instead of inventing a new branch name
9. If `scripts/git-topology-registry.sh` exists in the invoking worktree or another already-known authoritative topology worktree, run `scripts/git-topology-registry.sh refresh --write-doc` from that worktree before entering the new worktree so the topology mutation is captured immediately.
   - Do not assume `main` already contains the topology script before this feature is merged.
   - If refresh fails on topology lock, wait briefly and retry once.
   - If it still fails, stop and report the exact reconcile command instead of continuing with extra mutations.
10. Enter the target worktree.
11. If issue id exists: `bd update <ISSUE_ID> --status in_progress`
   - if direct DB access fails in the current environment, retry with `bd update --no-db <ISSUE_ID> --status in_progress`
12. If `scripts/git-session-guard.sh` exists, run `scripts/git-session-guard.sh --refresh`
13. If the helper exists, run:
   - `scripts/worktree-ready.sh create --branch <branch> --path <worktree-path> --handoff <manual|terminal|codex>`
14. Return the helper status block.

Handoff default:
- Default to `manual`.
- Do not choose `--handoff codex` or `--handoff terminal` just because the user is already inside Codex or Terminal.
- Only select `terminal` or `codex` handoff when the user explicitly asks to open a terminal, launch Codex, or continue immediately in the new worktree.

Rules for ambiguity:
- Do not ask the user to restate the whole request.
- Do not ask about branch naming if the helper already produced a safe default.
- Only ask a question when exact/remote/similar-name collisions make an automatic choice risky.
- The clarification question must offer a clean new branch option explicitly.

## Existing Branch Routing

When the input is `/worktree start --existing <branch>` or `/worktree attach <branch>`:
1. Treat the branch as pre-existing and do not derive a new branch name.
2. Resolve whether the branch exists locally before proposing a worktree action.
3. Derive a sanitized sibling-path preview from the branch name for user-facing output.
4. Ask `scripts/worktree-ready.sh` for the actual branch-to-worktree mapping.
5. If the branch is already attached elsewhere, prefer the reported existing path over the derived preview.
6. If the branch is missing locally, return `action_required` with one exact corrective next step instead of suggesting a low-level create command.

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
8. If `scripts/git-topology-registry.sh` exists, run `scripts/git-topology-registry.sh check`
   - if stale, report: `Run command-session-summary or scripts/git-topology-registry.sh refresh --write-doc from the authoritative worktree before ending the session`
9. `bd close <ISSUE_ID> --reason "<reason>"`
   - if direct DB access fails in the current environment, retry with `bd close --no-db <ISSUE_ID> --reason "<reason>"`
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
- Prefer helper output over ad hoc prose when the helper is available.
- If topology registry is stale, treat live `git` as authoritative for conflict detection and refresh the registry after the mutation.
- Fall back to manual instructions if `terminal` or `codex` automation is unavailable.
- Keep output short and actionable.

## Output Format

```text
Worktree: <absolute-path>
Preview: <path-preview>
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
  1. cd /Users/rl/coding/moltinger-remote-uat-hardening && codex
```

Blocked environment:

```text
Status: needs_env_approval
Next:
  1. cd /Users/rl/coding/moltinger-remote-uat-hardening && direnv allow
  2. codex
```

Ambiguous naming:

```text
Question: Нашёл похожие линии. Создать чистую ветку feat/remote-uat-hardening или продолжить одну из существующих: codex/full-review, feat/remote-uat-hardening-v2?
```

Optional helper detail lines may also include:
- `Topology: <ok|stale|unavailable>`
- `Env: <unknown|no_envrc|approval_needed|approved_or_not_required>`
- `Guard: <unknown|missing|ok|drift>`
- `Beads: <shared|redirected|missing>`
- `Handoff: <manual|terminal|codex>`
- `Warnings:`
