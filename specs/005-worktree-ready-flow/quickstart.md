# Quickstart: Worktree Ready UX

## Scenario 1: Existing branch, manual handoff

1. Run `/worktree attach codex/gitops-metrics-fix`
2. Expect:
   - new worktree path is shown
   - status is `needs_env_approval` or `ready_for_codex`
   - `Next` contains exact manual commands

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
