# Tasks: Moltis Skill Discovery And Telegram Leak Regressions

**Input**: Design documents from `/specs/034-moltis-skill-discovery-and-telegram-leak-regressions/`  
**Prerequisites**: `spec.md`, `plan.md`

## Phase 0: Evidence And Scope

- [x] T001 Confirm this is a new post-merge slice and move the incident into a fresh worktree/branch from current `main`
- [x] T002 Restore local Beads/worktree readiness in `034`
- [x] T003 Collect authoritative live evidence for `/api/skills`, `channels.list`, `chat.history`, `chat.raw_prompt`, and sandbox filesystem visibility
- [x] T004 Re-check official Moltis/OpenClaw docs and official issue surface before relying on community/secondary sources

## Phase 1: Spec And Backlog Baseline

- [x] T010 Create the Speckit package for `034-moltis-skill-discovery-and-telegram-leak-regressions`
- [x] T011 Record the product correction that `codex-update` cannot stay a remote-executable local-update skill on server-side Moltis surfaces
- [x] T012 Add deferred backlog for full `codex-update` redesign into advisory-only / notification-only remote-safe capability

## Phase 2: Repo-Owned Carrier

- [x] T020 Update `config/moltis.toml` guidance so Telegram capability/update answers do not use sandbox file probes as truth for skill availability
- [x] T021 Extend Telegram UAT/probe failure signatures for `Activity log`, host-path leakage, and false `codex-update` skill-missing replies
- [x] T022 Add or update targeted component/static coverage for the new regression gates

## Phase 3: Documentation, RCA, And Upstream Handoff

- [x] T030 Write RCA separating repo-owned causes from upstream prompt/runtime/sandbox mismatch and transport leakage
- [x] T031 Update rules/runbook/lessons with official-first guidance and remote-surface constraints for `codex-update`
- [x] T032 Prepare an upstream issue artifact with evidence and closure criteria

## Phase 4: Verification And Handoff

- [x] T040 Run targeted checks and reconcile `tasks.md`
- [x] T041 Commit, rebase, push, and produce concise handoff

## Deferred Follow-Up Backlog

- [ ] B001 Redesign `skills/codex-update` into a remote-safe advisory/notification capability that does not promise server-side execution of local Codex CLI update actions (`moltinger-main-034-moltis-skill-discovery-and-telegram-leak-regressions-0ph`)
- [ ] B002 Replace any user-facing contract that implies Moltis can update the user's local Codex installation from the remote server/container
- [ ] B003 When the `codex-update` slice is revisited, align it with the existing local Codex UX where new instances already offer local auto-update prompts at startup
