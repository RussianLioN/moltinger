# Quickstart: Worktree Ready UX

## Scenario 1: Existing branch, manual handoff

1. Run `/worktree attach codex/gitops-metrics-fix`
2. Expect:
   - new worktree path is shown
   - helper output includes `Boundary: stop_after_attach`
   - status is `needs_env_approval` or `ready_for_codex`
   - `Next` contains exact manual commands
   - the workflow stops at handoff and does not continue downstream work in the originating session

## Scenario 2: Existing branch with blocked environment

1. Run `/worktree attach codex/gitops-metrics-fix`
2. If `.envrc` approval is needed, expect:
   - status `needs_env_approval`
   - `Next` includes `cd <path>`, `direnv allow`, `codex`
3. After completing the recommended step, launching Codex should succeed without additional explanation from the assistant.

## Scenario 3: New task, new branch flow

1. Run `/worktree start BD-321 metrics-fix`
2. Expect:
   - branch and sanitized path are reported
   - session guard is refreshed
   - final output is a readiness report, not just a creation confirmation

## Scenario 4: One-shot slug-only clean start

1. Run `/worktree start remote-uat-hardening`
2. Expect:
   - no issue-id clarification when there are no conflicts
   - derived branch `feat/remote-uat-hardening`
   - derived path preview `../<repo>-remote-uat-hardening`
   - create flow continues automatically
   - final output is a readiness report, not just a creation confirmation

## Scenario 5: Similar-name ambiguity

1. Prepare a repo where a similar branch or worktree already exists, for example `feat/remote-uat-hardening-v2`
2. Run `/worktree start remote-uat-hardening`
3. Expect:
   - exactly one short clarification question
   - the clean-new option is explicitly shown
   - top similar candidates are surfaced without requiring the user to inspect `git worktree list`

## Scenario 6: Doctor mode

1. Run `/worktree doctor codex/gitops-metrics-fix`
2. Expect:
   - branch/worktree mapping
   - readiness status
   - any missing prerequisite
   - one exact recommended next action for each failing check

## Scenario 7: Stale registry during start flow

1. Create a topology change that is visible in live `git`, but leave `docs/GIT-TOPOLOGY-REGISTRY.md` stale
2. Run `/worktree start remote-uat-hardening`
3. Expect:
   - conflict detection still follows live `git`
   - helper report marks topology as stale
   - workflow refreshes registry after the mutation or returns the exact reconcile command if the refresh lock is busy

## Scenario 8: Opt-in terminal or Codex handoff

1. Run `/worktree attach codex/gitops-metrics-fix --handoff terminal`
2. Expect:
   - terminal automation only when explicitly requested
   - graceful fallback to manual commands if unsupported
3. Run `/worktree attach codex/gitops-metrics-fix --handoff codex`
4. Expect:
   - Codex launch in the target worktree when supported and safe
   - manual fallback instructions otherwise

## Scenario 9: Stop-and-handoff boundary after create

1. Run a request that both creates a worktree and describes downstream work, for example:
   - `Используй command-worktree и создай новый worktree pr17-webhook-extraction. После этого продолжи анализ PR из нового worktree.`
2. Expect:
   - managed create/attach flow completes first
   - helper output includes `Boundary: stop_after_create` or `Boundary: stop_after_attach`
   - helper output includes `Final State: ...`
   - the workflow stops at the handoff block and does not continue Phase B in the originating session
   - if `docs/GIT-TOPOLOGY-REGISTRY.md` changed in the invoking branch, the workflow lands and pushes that mutation before the handoff block

## Scenario 10: Machine-readable handoff contract

1. Run:
   - `scripts/worktree-ready.sh create --branch feat/remote-uat-hardening --path /tmp/demo --format env`
2. Expect:
   - `schema=worktree-handoff/v1`
   - `boundary=stop_after_create`
   - `final_state=<handoff_*|blocked_*>`
   - `pending=<short deferred summary>` when explicit downstream work was provided
   - `phase_b_seed_payload=<structured deferred payload>` when richer downstream context was provided
   - shell-safe `next_1`, `next_2`, and warnings if applicable

## Scenario 11: Manual next steps are copy-paste friendly

1. Run a managed create/attach flow with `manual` handoff.
2. Expect:
   - the human-facing response still contains the structured status block
   - exact next-step commands are also rendered in a fenced `bash` block
   - the user can copy the block without reconstructing commands from prose

## Scenario 12: Mixed request preserves downstream intent without breaking the boundary

1. Run a managed create/attach flow where the originating request also described explicit downstream work in the target worktree.
2. Expect:
   - the workflow still stops after Phase A
   - `Pending` contains a concise concrete deferred summary instead of generic placeholder text
   - if the request is long or structured, the helper preserves the richer deferred intent separately via `phase_b_seed_payload`
   - for manual handoff, the response treats the helper human output as canonical and may append a dedicated `Phase B Seed Payload (deferred, not executed)` block after the fenced `bash` block
   - the richer deferred payload preserves exact feature descriptions, defaults, boundaries, and stop conditions without claiming that Phase B already started

## Scenario 13: Attach flow preserves rich deferred payload

1. Run `/worktree attach codex/gitops-metrics-fix` together with a structured downstream request for the target worktree.
2. Expect:
   - helper output includes `Boundary: stop_after_attach`
   - the workflow still stops after Phase A
   - `Pending` stays short
   - the richer deferred Phase B intent is preserved separately and not collapsed into the short summary
