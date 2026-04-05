# Tasks: Telegram Skill Detail Hardening

**Input**: Design documents from `/specs/040-telegram-skill-detail-hardening/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`

## Phase 0: Planning

- [x] T001 Consolidate official docs, upstream issue signals, and local consilium findings in `specs/040-telegram-skill-detail-hardening/research.md`
- [x] T002 Rank the first five general skill-detail hardening improvements for immediate implementation

## Phase 1: Runtime Contract

- [x] T010 [US2] Make `skill_detail` terminal in `scripts/telegram-safe-llm-guard.sh` by suppressing tool execution in `BeforeToolCall`

## Phase 2: Authoring Contract

- [x] T020 [US3] Add Telegram-safe skill-detail frontmatter contract to `skills/codex-update/SKILL.md`
- [x] T021 [US3] Add Telegram-safe skill-detail frontmatter contract to `skills/post-close-task-classifier/SKILL.md`
- [x] T022 [US3] Update `docs/moltis-skill-agent-authoring.md` with a general repo-managed skill-detail frontmatter rule

## Phase 3: Verification

- [x] T030 [US1] Extend `tests/component/test_telegram_safe_llm_guard.sh` with persisted `skill_detail` + Tavily suppression coverage
- [x] T031 [US1] Extend `tests/component/test_telegram_safe_llm_guard.sh` with clean skill-detail coverage for `codex-update`
- [x] T032 [US1] Extend `tests/component/test_telegram_safe_llm_guard.sh` with clean skill-detail coverage for `post-close-task-classifier`
- [x] T033 [US3] Add static skill-detail contract coverage in `tests/static/test_config_validation.sh`
- [x] T034 Run `bash tests/component/test_telegram_safe_llm_guard.sh`
- [x] T035 Run `bash tests/static/test_config_validation.sh`
- [ ] T036 Run authoritative Telegram UAT for a skill-detail prompt

## Phase 4: RCA And Landing

- [x] T040 Update RCA and lessons for the general skill-detail hardening root cause
- [ ] T041 Reconcile Beads state, commit, push, and record handoff
