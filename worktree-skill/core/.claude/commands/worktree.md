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
2. If an optional issue tracker is installed, pick the top ready issue from it.
3. If multiple equal candidates exist, ask one short clarification.
4. If one strong candidate exists, continue with `start` automatically.

Issue id regex: `[A-Za-z]+-[0-9]+`

## One-Shot Start Rules

Treat short requests like these as valid `start` flows:
- `/worktree remote-uat-hardening`
- `/worktree создай новый worktree remote-uat-hardening`
- `Используй command-worktree и создай новый worktree remote-uat-hardening`
- `/worktree start PROJ-123 telemetry-rollout`

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

When the request is clearly Speckit-oriented:
1. Treat create/start as Speckit-aware if either is true:
   - the user explicitly mentions Speckit/spec package/`/speckit.*`
   - the resolved issue title or description references a Speckit seed/package
2. In that path, do not derive `feat/...`.
3. Ask the helper for a numeric Speckit-compatible branch instead:
   - branch: `NNN-<slug>`
   - worktree dir: `../<repo>-NNN-<slug>`
4. Reuse an existing exact numeric branch if one already exists for the same short name.

## Helper Integration

Deterministic readiness, naming, and ambiguity detection are centralized in `scripts/worktree-ready.sh`.

Treat the helper as the source of truth whenever it is available:

```bash
scripts/worktree-ready.sh plan --slug <slug> [--issue <id>]
scripts/worktree-ready.sh plan --slug <slug> [--issue <id>] --speckit
scripts/worktree-ready.sh create --branch <branch> --path <path> --handoff manual
scripts/worktree-ready.sh attach --branch <existing-branch> --handoff manual
scripts/worktree-ready.sh doctor --branch <branch-or-path>
```

Helper responsibilities:
- deterministic branch/path derivation
- Speckit-aware numeric branch allocation when requested or implied by issue context
- exact worktree/branch detection
- similar-name discovery
- readiness status and next-step generation
- honest environment and handoff reporting
- machine-readable handoff contract for boundary-safe orchestration

Canonical readiness vocabulary:
- `created`
- `needs_env_approval`
- `ready_for_codex`
- `drift_detected`
- `action_required`

Canonical handoff final states:
- `handoff_ready`
- `handoff_needs_env_approval`
- `handoff_needs_manual_readiness`
- `handoff_launched`
- `blocked_guard_drift`
- `blocked_missing_branch`
- `blocked_action_required`

Planning decisions from `scripts/worktree-ready.sh plan`:
- `create_clean`
- `attach_existing_branch`
- `reuse_existing`
- `needs_clarification`

If `scripts/git-topology-registry.sh` exists:
- run `scripts/git-topology-registry.sh check` as a non-blocking preflight
- if registry is `stale`, do not block the start flow on the markdown snapshot
- use live `git` for collision detection and refresh the registry after the mutation

## Scope Boundary

`start`, `create`, and `attach` are **two-phase workflows**:

- **Phase A**: plan -> mutate -> reconcile -> classify -> emit handoff
- **Phase B**: downstream task work executed from the created worktree or an explicit handoff session

For `command-worktree`, you own **only Phase A**.

Rules:
- After a successful managed `create` or `attach`, stop after returning the helper handoff block.
- Do not continue the broader user task in the originating session.
- Do not claim "we are now working from the new worktree" unless the handoff actually launched a new session and the downstream work happens there.
- Do not prove the new context via `git -C ...`, path-targeted commands, or ad hoc `cd` in the old session.
- If the user asks for later work "из нового worktree", treat that as deferred Phase B and include it in `Pending`, not as permission to continue locally.
- If the user already described concrete downstream work, preserve that exact deferred intent in `Pending` instead of a generic placeholder.
- Mixed requests do not expand Phase A permissions. Treat downstream work as opaque deferred payload only.
- During Phase A, do not analyze, validate, decompose, or prepare the downstream work.
- During Phase A, do not create or update downstream artifacts, including Beads issues, GitHub issues, Linear issues, specs, plans, checklists, or implementation notes.
- Phase A may only: plan, sync base, create/attach the worktree, verify ancestry, refresh/land topology state, mark an already-resolved issue `in_progress`, and render or launch the handoff.
- If explicit `--handoff terminal` or `--handoff codex` is requested and succeeds, stop the current session immediately after reporting the launched handoff.
- If Phase A mutates `docs/GIT-TOPOLOGY-REGISTRY.md` in the invoking branch, land that mutation before the handoff block. Do not leave it as an unpushed local diff unless the user explicitly asked for a dirty local-only test flow.
- If a separate UAT worktree later needs reset/update and carries a newer `docs/GIT-TOPOLOGY-REGISTRY.md` snapshot, preserve/promote that snapshot into the owning branch before treating the UAT branch as disposable.

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
- Speckit-aware create:
  - `branch`: `NNN-<slug>`
  - `worktree dir`: `../<repo>-NNN-<slug>`

Process:
1. Verify git repository, invoking worktree, and canonical root worktree.
2. If `scripts/git-topology-registry.sh` exists in the invoking worktree, run `scripts/git-topology-registry.sh check` as a non-blocking preflight.
3. Parse the request into one of:
   - issue + slug
   - slug-only clean start
   - existing branch attach
4. For slug-only or ambiguous natural-language requests, run:
   - generic: `scripts/worktree-ready.sh plan --slug <slug> [--issue <id>]`
   - Speckit-aware: `scripts/worktree-ready.sh plan --slug <slug> [--issue <id>] --speckit`
   - If the user did not explicitly mention Speckit, but the resolved issue metadata references a Speckit seed/package, treat the plan as Speckit-aware anyway.
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
   - In Codex/App, keep this as its own approval step when escalation is required. Do not bundle it with create/refresh/handoff commands.
7. If issue id exists and the slug was omitted, derive the slug from the issue title using `bd show`, with `--no-db` fallback if needed.
8. Create or attach the worktree with beads integration:
   - new branch: use the deterministic executor instead of raw `bd worktree create`
     - `scripts/worktree-phase-a.sh create-from-base --canonical-root <canonical-root> --base-ref main --branch <branch> --path <absolute-worktree-path>`
   - existing local branch: create the worktree for that branch instead of inventing a new branch name
9. For new branches, ancestry verification is mandatory before any topology refresh:
   - if `scripts/worktree-phase-a.sh` reports that the branch already existed on the wrong commit, stop blocked
   - if the created worktree `HEAD` does not equal the resolved `main` commit, stop blocked
   - do not repair the branch in-place during Phase A
   - do not refresh topology, commit, or push after an ancestry mismatch
10. If `scripts/git-topology-registry.sh` exists in the invoking worktree or another already-known authoritative topology worktree, run `scripts/git-topology-registry.sh refresh --write-doc` from that worktree before any handoff so the topology mutation is captured immediately.
   - Do not assume `main` already contains the topology script before this feature is merged.
   - In Codex/App sessions, if the shared repo `.git` directory is outside the current writable sandbox, request approval/escalation for this refresh step before running it.
   - Keep the topology mutation phase separate from the base-sync phase when escalation is required: create/refresh/helper may be grouped together, but do not bundle them with the `fetch/switch/pull` step.
   - If refresh fails on topology lock, wait briefly and retry once.
   - If refresh reports that the shared topology state is not writable from the current session, stop and tell the user to re-run the same refresh command with approval/escalation from the authoritative topology worktree.
   - If it still fails, stop and report the exact reconcile command instead of continuing with extra mutations.
11. If the refresh changed committed files in the invoking branch, landing the plane is part of Phase A:
   - `git status --short docs/GIT-TOPOLOGY-REGISTRY.md`
   - if changed, run:
     - `git add docs/GIT-TOPOLOGY-REGISTRY.md`
     - `git commit -m "docs(topology): refresh registry after worktree mutation"`
     - `git pull --rebase`
     - `bd sync`
     - `git push`
   - If this landing sequence fails, stop and report the exact blocking command/result instead of continuing to handoff.
   - Treat the committed registry mutation as owned by the invoking branch, not by the target worktree branch.
   - Do not run a second refresh/commit/push cycle in the same Phase A run.
12. If issue id exists: `bd update <ISSUE_ID> --status in_progress`
   - if direct DB access fails in the current environment, retry with `bd update --no-db <ISSUE_ID> --status in_progress`
13. If the request contains explicit downstream work for the target worktree, extract it as `pending_summary` using the user's wording as closely as possible.
    - Keep it to one sentence.
    - Treat it as deferred payload, not as a task to reason about now.
    - Do not expand it into subtasks, rationale, diagnostics, recommendations, or new deliverables.
    - Normalize only pronouns or path references when needed for clarity.
14. If the helper exists, run:
   - `scripts/worktree-ready.sh create --branch <branch> --path <worktree-path> --issue <id> --handoff <manual|terminal|codex> [--pending-summary "<pending_summary>"]`
   - omit `--issue <id>` only when no issue id was resolved confidently
15. Return the helper stdout as the final manual-handoff reply.
16. For manual handoff, immediately follow the status block with a fenced `bash` block that contains only the exact next-step commands in order, one command per line.
    - If the helper detected issue-linked foundation files that exist only in the invoking branch or its upstream, the fenced `bash` block must include the exact bootstrap import command before `direnv allow` or `codex`.
17. If and only if the original request contained explicit downstream work, append exactly one fenced `text` block using this fixed template:
   ```text
   Phase B only.
   Worktree: <path>
   Branch: <branch>
   Task: <pending_summary>
   Phase A is complete. Do not repeat worktree setup. Do not create or update issues, specs, or plans unless explicitly requested in the target session.
   ```
18. Stop. Do not continue downstream task execution in the originating session.

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
- If a branch exists but no worktree is attached, route the user back into the managed attach flow instead of suggesting raw `bd worktree create`.
- Distinguish missing readiness state from unavailable probes: do not claim beads or guard are missing when the probe itself could not be executed.

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
   - if no issue id can be resolved confidently, print `Issue: n/a` and skip the close step
   - do not invent a follow-up issue or infer an unrelated issue from prose context
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
   - cleanup reports are lifecycle reports, not readiness handoffs
   - use `Status: cleanup_complete` on success
   - use `Status: cleanup_blocked` on failure

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
- Do not append speculative troubleshooting after a successful create/attach flow. Report only confirmed facts and exact next steps.

## Output Format

```text
Worktree: <absolute-path>
Preview: <path-preview>
Branch: <branch-name>
Issue: <id or n/a>
Status: <created|needs_env_approval|ready_for_codex|drift_detected|action_required>
Phase: <create|attach|doctor|handoff>
Boundary: <stop_after_create|stop_after_attach|stop_after_handoff|none>
Final State: <handoff_ready|handoff_needs_env_approval|handoff_needs_manual_readiness|handoff_launched|blocked_*>
Approval Required: <true|false>
Launch Command: <exact command when present>
Repair Command: <exact repair command when present>
Pending: <deferred downstream work after handoff>
Next:
  1. <first exact step>
  2. <second exact step if needed>
```

For manual handoff, also render:

```bash
cd /absolute/path
direnv allow
codex
```

If the request included explicit downstream work, append:

```text
Phase B only.
Worktree: <path>
Branch: <branch>
Task: <concrete deferred task>
Phase A is complete. Do not repeat worktree setup. Do not create or update issues, specs, or plans unless explicitly requested in the target session.
```

## Completion Rules

- Do not treat the workflow as complete until the final reply includes a readiness status from the canonical helper vocabulary.
- For `start`, `create`, and `attach`, do not treat the workflow as complete until the final reply includes a handoff boundary and final state from the helper contract.
- If the helper returns `ready_for_codex`, keep the response short and provide the direct launch command.
- If the helper returns `needs_env_approval`, the response must show `direnv allow` before any Codex launch step.
- If the helper returns `drift_detected` or `action_required`, the response must include the concrete corrective next step instead of a generic success message.
- Do not downgrade `ready_for_codex` or `needs_env_approval` back to a vague `created` summary in prose.
- Treat `Final State` as the authoritative terminal result for create/attach flows; `Status` is compatibility-only.
- For manual handoff, the final assistant message must end at the handoff block. Do not continue the user’s downstream task.
- If an optional `Phase B Seed Prompt` is rendered, it is advisory handoff metadata only. It must follow the fenced `bash` block and must not contain evidence that Phase B already executed.
- For `terminal` or `codex` handoff, if launch succeeds, report the launched handoff and stop. If launch fails, degrade to manual handoff and stop.
- If Phase A refreshed `docs/GIT-TOPOLOGY-REGISTRY.md`, explicitly state whether that managed diff was landed and pushed in the invoking branch.
- Do not ask the user to manually copy prose commands when a fenced `bash` block can be provided.
- For manual handoff, if the helper produced a human-readable handoff block, relay it verbatim. Do not restyle fields, collapse commands, convert fenced blocks back into prose, or prepend/append a second custom summary.
- If the helper surfaced `Bootstrap Source` and `Bootstrap Files`, keep them verbatim and preserve the corresponding `git checkout <source> -- ...` command inside the fenced `bash` block.
- For manual handoff, the final assistant reply must contain exactly:
  1. the helper status block
  2. one fenced `bash` block containing only the exact next-step commands, one command per line
  3. if explicit downstream work was provided, one fenced `text` block using the fixed `Phase B only` template
- Do not add lead-in prose, explanation, bullets, rationale, or commentary before the status block, between blocks, or after the final block.
- If the helper was run in human mode, its stdout is the canonical reply payload for manual handoff. Return that payload unchanged instead of reconstructing it from local notes.
- Never render commands or the seed prompt as unfenced plain text.
- The `Next:` list and the fenced `bash` block must contain the same commands in the same order.

## Manual Handoff Examples

Ready environment:

```text
Status: ready_for_codex
Next:
  1. cd /path/to/repo-remote-uat-hardening
  2. codex
```

```bash
cd /path/to/repo-remote-uat-hardening
codex
```

Blocked environment:

```text
Status: needs_env_approval
Next:
  1. cd /path/to/repo-remote-uat-hardening
  2. direnv allow
  3. codex
```

```bash
cd /path/to/repo-remote-uat-hardening
direnv allow
codex
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

If a managed create/cleanup flow successfully ran `scripts/git-topology-registry.sh refresh --write-doc`, explicitly say that the tracked diff in `docs/GIT-TOPOLOGY-REGISTRY.md` is expected in the invoking worktree until it is committed or discarded.
