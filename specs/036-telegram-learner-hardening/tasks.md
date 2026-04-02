# Tasks: Telegram Learner Hardening

**Input**: Design documents from `/specs/036-telegram-learner-hardening/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`

## Phase 0: Planning

- [x] T001 Consolidate canonical project artifacts and upstream issue evidence for learner-skill hardening in `specs/036-telegram-learner-hardening/research.md`
- [x] T002 Synthesize at least 7 learner-skill improvements from consilium findings and rank the first five to implement now in `specs/036-telegram-learner-hardening/research.md`

## Phase 1: Thin Skill Contracts

- [x] T010 [US2] Rewrite `skills/telegram-learner/SKILL.md` as a thin official-first learner contract with explicit Telegram-safe summary, canonical runtime boundary and degraded mode
- [x] T011 [P] [US3] Create `skills/openclaw-improvement-learner/SKILL.md` as a similar learner skill for OpenClaw improvements/news regression coverage
- [x] T012 [P] [US3] Add official/community learner-authoring guidance artifact in `docs/research/2026-04-02-telegram-learner-official-community-guidance.md`
- [x] T013 [US2] Update `docs/moltis-skill-agent-authoring.md` with a short Telegram-safe learner-skill authoring pattern

## Phase 2: Runtime Reply Hygiene

- [x] T020 [US1] Refactor learner skill-detail rendering in `scripts/telegram-safe-llm-guard.sh` to produce concise value-first replies without workflow/operator markup
- [x] T021 [US1] Ensure typo resolution for `telegram-lerner` remains silent and the final reply uses only the canonical skill name

## Phase 3: Verification

- [x] T030 [US1] Update learner skill-detail coverage in `tests/component/test_telegram_safe_llm_guard.sh` for concise clean replies and negative checks on internal markup/leaks
- [x] T031 [P] [US3] Add component coverage for the new similar learner skill in `tests/component/test_telegram_safe_llm_guard.sh`
- [x] T032 Run `bash tests/component/test_telegram_safe_llm_guard.sh`
- [x] T033 Run `bash tests/component/test_telegram_remote_uat_contract.sh`
- [x] T034 Run `make codex-check`
- [ ] T035 Run authoritative Telegram UAT for `Расскажи мне про навык telegram-lerner`

## Phase 4: RCA And Landing

- [x] T040 Update RCA and lessons with the learner-skill authoring root cause and implemented hardening
- [ ] T041 Reconcile checkboxes, Beads statuses, commit, push and record final handoff
