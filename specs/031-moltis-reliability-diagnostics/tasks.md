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
- [x] T057 Only after successful live verification, land `PR2` via a fresh docs-only carrier from verified `main` with RCA/consilium/rules/runbook/lessons/spec updates and then reconcile `tasks.md` (landed as PR #101)

---

## Phase 7: Telegram Activity-Log Leak Closure

- [x] T060 Reconcile Speckit artifacts for the Telegram `Activity log` leak and encode the authoritative-UAT false-pass hypotheses
- [x] T061 Add an explicit tracked Moltis identity/channel-output guardrail that forbids internal activity/tool-progress dumps in user-facing messaging channels
- [x] T062 Harden `scripts/telegram-web-user-probe.mjs` so emoji-prefixed telemetry replies and recent invalid pre-send incoming activity fail closed
- [x] T063 Extend Telegram component coverage for emoji-prefixed telemetry replies and authoritative pre-send contamination
- [x] T064 Record RCA/rules/lessons for the Telegram activity-log leak plus authoritative-UAT blind spot
- [x] T065 Re-run authoritative Telegram validation against the shared remote runtime and reconcile `tasks.md` with the verified outcome

---

## Phase 8: Browser Sandbox Contract Audit And New-Instance Prevention

- [x] T070 Record the second browser root cause in tracked RCA/rules/runbook artifacts, including the answer to whether the failure came from ignoring official docs versus stopping after a partial contract fix
- [ ] T071 Audit the full browser/sandbox contract against official Moltis docs plus secondary browserless/Chromium bind-mount caveats: sandbox mode, Docker socket access, `container_host`, `sandbox_image`, `profile_dir`, `persist_profile`, writable host-visible profile storage, and end-to-end browser canary proof
- [ ] T072 Extend deploy/runtime/browser proof so Docker/socket recovery is not treated as complete until writable browser-profile storage and a real `browser` navigation canary both pass
- [ ] T073 Verify additional adjacent timeout/activity-leak failure modes triggered by browser/search incidents and reconcile the authoritative Telegram/browser UAT contract accordingly
- [ ] T074 Preserve the browser/sandbox deploy checklist and new-instance lessons so future agent instances start from the complete contract rather than rediscovering the same drift

## Dependencies & Execution Order

- Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6 -> Phase 7
- Phase 8 is a new follow-up backlog driven by the March 27 browser timeout evidence; it is intentionally left open until the full browser/sandbox contract is re-proven against the authoritative remote path.
- Phase 6 depends on the existing runtime-attestation hardening from Phase 5 and now lands through `PR1 -> main deploy -> PR2` rather than direct feature-branch rollout.
- Phase 7 depends on the completed Telegram/session reliability work from Phases 4 and 5 and adds a narrower user-facing channel-output/UAT closure pass.
- Phase 8 depends on both the earlier browser access repair and the Telegram/UAT work, because the observed failure combined browser timeout, activity leakage, and incomplete post-fix verification.
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
- Close the Telegram activity-log incident by layering a fail-closed prompt/channel contract under a fail-closed authoritative UAT gate, then validating the shared remote behavior with a real Telegram run.
- Treat browser sandbox recovery as incomplete until the whole Docker-backed browser contract is re-proven: socket access, `container_host`, host-visible writable profile storage, and an exercised browser canary on the same user-facing path that previously timed out.
