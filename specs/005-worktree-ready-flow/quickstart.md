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

## Scenario 4: Doctor mode

1. Run `/worktree doctor codex/gitops-metrics-fix`
2. Expect:
   - branch/worktree mapping
   - readiness status
   - any missing prerequisite
   - one exact recommended next action for each failing check

## Scenario 5: Opt-in terminal or Codex handoff

1. Run `/worktree attach codex/gitops-metrics-fix --handoff terminal`
2. Expect:
   - terminal automation only when explicitly requested
   - graceful fallback to manual commands if unsupported
3. Run `/worktree attach codex/gitops-metrics-fix --handoff codex`
4. Expect:
   - Codex launch in the target worktree when supported and safe
   - manual fallback instructions otherwise
