# Feature Specification: Clawdiy Remote OAuth Runtime Lifecycle

**Feature Branch**: `017-clawdiy-remote-oauth-lifecycle`  
**Created**: 2026-03-12  
**Status**: Planned  
**Input**: User description: "Оформляй исследования в документы и добавляй его в индексы с кроссылками и хлебными крошками, затем планируй реализацию по speckit воркфлоу"

## Executive Summary

Clawdiy already runs live on `ainetic.tech`, but its `codex-oauth` / `gpt-5.4` capability is still only metadata-gated. The repository can render `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE`, validate scopes/models syntactically, and quarantine the provider when metadata is missing, but it still lacks the production lifecycle for a real OpenClaw runtime OAuth session.

This feature upgrades Clawdiy from metadata-only OAuth readiness to a production-grade runtime lifecycle. The design must distinguish three layers that are currently conflated:

1. GitHub Secrets and CI-rendered metadata gate
2. the real OpenClaw runtime auth store used by the live container
3. post-auth execution evidence proving `gpt-5.4` actually works upstream

The implementation must support the current practical-now operator path: bootstrap OAuth against the actual target runtime auth store on `ainetic.tech`, then keep verification, quarantine, and operator repeat-auth under GitOps. It must also leave a clean path toward future artifactized delivery of the runtime auth store without redesigning the topology.

## Assumptions

- Clawdiy remains deployed on `ainetic.tech` in its own compose stack and subdomain `clawdiy.ainetic.tech`.
- Baseline Clawdiy runtime health must remain independent from optional `codex-oauth` capability.
- Runtime OAuth credentials must not be committed to git.
- GitHub Secrets remain the canonical source for metadata gates and operator-controlled deploy inputs.
- The current OpenClaw upstream behavior on 2026-03-12 includes an official remote paste-back flow, but that flow is operationally brittle.

## Out of Scope

- Replacing OpenClaw upstream auth UX with a custom gateway-auth RPC
- Designing a generic multi-provider credential vault for every current and future agent
- Making `gpt-5.4` a hard dependency for baseline Clawdiy health
- Storing live OAuth refresh/access artifacts directly in git

## User Scenarios & Testing

### User Story 1 - Clawdiy Uses A Real Runtime OAuth Store (Priority: P1)

As an operator of live Clawdiy,  
I want OpenClaw to read a real runtime auth store for `codex-oauth`,
So that `gpt-5.4` is actually available to the live container rather than only advertised by metadata.

**Why this priority**: Without a real runtime auth store, the current repo can only claim policy readiness, not actual provider readiness.

**Independent Test**: On live Clawdiy, verify that the runtime auth store exists in the intended persistent path, `codex-oauth` is visible in runtime model/provider status, and the provider remains quarantined when the store is absent or invalid.

**Acceptance Scenarios**:

1. **Given** Clawdiy has a valid runtime auth store in the intended persistent location, **When** the runtime is deployed, **Then** OpenClaw resolves `codex-oauth` from that store without requiring manual server-side file edits after each deploy.
2. **Given** the runtime auth store is missing, malformed, or owned by the wrong path/identity, **When** Clawdiy is validated, **Then** the provider is fail-closed quarantined and baseline health remains available.
3. **Given** metadata exists but runtime auth store does not, **When** the operator runs repeat-auth verification, **Then** the system must report “metadata present, runtime auth absent” rather than a generic pass.

### User Story 2 - Operators Can Repeat-Auth Without Rediscovering The Flow (Priority: P1)

As an operator maintaining Clawdiy over time,  
I want a documented and repeatable bootstrap and rotation path for remote-container OAuth,  
So that refresh/rotation does not depend on tribal knowledge or ad hoc SSH experimentation.

**Why this priority**: The provider will drift or expire over time; repeat-auth must be part of the platform, not a one-off bootstrap ritual.

**Independent Test**: Follow the documented repeat-auth path from a clean operator workstation and confirm it updates the intended runtime store, preserves metadata/quarantine rules, and produces operator-visible evidence.

**Acceptance Scenarios**:

1. **Given** the operator needs to bootstrap or refresh `codex-oauth`, **When** they follow the runbook, **Then** the steps explicitly say where auth is written, how it is validated, and what evidence proves success.
2. **Given** the operator follows the flow but upstream OAuth does not complete, **When** the attempt ends, **Then** the failure is visible, evidence is preserved, and Clawdiy does not silently switch into an undefined provider state.
3. **Given** the operator completes repeat-auth successfully, **When** the next deployment or restart happens, **Then** runtime auth remains available from the intended persistent store.

### User Story 3 - Promotion Requires Real Post-Auth Canary Evidence (Priority: P2)

As a maintainer of the Clawdiy platform,  
I want `gpt-5.4` promotion to depend on a real post-auth canary,  
So that upstream provider readiness is proven rather than inferred from login metadata.

**Why this priority**: Fresh upstream issues show that OAuth may appear successful while scopes or provider activation are still incomplete.

**Independent Test**: Run a canary after repeat-auth and verify that promotion passes only when the canary succeeds, and that failure keeps `gpt-5.4` quarantined.

**Acceptance Scenarios**:

1. **Given** runtime auth exists but required scopes or provider activation are incomplete, **When** canary runs, **Then** promotion remains blocked and the failure mode is explicit.
2. **Given** runtime auth and provider activation are valid, **When** canary runs against `gpt-5.4`, **Then** the evidence records success and the provider can be promoted.
3. **Given** canary fails after a previously good state, **When** the operator reviews Clawdiy health, **Then** baseline Clawdiy stays up while `codex-oauth` is downgraded or quarantined.

## Edge Cases

- Runtime auth metadata exists, but the live auth store was never created.
- Runtime auth store exists, but OpenClaw writes or reads from the wrong locality.
- Provider auth store exists, but `models.providers.codex-oauth` is not explicitly active.
- OAuth succeeds superficially, but required scope `api.responses.write` is missing.
- Live Clawdiy restarts after auth bootstrap and loses access to the runtime auth store because the path was not persistent.
- The operator has evidence from repeat-auth but no real canary result.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST distinguish metadata OAuth gate state from the real runtime auth artifact used by OpenClaw.
- **FR-002**: The system MUST define an authoritative persistent runtime location for Clawdiy provider auth state.
- **FR-003**: The system MUST document and validate how runtime auth state is written into the live Clawdiy container lifecycle.
- **FR-004**: The system MUST support a practical-now repeat-auth path that targets the real Clawdiy runtime auth store on `ainetic.tech`.
- **FR-005**: The system MUST preserve a future path to artifactized auth-store delivery without redesigning the overall topology.
- **FR-006**: The system MUST keep baseline Clawdiy runtime health separate from optional `codex-oauth` readiness.
- **FR-007**: If metadata is present but runtime auth store is missing or invalid, the system MUST fail closed for `codex-oauth` and MUST NOT report provider readiness.
- **FR-008**: The system MUST explicitly validate provider activation for `codex-oauth` instead of assuming a valid auth store automatically enables the provider.
- **FR-009**: The system MUST require post-auth verification for required scope(s) and allowed model(s), including `api.responses.write` and `gpt-5.4`.
- **FR-010**: The system MUST define a real post-auth canary that proves upstream `gpt-5.4` execution path success.
- **FR-011**: The system MUST persist operator-visible repeat-auth and canary evidence.
- **FR-012**: Runtime OAuth credentials MUST NOT be committed to git.
- **FR-013**: Docs and workflows MUST state which pieces remain in GitHub Secrets and which pieces live only in the runtime auth store.
- **FR-014**: Repeat-auth runbooks MUST say where the auth artifact is expected, how it is refreshed, and how to recover from partial failure.
- **FR-015**: Tests and smoke checks MUST detect “metadata pass but runtime auth absent” as a failing or quarantined condition.
- **FR-016**: The implementation MUST update the Clawdiy runtime/config contract so provider activation is explicit and testable.

### Key Entities

- **Auth Metadata Gate**: Compact policy/verification data rendered from GitHub Secrets, such as scopes and allowed models.
- **Runtime Auth Store**: Persistent Clawdiy-local artifact store that OpenClaw actually uses for `codex-oauth` authentication.
- **Provider Activation Contract**: Explicit runtime configuration showing whether `codex-oauth` is activated and bound to the intended model path.
- **Repeat-Auth Evidence**: Durable record of when runtime auth was bootstrapped or refreshed, by which method, and with what result.
- **Post-Auth Canary Result**: Structured evidence proving whether real `gpt-5.4` execution succeeded after auth bootstrap.

## Success Criteria

### Measurable Outcomes

- **SC-001**: In 100% of covered validation scenarios, the system distinguishes metadata-only readiness from real runtime auth readiness.
- **SC-002**: In 100% of covered failure scenarios, missing or invalid runtime auth quarantines `codex-oauth` without taking Clawdiy baseline health down.
- **SC-003**: Operators can execute the documented repeat-auth flow without undocumented server-side edits or rediscovery work.
- **SC-004**: Promotion of `gpt-5.4` depends on successful post-auth canary evidence rather than metadata alone.
- **SC-005**: Documentation, config, smoke checks, and tests all tell the same story about runtime auth store, provider activation, and canary gating.
