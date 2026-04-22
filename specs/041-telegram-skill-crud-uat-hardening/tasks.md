# Tasks: Telegram Skill CRUD UAT Hardening

**Input**: Design documents from `/specs/041-telegram-skill-crud-uat-hardening/`
**Prerequisites**: plan.md, spec.md

**Tests**: Targeted proof is based on `tests/component/test_telegram_remote_uat_contract.sh` plus syntax and doc-contract validation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel
- **[Story]**: User story reference (`US1`, `US2`, `US3`)

## Phase 0: Spec Alignment

- [x] T001 Create the Speckit package `specs/041-telegram-skill-crud-uat-hardening/` with `spec.md`, `plan.md`, and `tasks.md`

## Phase 1: User Story 1 - Authoritative Create/Update/Delete Verdicts (Priority: P1)

- [x] T010 [US1] Extend mutation intent classification in `scripts/telegram-e2e-on-demand.sh` to distinguish create, update, and delete turns
- [x] T011 [US1] Reuse baseline `/api/skills` verification in `scripts/telegram-e2e-on-demand.sh` for update/delete target checks before send
- [x] T012 [US1] Add post-reply semantic verification in `scripts/telegram-e2e-on-demand.sh` for update/delete target visibility transitions

## Phase 2: User Story 2 - Review-Safe Mutation Failure Taxonomy (Priority: P1)

- [x] T020 [US2] Add mutation-specific failure codes and diagnostic context in `scripts/telegram-e2e-on-demand.sh`
- [x] T021 [US2] Extend `tests/component/test_telegram_remote_uat_contract.sh` with positive and negative update/delete verdict coverage

## Phase 3: User Story 3 - Operator Documentation Matches Real Mutation Coverage (Priority: P2)

- [x] T030 [US3] Update `docs/telegram-e2e-on-demand.md` to document create/update/delete authoritative mutation coverage and safety limits

## Phase 4: Verification

- [x] T040 Run targeted validation for `scripts/telegram-e2e-on-demand.sh` and `tests/component/test_telegram_remote_uat_contract.sh`
- [x] T041 Reconcile `specs/041-telegram-skill-crud-uat-hardening/tasks.md` checkboxes with the actual implementation state
