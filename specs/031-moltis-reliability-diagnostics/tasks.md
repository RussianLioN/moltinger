# Tasks: Moltis Reliability Diagnostics and Runtime Guardrails

**Input**: Design documents from `/specs/031-moltis-reliability-diagnostics/`  
**Prerequisites**: plan.md, spec.md

## Phase 0: Planning And Evidence

- [x] P001 Read root and local instructions, memory/session context, and confirm the work stays in branch `031-moltis-reliability-diagnostics`
- [x] P002 Collect tracked facts for `config/moltis.toml`, prompts/context, skills bridge, tool-calling, browser/search, memory/vector storage, runtime constraints, and current guardrails
- [x] P003 Collect authoritative live evidence from production runtime, logs, and Telegram user-path probing
- [x] P004 Cross-check the intended baseline against official Moltis documentation before proposing fixes

---

## Phase 1: Speckit Package

- [x] T001 Create `specs/031-moltis-reliability-diagnostics/spec.md`
- [x] T002 Create `specs/031-moltis-reliability-diagnostics/plan.md`
- [x] T003 Create `specs/031-moltis-reliability-diagnostics/tasks.md`
- [x] T004 Record the root-cause matrix and classify issues into `misconfiguration`, `missing integration`, `bugs`, and `operational drift`
- [x] T005 Define the minimal safe remediation order and clearly separate deferred operational actions from repository-safe fixes

---

## Phase 2: Runtime Guardrails

- [x] T010 Add Moltis deploy/runtime contract verification for `/server`, repo skills visibility, runtime config mount source, and writable runtime config behavior
- [x] T011 Add targeted repository test coverage for the new runtime contract guardrails
- [x] T012 Reconcile `tasks.md` after the guardrail changes land

---

## Phase 3: Diagnostic Tooling

- [x] T020 Refresh `scripts/test-moltis-api.sh` to the current `/api/auth/*` and RPC contract
- [x] T021 Validate the refreshed smoke script with targeted checks
- [x] T022 Reconcile `tasks.md` after the diagnostic script changes land

---

## Phase 4: Deferred Operational Follow-Up

- [x] T030 Redeploy production so the tracked runtime contract is actually applied on the server
- [ ] T031 Clear or migrate stale session/model state that still references removed provider catalogs
- [ ] T032 Restore browser runtime health by fixing Docker access/connectivity on the target host
- [ ] T033 Stabilize Tavily search integration or replace it with a less fragile search path
- [ ] T034 Configure repository-visible memory watch/index scope and backfill embeddings for useful vector memory
- [ ] T035 Clean stale runtime context files in `~/.moltis` that conflict with the current project/runtime identity

## Dependencies & Execution Order

- Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4
- Phase 2 and Phase 3 are the only repository-safe implementation phases in this slice.
- Phase 4 depends on operator action against the shared remote runtime after repository guardrails are merged.

## Implementation Strategy

- First freeze the diagnosis into Speckit artifacts so the repair path is evidence-based.
- Then prevent future silent drift by hardening deploy/runtime verification.
- Then refresh the operator smoke diagnostic so it tests the current Moltis API surface instead of stale endpoints.
- Leave live runtime repair, session cleanup, and memory/browser operational work as explicit follow-up actions.
