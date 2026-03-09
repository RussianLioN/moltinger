# Feature Specification: Clawdiy Agent Platform

**Feature Branch**: `001-clawdiy-agent-platform`  
**Created**: 2026-03-09  
**Status**: Ready for Planning  
**Research Report**: [research.md](./research.md)  
**Protocol Draft**: [protocol.md](./protocol.md)  
**Input**: User description: "Deploy OpenClaw as a second permanent Moltinger platform agent named Clawdiy with its own subdomain, Telegram bot, persistent runtime, inter-agent protocol, staged rollout, rollback, and implementation handoff."

## Scope Boundary

### In Scope

- A permanent second platform agent named Clawdiy with its own human-facing identity, runtime boundary, and operational ownership.
- A deployment architecture that starts on the current shared server and remains valid when Clawdiy is later moved to a separate node or VM.
- A documented inter-agent contract for Moltinger, Clawdiy, and future permanent agents.
- Platform operations needed for a long-lived agent fleet: ingress, secrets, repeat-auth, observability, backup, restore, rollback, and runbooks.
- Implementation packaging requirements so a later delivery branch can execute without repeating research.

### Out of Scope

- Full autonomous swarm scheduling across arbitrary numbers of nodes in this first feature package.
- Replacing the current Moltinger production deployment or its existing user-facing identity.
- Designing every future agent in detail; this feature defines the reusable platform contract they will follow.
- Production-grade high availability across multiple hosts in the first rollout.
- Using Telegram as the authoritative machine-to-machine transport for core inter-agent handoff.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Permanent Second Agent Deployment (Priority: P1)

Как оператор платформы, я хочу развернуть Clawdiy как отдельного постоянного агента рядом с Moltinger, чтобы получить второй независимый рабочий контур без риска для текущего агента.

**Why this priority**: Без отдельного long-lived deployment остальные требования не имеют смысла: inter-agent protocol, runbooks и дальнейший рост роя зависят от существования второго стабильного агента.

**Independent Test**: Clawdiy can be deployed, reached via its own web address and Telegram bot, restarted independently, and removed independently while Moltinger remains available and unchanged.

**Acceptance Scenarios**:

1. **Given** Moltinger is already running, **When** Clawdiy is deployed, **Then** both permanent agents are simultaneously reachable through their own human-facing endpoints.
2. **Given** Clawdiy is restarted or updated, **When** operator verifies platform state, **Then** Moltinger configuration, state, and ingress remain unaffected.
3. **Given** both agents share the same host in the first rollout, **When** operator inspects runtime ownership, **Then** Clawdiy has its own persistent configuration, state, secrets, and operational procedures.

---

### User Story 2 - Traceable Inter-Agent Task Handoff (Priority: P1)

Как координатор платформы, я хочу передавать задачи между Moltinger, Clawdiy и будущими агентами через явный протокол, чтобы handoff был адресуемым, наблюдаемым и управляемым, а не зависел от неявного контекста чата.

**Why this priority**: Если handoff не имеет стабильной адресации, acknowledgement и failure policy, multi-agent platform быстро превращается в набор несвязанных чатов без операционной надежности.

**Independent Test**: A task can be handed from one registered agent to another, receives correlation identifiers and acknowledgements, and ends with a terminal status or explicit escalation.

**Acceptance Scenarios**:

1. **Given** a registered recipient agent, **When** Moltinger hands off a task to Clawdiy, **Then** the handoff receives a stable correlation id and an acknowledgement record.
2. **Given** a handoff reaches terminal state, **When** operator reviews the run, **Then** completion, failure, or timeout is visible in the audit trail together with sender and recipient identities.
3. **Given** the sender targets an unknown, unauthorized, or unavailable agent, **When** handoff is attempted, **Then** the platform rejects or escalates it without silent loss.

---

### User Story 3 - Separate Auth and Trust Lifecycle (Priority: P1)

Как оператор платформы, я хочу управлять Telegram, web/API, and model-provider authentication отдельно для каждого постоянного агента, чтобы повторная авторизация, rotation и incident response не ломали весь рой сразу.

**Why this priority**: Shared-host multi-agent systems fail dangerously when one agent's token, password, or OAuth profile is reused or silently degrades across agents.

**Independent Test**: One agent can rotate or repeat-auth its credentials while the other agent stays healthy, and any degraded auth state fails closed with operator-visible evidence.

**Acceptance Scenarios**:

1. **Given** Clawdiy requires repeat-auth for one external capability, **When** operator follows the documented procedure, **Then** only Clawdiy's affected capability changes state.
2. **Given** credentials are rotated for one agent, **When** the platform is re-verified, **Then** no cross-agent secret leakage or identity collision occurs.
3. **Given** a provider or OAuth scope is insufficient, **When** the capability is invoked, **Then** the request fails closed and raises an explicit escalation path.

---

### User Story 4 - Observable Recovery and Rollback (Priority: P2)

Как оператор платформы, я хочу иметь per-agent health, logs, backups, restore и rollback, чтобы можно было безопасно сопровождать Clawdiy как production-grade long-lived service.

**Why this priority**: A second permanent agent without health ownership, backups, and rollback would increase platform risk instead of expanding capability.

**Independent Test**: Operator can distinguish Moltinger and Clawdiy telemetry, recover Clawdiy from backup, and disable or roll back Clawdiy without destroying evidence or impacting Moltinger.

**Acceptance Scenarios**:

1. **Given** both agents are running, **When** operator checks health and logs, **Then** each agent's runtime status and cross-agent exchanges are distinguishable.
2. **Given** Clawdiy state is restored from backup, **When** recovery completes, **Then** Clawdiy returns with expected identity and state while Moltinger remains unchanged.
3. **Given** a rollout or protocol change regresses Clawdiy, **When** rollback is triggered, **Then** the platform can return to Moltinger-only or last-known-good Clawdiy state with preserved audit evidence.

---

### User Story 5 - Future Fleet Expansion Without Topology Rewrite (Priority: P2)

Как архитектор платформы, я хочу использовать эту же схему для будущих агентов и для последующего выноса Clawdiy на отдельный node/VM, чтобы рост роя не требовал полной переделки адресации, доверия и runbooks.

**Why this priority**: The user explicitly needs a reusable control-plane pattern, not a one-off bootstrap around a single GPT-5.4 task.

**Independent Test**: The same identity, discovery, and handoff contract can describe same-host agents and later remote agents without redefining the canonical agent model.

**Acceptance Scenarios**:

1. **Given** a new permanent role is added, **When** it is onboarded into the fleet, **Then** it fits the same identity, addressing, and handoff rules defined for Moltinger and Clawdiy.
2. **Given** Clawdiy is moved from shared host to separate node or VM, **When** the move is completed, **Then** canonical identities and inter-agent semantics remain unchanged.
3. **Given** the platform contains a mix of same-host and remote agents, **When** operator routes work between them, **Then** discovery, trust, and escalation continue to follow one documented model.

### Edge Cases

- What happens when Telegram delivers duplicate, late, or out-of-order messages that could trigger duplicate handoffs?
- What happens when a user-visible completion is delivered to a channel but the coordinator agent does not receive the internal completion signal?
- What happens when an OAuth or subscription token exists but lacks required scopes for the intended model or capability?
- What happens when one agent restarts while a cross-agent task is in progress?
- What happens when a restored agent state is older than the current inter-agent protocol or registry state?
- What happens when two runtimes are accidentally configured with the same canonical agent identity?
- What happens when a target agent remains registered but its capability claims are stale or temporarily unavailable?
- What happens when Clawdiy must be rolled back while preserving evidence about a failed handoff or failed auth event?

## Requirements *(mandatory)*

### Functional Requirements

#### Agent Identity and Deployment Boundaries

- **FR-001**: The platform MUST support at least two simultaneously active permanent agents with unique canonical agent identifiers.
- **FR-002**: Clawdiy MUST have its own stable human-facing identity, including a distinct web address and Telegram bot identity.
- **FR-003**: Clawdiy MUST be deployable as a separate runtime unit on the current host without overwriting or reusing Moltinger's persistent state.
- **FR-004**: Each permanent agent MUST own separate persistent configuration, state, secret inventory, and operator procedures.
- **FR-005**: The deployment model MUST preserve a path to move Clawdiy to a separate node or VM without changing canonical agent identity or rewriting the inter-agent contract.
- **FR-006**: The feature MUST define a reusable onboarding pattern for future permanent agents such as architect, coder, tester, researcher, and coordinator roles.

#### Agent Discovery and Addressing

- **FR-007**: The platform MUST define a canonical addressing model that distinguishes agent identity from transport-specific endpoints.
- **FR-008**: The platform MUST define how agents are registered, discovered, and marked reachable or unavailable.
- **FR-009**: The platform MUST define capability metadata so senders can determine whether a target agent can accept a requested task.
- **FR-010**: The platform MUST reject or explicitly escalate requests addressed to unknown, ambiguous, unauthorized, or unavailable agents.

#### Inter-Agent Message Contract

- **FR-011**: The platform MUST define a versioned inter-agent message envelope for task handoff and status exchange.
- **FR-012**: The message envelope MUST include sender identity, recipient identity, message id, correlation id, causation reference, timestamps, and idempotency semantics.
- **FR-013**: The platform MUST distinguish end-user conversation context from inter-agent task context and preserve correlation between them.
- **FR-014**: The platform MUST define a required acknowledgement model for accepted, rejected, started, completed, failed, timed out, and cancelled states.
- **FR-015**: The platform MUST define deterministic handling for duplicates, late arrivals, orphaned replies, and stale completions.
- **FR-016**: The platform MUST define retry policy, retry eligibility, retry limits, and backoff behavior.
- **FR-017**: The platform MUST define timeout policy for delivery, execution start, execution progress silence, and terminal completion.
- **FR-018**: The platform MUST define escalation behavior when the expected acknowledgement or terminal state is not produced.

#### Trust Boundary and Authentication Lifecycle

- **FR-019**: Each permanent agent MUST have an independent authentication lifecycle for human access, API access, Telegram access, and external provider access.
- **FR-020**: The platform MUST define which credentials are agent-local and which infrastructure credentials, if any, may be shared.
- **FR-021**: The platform MUST define a trust boundary between public ingress and internal inter-agent communication.
- **FR-022**: The platform MUST require explicit authorization policy for one agent to invoke another agent's capabilities.
- **FR-023**: The platform MUST fail closed when auth, token scope, or trust material is missing, degraded, or expired.
- **FR-024**: The platform MUST include repeat-auth and credential rotation procedures for Telegram, web/API auth, and external model/provider auth.

#### Observability, Audit, and Recovery

- **FR-025**: The platform MUST produce an audit trail for inter-agent handoffs, status changes, auth events, operator interventions, and rollback actions.
- **FR-026**: The platform MUST support per-agent health checks, logs, metrics, and alert ownership.
- **FR-027**: The platform MUST allow operators to distinguish human-facing notifications from machine-facing acknowledgements in observability artifacts.
- **FR-028**: The platform MUST define backup and restore scope for configuration, state, recoverable credentials, and audit evidence.
- **FR-029**: The platform MUST define disaster recovery procedures for single-agent corruption, shared-host loss, auth failure, and stuck message processing.
- **FR-030**: The platform MUST define a rollback procedure that can disable Clawdiy or revert protocol changes without regressing Moltinger's known-good operation.

#### Governance, Rollout, and Handoff

- **FR-031**: The platform MUST define a staged rollout with entry criteria, exit criteria, and rollback checkpoints for each stage.
- **FR-032**: The implementation MUST be planned under a dedicated epic/worktree/branch model separate from unrelated platform work.
- **FR-033**: Documentation ownership MUST define who maintains deployment docs, runbooks, secret references, protocol docs, and topology registry entries.
- **FR-034**: The final Speckit package MUST provide enough context that a later implementation branch can begin without repeating the core research phase.
- **FR-035**: Telegram MAY be used for human ingress and notifications, but the authoritative inter-agent handoff path MUST be explicitly documented and MUST NOT depend on ad hoc chat behavior.
- **FR-036**: The platform MUST provide an operator-visible manual escalation path for any handoff that cannot be completed automatically.

### Key Entities

- **AgentIdentity**: Canonical representation of a permanent agent, including stable id, display identity, ownership, and role.
- **AgentEndpoint**: A transport-specific way to reach an agent, such as web ingress, API surface, or Telegram bot identity.
- **AgentRegistryEntry**: The discovery record that states which agent exists, what capabilities it offers, and whether it is currently eligible to receive work.
- **AgentCredentialSet**: The set of secrets, auth states, and repeat-auth obligations associated with exactly one agent.
- **AgentMessageEnvelope**: The versioned handoff document used to send work, status, and control signals between agents.
- **TaskHandoff**: A single cross-agent assignment with intent, lifecycle state, deadlines, and evidence.
- **AcknowledgementRecord**: Proof that a recipient accepted, rejected, started, progressed, completed, failed, or timed out a handoff.
- **ConversationCorrelation**: The mapping between a human conversation, an inter-agent workflow, and any related operational incidents.
- **AuditEvent**: An append-only operational record for message delivery, auth change, escalation, rollback, restore, or operator action.
- **StateSnapshot**: A recoverable representation of one agent's persistent state used for backup, restore, and rollback.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can deploy Clawdiy as a second permanent agent without causing a regression or downtime incident for Moltinger during the rollout window.
- **SC-002**: 100% of cross-agent handoffs create a correlation id and audit record at submission time and at terminal state.
- **SC-003**: In a healthy environment, a registered target agent acknowledges an incoming handoff within 10 seconds or the platform escalates it as undelivered.
- **SC-004**: 100% of terminal handoff outcomes are classified as completed, failed, timed_out, rejected, or cancelled; no handoff remains silently lost.
- **SC-005**: Operators can restore Clawdiy from backup within 30 minutes without modifying Moltinger's state.
- **SC-006**: The documented platform contract remains valid when adding at least three future permanent agent roles without redefining the canonical message schema.
- **SC-007**: Clawdiy can be rolled back to disabled or last-known-good state within 15 minutes using the documented rollback procedure while preserving audit evidence.
- **SC-008**: 0 end-user session cookies, Telegram bot tokens, or provider auth profiles are shared implicitly between Moltinger and Clawdiy.
- **SC-009**: Operators can determine the cause of a failed or stuck handoff from logs and audit records within 5 minutes.
- **SC-010**: Moving Clawdiy from the shared host to a separate node or VM requires no change to canonical agent ids, correlation semantics, or user-facing role definitions.

## Assumptions

- The current production baseline remains `moltis.ainetic.tech` on the shared host `ainetic.tech`.
- GitHub Secrets remains the canonical secret source, and runtime secret material continues to be generated by CI/CD.
- The first rollout places Clawdiy on the same server in a separate deployment unit, while future extraction to a separate node or VM is intentionally planned.
- Shared infrastructure components such as ingress and monitoring may be reused, but Clawdiy runtime state and auth lifecycle remain distinct.
- A later planning phase may choose specific transports, storage layouts, and implementation files as long as they satisfy this feature contract and the supporting research artifacts.

## Dependencies

- Existing Moltinger production ingress, monitoring, and CI/CD remain operational during the feature rollout.
- Supporting artifacts in this package, especially [research.md](./research.md) and [protocol.md](./protocol.md), are treated as planning inputs for the later implementation phase.
