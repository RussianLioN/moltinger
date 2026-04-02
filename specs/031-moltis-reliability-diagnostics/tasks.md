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
- [x] T023 Add a read-only Tavily/memory diagnostic script that summarizes tracked search/memory contract plus optional runtime-log failure taxonomy
- [x] T024 Validate the new diagnostic script with targeted repository coverage
- [x] T025 Reconcile `tasks.md` after the search/memory diagnostic additions land

---

## Phase 4: Highest-Priority Live Reliability Follow-Up

- [x] T030 Redeploy production so the tracked runtime contract is actually applied on the server
- [x] T031 Clear or migrate stale session/model state that still references removed provider catalogs
- [x] T032 [P0] Stabilize Tavily search integration or replace it with a less fragile search path; include dedicated health proof beyond transport-green deploy/UAT
- [x] T033 [P0] Arrest `memory_search` embedding-provider failures by pinning a deterministic memory contract or explicit keyword-only fallback before broader memory rollout
- [x] T034 Restore browser runtime health by fixing Docker access/connectivity on the target host
- [x] T035 Configure repository-visible memory watch/index scope and backfill embeddings for useful vector memory after the provider contract is deterministic
- [x] T036 Clean stale runtime context files in `~/.moltis` that conflict with the current project/runtime identity

---

## Phase 5: Architectural Hardening Backlog

- [x] T040 Record the config/auth/session durability consilium and capture the architectural hardening backlog in tracked artifacts
- [x] T041 Make `scripts/render-moltis-env.sh` fail closed on empty required auth and provider secrets and cover it with targeted tests
- [x] T042 Pin production `MOLTIS_RUNTIME_CONFIG_DIR` to the canonical runtime path or an explicit allowlist and validate that exact path during deploy
- [x] T043 Reconcile auth ownership across `config/moltis.toml`, secrets docs, deploy workflow, preflight, and runtime strategy including `MOLTINGER_SERVICE_TOKEN` and Telegram allowlist source of truth
- [x] T044 Upgrade deploy and smoke proof from transport green to canonical provider/model proof including `openai-codex::gpt-5.4` and restart survival
- [x] T045 Add explicit session reconcile/reset automation and runbook gates after provider/catalog recovery for Telegram and UI sessions
- [x] T046 Audit and preserve durable runtime state outside tracked config, including `~/.moltis`, with a manifest or contract suitable for backup/restore validation
- [x] T047 Expand authoritative UAT semantics for `/status`, wrong-target chat, verification-gate replies, and exercised-surface matrices for browser/search/repo-context paths
- [x] T048 Design immutable production release roots plus runtime attestation/drift detection so runtime provenance cannot silently fall off tracked intent

---

## Phase 6: Embedding And Ollama Root-Cause Closure

- [x] T050 Reconcile Speckit artifacts for the `memory_search` / missing Ollama provider incident and encode the runtime-config parity + `OLLAMA_API_KEY` hypotheses
- [x] T051 Forward `OLLAMA_API_KEY` into the production `moltis` container and add static coverage for the contract
- [x] T052 Extend deploy verification and runtime attestation so stale writable `moltis.toml` fails closed against tracked `config/moltis.toml`
- [x] T053 Add or update component/static coverage for runtime-config parity enforcement
- [x] T054 Record RCA, consilium, and an explicit rule for embedding/runtime drift; rebuild lessons index
- [x] T055 Prepare a runtime-only `PR1` carrier for `main` that includes only the embedding/Ollama fix path plus blocking verification lanes
- [x] T056 Merge `PR1` into `main`, run the canonical production deploy from `main`, and validate live `memory_search` plus Ollama provider/model availability against the authoritative remote runtime
- [x] T057 Only after successful live verification, land `PR2` via a fresh docs-only carrier from verified `main` with RCA/consilium/rules/runbook/lessons/spec updates and then reconcile `tasks.md`

---

## Phase 7: Telegram Same-Turn Iteration Drift

- [x] T058 Capture live hook audit/capture evidence for repeated `BeforeLLMCall` after a direct Telegram skill-detail fastpath and confirm whether suppression is being misclassified as a new user turn
- [x] T059 Fix repeated same-turn `BeforeLLMCall` handling so `iteration>1` keeps suppression alive and does not trigger a second direct-send
- [x] T060 Add regression coverage for the `iteration=2` duplicate-delivery pattern and validate the updated Telegram guard contract before redeploy

## Dependencies & Execution Order

- Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5
- Phase 6 depends on the existing runtime-attestation hardening from Phase 5 and now lands through `PR1 -> main deploy -> PR2` rather than direct feature-branch rollout.
- Phase 7 depends on the Telegram direct-fastpath/live-capture evidence already established earlier in this slice.
- Phase 2 and Phase 3 are the only repository-safe implementation phases in this slice.
- Phase 4 depends on operator action against the shared remote runtime after repository guardrails are merged.
- Phase 5 is a follow-up hardening backlog informed by the completed diagnosis and consilium, not a promise to land all items in this slice.
- Phase 6 returns to an operator-driven live fix, but only after the runtime-only `PR1` is merged to `main` and deployed through the canonical production workflow.
- Phase 7 is another live-root-cause closure step for Telegram reliability and should also finish with authoritative remote proof rather than local-only green tests.

## Implementation Strategy

- First freeze the diagnosis into Speckit artifacts so the repair path is evidence-based.
- Then prevent future silent drift by hardening deploy/runtime verification.
- Then refresh the operator smoke diagnostic so it tests the current Moltis API surface instead of stale endpoints.
- Leave live runtime repair, session cleanup, and memory/browser operational work as explicit follow-up actions.
- Use Phase 5 backlog items to drive the next durability-focused slice once the current operational backlog is under control.
- Close the embedding/Ollama incident by first preparing a minimal `PR1` for `main`, then proving the live runtime consumes the tracked memory contract and receives the Ollama cloud credential needed for provider discovery, and only after that landing the deferred `PR2` documentation layer.
- For Telegram direct fastpaths, treat repeated `BeforeLLMCall` iterations as a separate reliability class from late `AfterLLMCall`/`MessageSending` tails and require live evidence for both.
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
- [x] T023 Add a read-only Tavily/memory diagnostic script that summarizes tracked search/memory contract plus optional runtime-log failure taxonomy
- [x] T024 Validate the new diagnostic script with targeted repository coverage
- [x] T025 Reconcile `tasks.md` after the search/memory diagnostic additions land

---

## Phase 4: Highest-Priority Live Reliability Follow-Up

- [x] T030 Redeploy production so the tracked runtime contract is actually applied on the server
- [x] T031 Clear or migrate stale session/model state that still references removed provider catalogs
- [x] T032 [P0] Stabilize Tavily search integration or replace it with a less fragile search path; include dedicated health proof beyond transport-green deploy/UAT
- [x] T033 [P0] Arrest `memory_search` embedding-provider failures by pinning a deterministic memory contract or explicit keyword-only fallback before broader memory rollout
- [x] T034 Restore browser runtime health by fixing Docker access/connectivity on the target host
- [x] T035 Configure repository-visible memory watch/index scope and backfill embeddings for useful vector memory after the provider contract is deterministic
- [x] T036 Clean stale runtime context files in `~/.moltis` that conflict with the current project/runtime identity

---

## Phase 5: Architectural Hardening Backlog

- [x] T040 Record the config/auth/session durability consilium and capture the architectural hardening backlog in tracked artifacts
- [x] T041 Make `scripts/render-moltis-env.sh` fail closed on empty required auth and provider secrets and cover it with targeted tests
- [x] T042 Pin production `MOLTIS_RUNTIME_CONFIG_DIR` to the canonical runtime path or an explicit allowlist and validate that exact path during deploy
- [x] T043 Reconcile auth ownership across `config/moltis.toml`, secrets docs, deploy workflow, preflight, and runtime strategy including `MOLTINGER_SERVICE_TOKEN` and Telegram allowlist source of truth
- [x] T044 Upgrade deploy and smoke proof from transport green to canonical provider/model proof including `openai-codex::gpt-5.4` and restart survival
- [x] T045 Add explicit session reconcile/reset automation and runbook gates after provider/catalog recovery for Telegram and UI sessions
- [x] T046 Audit and preserve durable runtime state outside tracked config, including `~/.moltis`, with a manifest or contract suitable for backup/restore validation
- [x] T047 Expand authoritative UAT semantics for `/status`, wrong-target chat, verification-gate replies, and exercised-surface matrices for browser/search/repo-context paths
- [x] T048 Design immutable production release roots plus runtime attestation/drift detection so runtime provenance cannot silently fall off tracked intent

---

## Phase 6: Embedding And Ollama Root-Cause Closure

- [x] T050 Reconcile Speckit artifacts for the `memory_search` / missing Ollama provider incident and encode the runtime-config parity + `OLLAMA_API_KEY` hypotheses
- [x] T051 Forward `OLLAMA_API_KEY` into the production `moltis` container and add static coverage for the contract
- [x] T052 Extend deploy verification and runtime attestation so stale writable `moltis.toml` fails closed against tracked `config/moltis.toml`
- [x] T053 Add or update component/static coverage for runtime-config parity enforcement
- [x] T054 Record RCA, consilium, and an explicit rule for embedding/runtime drift; rebuild lessons index
- [x] T055 Prepare a runtime-only `PR1` carrier for `main` that includes only the embedding/Ollama fix path plus blocking verification lanes
- [x] T056 Merge `PR1` into `main`, run the canonical production deploy from `main`, and validate live `memory_search` plus Ollama provider/model availability against the authoritative remote runtime
- [x] T057 Only after successful live verification, land `PR2` via a fresh docs-only carrier from verified `main` with RCA/consilium/rules/runbook/lessons/spec updates and then reconcile `tasks.md`

## Dependencies & Execution Order

- Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5
- Phase 6 depends on the existing runtime-attestation hardening from Phase 5 and now lands through `PR1 -> main deploy -> PR2` rather than direct feature-branch rollout.
- Phase 2 and Phase 3 are the only repository-safe implementation phases in this slice.
- Phase 4 depends on operator action against the shared remote runtime after repository guardrails are merged.
- Phase 5 is a follow-up hardening backlog informed by the completed diagnosis and consilium, not a promise to land all items in this slice.
- Phase 6 returns to an operator-driven live fix, but only after the runtime-only `PR1` is merged to `main` and deployed through the canonical production workflow.

## Implementation Strategy

- First freeze the diagnosis into Speckit artifacts so the repair path is evidence-based.
- Then prevent future silent drift by hardening deploy/runtime verification.
- Then refresh the operator smoke diagnostic so it tests the current Moltis API surface instead of stale endpoints.
- Leave live runtime repair, session cleanup, and memory/browser operational work as explicit follow-up actions.
- Use Phase 5 backlog items to drive the next durability-focused slice once the current operational backlog is under control.
- Close the embedding/Ollama incident by first preparing a minimal `PR1` for `main`, then proving the live runtime consumes the tracked memory contract and receives the Ollama cloud credential needed for provider discovery, and only after that landing the deferred `PR2` documentation layer.
