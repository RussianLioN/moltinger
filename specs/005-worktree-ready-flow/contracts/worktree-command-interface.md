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
- Must obey the same hard stop-after-Phase-A boundary as clean-create flows.
- Must not continue downstream task execution in the originating session after a successful attach handoff.

### `doctor`

- Evaluates an existing worktree or branch target.
- Must report readiness status plus exact next action for any failed probe.

### `cleanup`

- Removes an existing linked worktree through a helper-backed lifecycle flow.
- Must run from the canonical root worktree; linked worktrees may diagnose the target but must block the mutation and print the exact canonical-root retry command.
- Must treat `scripts/worktree-ready.sh cleanup ...` as the source of truth for lifecycle status, next steps, and exit code.
- Must remove worktrees through plain `bd worktree remove <absolute-path>` and verify disappearance through `git worktree list --porcelain`.
- Must treat already-missing worktrees or already-missing branches as idempotent outcomes, not opaque failures.
- When `--delete-branch` is requested, must prove merge safety with git ancestry first and may use a GitHub merged-PR fallback only when git ancestry is inconclusive and the authenticated repo metadata matches the same branch, base branch, and head SHA.
- When the GitHub fallback proves a squash/rebase merged branch, local branch deletion may require force-delete semantics because `git branch -d` still evaluates plain ancestry.
- Must block remote branch deletion when neither git nor GitHub can prove the branch was safely merged.

## Handoff Flags

- `--handoff manual` (default)
- `--handoff terminal`
- `--handoff codex`

If explicit flags are not used, natural-language requests such as "открой в новой вкладке" or "сразу запусти codex" may map to the corresponding handoff mode.

## Stop-and-Handoff Boundary

- `start`, `create`, and `attach` are **boundary commands**.
- After the managed create/attach flow completes, the command must stop after returning a handoff block.
- The originating session must not continue the broader user task after this point unless a supported launched handoff session actually takes over.
- Requests that say "работай из нового worktree", "там подтверди cwd/branch", or "после перехода продолжи" must still stop after Phase A unless a supported automatic handoff actually launches.
- Mixed requests do not expand Phase A permissions.
- During Phase A, the command must not create or update downstream artifacts such as Beads issues, specs, plans, checklists, or implementation notes.
- Manual handoff remains the default boundary-safe mode.

## Output Block

```text
Worktree: <absolute-path>
Branch: <branch-name>
Issue: <issue-id-or-n/a>
Status: <created|needs_env_approval|ready_for_codex|action_required>
Boundary: <stop_after_create|stop_after_attach|stop_after_handoff|none>
Final State: <handoff_ready|handoff_needs_env_approval|handoff_needs_manual_readiness|handoff_launched|blocked_*>
Pending: <one-sentence deferred Phase B summary>
Next:
  1. <first exact step>
  2. <second exact step if needed>
```

`Pending` is a short summary carrier only. It must stay concise even when the original downstream request is long and structured.

When the originating request contains richer deferred Phase B intent, the canonical manual handoff payload may also append a separate fenced `text` block:

```text
Phase B Seed Payload (deferred, not executed).
Worktree: <absolute-path>
Branch: <branch-name>
Pending Summary: <same short summary as Pending>
Payload:
<exact richer deferred Phase B seed payload>
Phase A is complete. Do not repeat worktree setup in the originating session.
```

## Machine-Readable Contract

- `scripts/worktree-ready.sh` must support `--format env`.
- For `create`, `attach`, and `handoff`, the helper emits shell-safe `key=value` lines with schema `worktree-handoff/v1`.
- For `cleanup`, the helper emits shell-safe `key=value` lines with schema `worktree-cleanup/v1`; see `contracts/worktree-cleanup-schema.md`.
- The command workflow may use this contract for automation, but even without machine parsing the human-facing behavior must respect the same boundary.
- `pending` remains the concise summary carrier.
- `phase_b_seed_payload` is a distinct richer deferred-intent carrier when the originating request includes structured Phase B details.
- For manual handoff, the helper human output is canonical. The command must relay that payload unchanged instead of rebuilding it locally.

## Behavioral Guarantees

- The final `Status` must reflect actual readiness, not just successful filesystem creation.
- `Final State` is authoritative for boundary decisions; `Status` is retained for legacy human compatibility.
- `Next` must always contain at least one exact action when `Status` is not `ready_for_codex`.
- Manual handoff must remain available even if terminal/Codex automation is unsupported.
- Existing low-level `bd worktree` semantics remain valid under the hood.
- Slug-only start flows must derive a safe default branch/path template automatically.
- The workflow must not ask more than one clarification question when exact or similar-name collisions are detected.
- The command must not prove "we are already in the new worktree" via `git -C` or path-targeted commands from the originating session.
- If the originating request already contains explicit downstream work, `Pending` should preserve a concise concrete deferred summary instead of generic placeholder text.
- Richer downstream constraints, exact feature descriptions, defaults, and stop conditions must be preserved separately via `phase_b_seed_payload` or equivalent helper-rendered deferred payload block instead of being collapsed into `Pending`.
- A manual handoff MAY append a `Phase B Seed Payload (deferred, not executed)` block after the fenced `bash` block, but it must remain advisory and must not imply that Phase B already started.
- Clean-create flows must be single-pass: one ancestry verification, one topology refresh, and at most one invoking-branch landing cycle.
- Cleanup flows must remain lifecycle-only: no handoff boundary, no downstream task execution, and no auto-publication of the topology registry markdown snapshot.
- Cleanup flows must fail closed for remote branch deletion when merged proof is unavailable, contradictory, or repository metadata cannot be authenticated.
