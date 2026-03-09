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
- Must conclude with a readiness report, machine-readable handoff contract, and a hard stop boundary.
- Must split mixed requests into:
  - **Phase A**: prepare worktree, refresh topology, classify readiness, emit handoff
  - **Phase B**: deferred downstream work executed only from the created worktree or an explicit handoff session
- For clean-create flows, Phase A must resolve an explicit `base_ref` and `base_sha` before creating the branch.
- Phase A must verify the new worktree `HEAD` equals the resolved `base_sha` before topology refresh or any landing-the-plane mutation.

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

## Stop-and-Handoff Boundary

- `start`, `create`, and `attach` are **boundary commands**.
- After the managed create/attach flow completes, the command must stop after returning a handoff block.
- The originating session must not continue the broader user task after this point unless the user explicitly overrides the boundary.
- Requests that say "работай из нового worktree", "там подтверди cwd/branch", or "после перехода продолжи" must still stop after Phase A unless a supported automatic handoff actually launches.
- Mixed requests do not expand Phase A permissions.
- During Phase A, the command must not create or update downstream artifacts such as Beads issues, specs, plans, checklists, or implementation notes.

## Output Block

```text
Worktree: <absolute-path>
Branch: <branch-name>
Issue: <issue-id-or-n/a>
Status: <created|needs_env_approval|ready_for_codex|action_required>
Boundary: <stop_after_create|stop_after_attach|stop_after_handoff|none>
Final State: <handoff_ready|handoff_needs_env_approval|handoff_needs_manual_readiness|handoff_launched|blocked_*>
Next:
  1. <first exact step>
  2. <second exact step if needed>
```

## Machine-Readable Contract

- `scripts/worktree-ready.sh` must support `--format env`.
- For `create`, `attach`, and `handoff`, the helper emits shell-safe `key=value` lines with schema `worktree-handoff/v1`.
- The command workflow may use this contract for automation, but even without machine parsing the human-facing behavior must respect the same boundary.

## Behavioral Guarantees

- The final `Status` must reflect actual readiness, not just successful filesystem creation.
- `Final State` is authoritative for boundary decisions; `Status` is retained for legacy human compatibility.
- `Next` must always contain at least one exact action when `Status` is not `ready_for_codex`.
- Manual handoff must remain available even if terminal/Codex automation is unsupported.
- Existing low-level `bd worktree` semantics remain valid under the hood.
- Slug-only start flows must derive a safe default branch/path template automatically.
- The workflow must not ask more than one clarification question when exact or similar-name collisions are detected.
- The command must not prove "we are already in the new worktree" via `git -C` or path-targeted commands from the originating session.
- If the originating request already contains explicit downstream work, `Pending` should preserve that concrete deferred intent instead of generic placeholder text.
- A manual handoff MAY append an optional `Phase B Seed Prompt` block after the fenced `bash` block, but it must remain advisory and must not imply that Phase B already started.
- Clean-create flows must be single-pass: one ancestry verification, one topology refresh, and at most one invoking-branch landing cycle.
