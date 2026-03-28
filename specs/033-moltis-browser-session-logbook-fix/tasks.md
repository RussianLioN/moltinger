# Tasks: Moltis Browser Session And Telegram Logbook Containment

**Input**: Design documents from `/specs/033-moltis-browser-session-logbook-fix/`
**Prerequisites**: `spec.md`, `plan.md`

## Phase 0: Evidence And Scope

- [x] T001 Confirm this is a new post-merge slice and move the incident into a fresh worktree/branch from `main`
- [x] T002 Re-collect authoritative live evidence for Telegram timeout + activity-log leak + browser failure shape
- [x] T003 Re-check official Moltis/OpenClaw docs for browser automation, sandbox mode, Docker, and Pair semantics

## Phase 1: Repo-Side Carrier

- [x] T010 Create the Speckit package for `033-moltis-browser-session-logbook-fix`
- [x] T011 Add fail-closed browser failure taxonomy to `scripts/test-moltis-api.sh`
- [x] T012 Extend `scripts/moltis-browser-canary.sh` reject signatures for session death and pool exhaustion
- [x] T013 Add temporary Telegram degraded-mode guidance to `config/moltis.toml`
- [x] T014 Cover the changes with component/static tests

## Phase 2: Documentation And Prevention

- [x] T020 Record RCA for stale browser session + Telegram logbook leakage and clarify repo-owned vs upstream-owned fixes
- [x] T021 Record a concise consilium memo with Moltis/OpenClaw/browser operational recommendations
- [x] T022 Update runbook/rules/lessons with official-first sandbox and Pair guidance
- [x] T023 Prepare an upstream issue artifact with evidence and acceptance criteria

## Phase 3: Verification And Handoff

- [x] T030 Run targeted checks and reconcile `tasks.md`
- [ ] T031 Commit, rebase, push, and produce a concise handoff with checklist, solved problems, and remaining upstream gaps
