# Feature Specification: Moltis Reliability Diagnostics and Runtime Guardrails

**Feature Branch**: `031-moltis-reliability-diagnostics`  
**Created**: 2026-03-21  
**Status**: Draft  
**Input**: Production Moltis is degraded on simple Telegram interactions, browser/search execution, tool-calling reliability, and memory/vector behavior. The work must first establish a fact-based diagnosis from tracked config, runtime evidence, official Moltis documentation, and live logs, then land only the safest repository-managed fixes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operators Can Explain The Degradation With Evidence (Priority: P1)

An operator can inspect one spec package and understand why Moltis is degraded across model selection, browser/search, tool-calling, skills visibility, and memory/vector storage without guessing.

**Why this priority**: The current failure pattern is cross-cutting. Fixes will be unsafe unless the runtime symptoms are tied to concrete tracked-vs-live evidence first.

**Independent Test**: Review `spec.md`, `plan.md`, and `tasks.md` and confirm that each major symptom is backed by a concrete source such as tracked config, live runtime inspection, logs, or official Moltis docs.

**Acceptance Scenarios**:

1. **Given** the tracked repository config and the live production runtime, **When** the operator compares them, **Then** the spec package names the exact drift and does not collapse unrelated symptoms into one vague cause.
2. **Given** browser/search, tool-calling, memory, and Telegram symptoms, **When** the operator reads the package, **Then** each symptom is classified as misconfiguration, missing integration, bug, or operational drift.
3. **Given** official Moltis docs for Docker, browser automation, memory, MCP, and prompts, **When** the operator reviews the package, **Then** the recommended baseline aligns with official behavior before any custom project assumptions.

---

### User Story 2 - Deploys Fail Fast When The Runtime Contract Drifts (Priority: P1)

An operator should not get a green deploy if Moltis starts with a healthy HTTP endpoint but cannot see `/server`, cannot load repo skills, or mounts the wrong runtime config surface.

**Why this priority**: The current production degradation is compatible with a superficially healthy container. That makes rollback and deploy signals misleading.

**Independent Test**: Run the tracked deploy verification path against a runtime that lacks the `/server` mount, uses the wrong config mount, or has a non-writable runtime config directory and confirm the deployment verification fails.

**Acceptance Scenarios**:

1. **Given** the Moltis container starts successfully but `/server` is missing, **When** deployment verification runs, **Then** the deployment is rejected as unhealthy.
2. **Given** the Moltis container mounts a read-only tracked config instead of the writable runtime config directory, **When** deployment verification runs, **Then** the deployment is rejected as unhealthy.
3. **Given** the Moltis container exposes `/health = 200` but repo skills are not visible, **When** deployment verification runs, **Then** the deployment is rejected as unhealthy.

---

### User Story 3 - Smoke Diagnostics Use Current Moltis Interfaces (Priority: P2)

An operator can run a repo-managed Moltis smoke script and test authentication plus a simple chat/status path using the current auth and RPC interfaces rather than obsolete endpoints.

**Why this priority**: One of the diagnostic tools in the repository is stale and currently reports failures that are caused by API drift in the script itself, not by Moltis.

**Independent Test**: Run the updated diagnostic script against a healthy Moltis instance and confirm it authenticates via the current auth endpoint and exercises the current RPC transport.

**Acceptance Scenarios**:

1. **Given** a valid Moltis password, **When** the smoke script runs, **Then** it authenticates through the current `/api/auth/login` flow instead of the retired `/login` form flow.
2. **Given** an authenticated session, **When** the smoke script sends a chat request, **Then** it uses the current RPC transport and surfaces the final response payload.
3. **Given** logout support is healthy, **When** the smoke script finishes, **Then** it invalidates the session and reports the result cleanly.

### Edge Cases

- What happens when a stale persisted session still points to a removed model even after the tracked provider catalog has been corrected?
- What happens when the MCP search server is intermittently available and the runtime must distinguish transport flakiness from config drift?
- What happens when Tavily MCP depends on SSE plus `TAVILY_API_KEY`, but the tracked env render path allows that secret to go empty or the runtime has no dedicated Tavily health proof?
- What happens when `memory_search` auto-detects embedding providers from the chat chain and starts sending embeddings traffic to the Z.ai Coding endpoint, returning `400 Bad Request` while a stale Groq entry returns `401 Unauthorized`?
- What happens when tracked `config/moltis.toml` pins `[memory] provider = "ollama"` and `model = "nomic-embed-text"`, but the writable runtime copy still carries an older auto-detect memory contract?
- What happens when the server `.env` contains `OLLAMA_API_KEY`, but the production `moltis` container does not receive it and therefore never exposes cloud-backed Ollama chat models such as `gemini-3-flash-preview:cloud`?
- What happens when the fix lives on a feature branch, but production policy allows deploys only from `main`, so incident closure must be split into a runtime-only `PR1` and a deferred documentation `PR2`?
- What happens when memory initializes successfully but indexes zero useful chunks because project docs are not visible in watched paths?
- What happens when browser automation is enabled in config but fails at runtime because Docker access and sibling-container connectivity are both incomplete?
- What happens when the container is healthy and authenticated, but the prompt/runtime context is degraded by stale `~/.moltis` memory files?
- What happens when the live UI itself proves the server is running a non-`main` branch and operators need that branch/runtime provenance to be deliberate rather than accidental drift?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST create `specs/031-moltis-reliability-diagnostics/spec.md`, `plan.md`, and `tasks.md` as the source of truth for this investigation.
- **FR-002**: The diagnostic package MUST inventory facts for `config/moltis.toml`, prompts/context, skills/agents bridge, tool-calling, browser/search integration, memory/vector storage, runtime constraints, logs, and current guardrails.
- **FR-003**: Each major production problem MUST be classified as `misconfiguration`, `missing integration`, `bug`, or `operational drift`.
- **FR-004**: The plan MUST propose a minimal safe remediation order that favors repository-managed guardrails before runtime-behavior changes.
- **FR-005**: Repository-managed fixes in this slice MUST stay safe, reversible, and non-destructive; live server state MUST NOT be mutated speculatively.
- **FR-006**: Moltis deploy verification MUST reject a runtime where the container working directory is not `/server`.
- **FR-007**: Moltis deploy verification MUST reject a runtime where the checkout is not mounted into the container as `/server`.
- **FR-008**: Moltis deploy verification MUST reject a runtime where `/server/skills` is not visible from inside the running Moltis container.
- **FR-009**: Moltis deploy verification MUST reject a runtime where `/home/moltis/.config/moltis` is not mounted from the configured writable runtime config directory.
- **FR-010**: Moltis deploy verification MUST reject a runtime where the runtime config directory is not writable for Moltis runtime-managed files such as `provider_keys.json`.
- **FR-011**: The repository smoke script for Moltis API diagnostics MUST use the current auth surface and current chat/status transport.
- **FR-012**: The package MUST explicitly distinguish safe repository fixes from deferred operational actions such as redeploying production, clearing stale session state, or backfilling memory indexes.
- **FR-013**: The package MUST preserve the target-boundary rule: local fixture results may validate repo contracts, but only remote checks may prove the shared live runtime behavior.
- **FR-014**: The package MUST record a concrete architectural hardening backlog for fail-closed config/auth/session durability beyond the safe-fix slice.
- **FR-015**: The package MUST surface Tavily SSE instability and `memory_search` embedding-provider failures as the highest-priority unresolved live blockers after OAuth/runtime-contract recovery.
- **FR-016**: The repository MUST provide a read-only diagnostic entrypoint that summarizes the tracked Tavily/memory contract plus an optional runtime-log failure taxonomy for Tavily and embeddings.
- **FR-017**: The shared Moltis env renderer MUST fail closed when `TAVILY_API_KEY` is empty if the tracked runtime depends on Tavily MCP search.
- **FR-018**: Production deploy/runtime verification MUST reject a runtime where `${MOLTIS_RUNTIME_CONFIG_DIR}/moltis.toml` diverges from tracked `config/moltis.toml`.
- **FR-019**: The production `moltis` container MUST receive `OLLAMA_API_KEY` whenever the tracked provider surface depends on cloud-backed Ollama models.
- **FR-020**: The repository MUST record an RCA and an explicit rule for embedding/runtime drift so future sessions check runtime config parity and `OLLAMA_API_KEY` delivery before blaming provider auth or embeddings APIs.
- **FR-021**: When production deploy policy allows deploys only from `main`, the incident closure MUST define a two-stage landing strategy: `PR1` contains only production-critical runtime fixes plus blocking verification lanes, and `PR2` carries RCA/consilium/rules/lessons/spec updates only after live verification succeeds via a fresh docs-only carrier based on the verified `main` state.

### Key Entities

- **RuntimeContractCheck**: Repository-managed verification that the running Moltis container matches the required `/server`, runtime config, and skills visibility contract.
- **RootCauseFinding**: A diagnostic record that ties one symptom to evidence, a category, and a recommended remediation sequence.
- **RuntimeDriftEvidence**: Concrete live facts such as mounts, logs, session state, health endpoints, or Telegram responses showing divergence from tracked intent.
- **SmokeDiagnostic**: A reproducible operator entrypoint that validates auth, status, and a basic chat flow against current Moltis interfaces.
- **DeferredOperationalFix**: A necessary live follow-up that should not be auto-applied by repository code in this slice.

### Assumptions & Dependencies

- Official Moltis docs remain the baseline for Docker, browser automation, memory, prompts, and MCP integration.
- The authoritative target for current behavior is the shared remote Moltis deployment, not a local replacement stack.
- Telegram bot ownership already lives inside Moltis; user-facing tests should therefore use the real Telegram path or authoritative server-side tooling.
- Existing repository scripts and tests may lag the current Moltis runtime surface and need to be verified before they are trusted as diagnostics.
- Production deploy policy is authoritative: the shared remote may be smoke-tested from a branch only through read-only or contract-safe UAT paths, but the actual production rollout must happen from `main`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The `031-moltis-reliability-diagnostics` spec package exists and documents the runtime evidence for the major degradation symptoms.
- **SC-002**: The final diagnostic package contains a root-cause classification matrix covering memory/vector behavior, simple chat failures, browser/search failures, tool-calling reliability, and missing repo-skill integration.
- **SC-003**: Repository deploy verification fails when Moltis is healthy at `/health` but missing `/server`, missing `/server/skills`, or using the wrong runtime config mount.
- **SC-004**: The repository Moltis smoke script authenticates through the current auth surface and exercises the current chat/status path.
- **SC-005**: Safe fixes landed in this slice are validated by targeted repository checks.
- **SC-006**: Deferred live actions are explicitly listed so operators can finish the repair without guessing which remaining steps are operational rather than code changes.
- **SC-007**: The package records follow-up backlog items for auth secret rendering, runtime-dir pinning, session reconciliation, semantic UAT hardening, and release-root/runtime-attestation drift control.
- **SC-008**: The Speckit backlog explicitly ranks Tavily SSE failures and `memory_search` embedding-provider failures above browser and long-tail cleanup work.
- **SC-009**: A repository-managed diagnostic script can emit a machine-readable summary of tracked search/memory contract plus Tavily/embedding failure signals from a provided log sample.
- **SC-010**: Deploy/runtime attestation fails when the live writable `moltis.toml` is stale relative to tracked `config/moltis.toml`.
- **SC-011**: Static validation fails if `docker-compose.prod.yml` stops forwarding `OLLAMA_API_KEY` into the `moltis` container.
- **SC-012**: The incident is preserved in tracked RCA/rules/lessons artifacts so the repair path is discoverable in future sessions.
- **SC-013**: The Speckit artifacts explicitly separate `PR1` production-critical runtime changes from `PR2` deferred documentation/process artifacts so the canonical deploy path can proceed from `main` without dragging along mutable post-incident docs.
