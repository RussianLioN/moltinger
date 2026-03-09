# Draft Inter-Agent Protocol: Clawdiy Agent Platform

**Feature**: 001-clawdiy-agent-platform  
**Date**: 2026-03-09  
**Status**: Draft for planning input

## 1. Purpose

Define a reusable agent-to-agent contract for Moltinger, Clawdiy, and future permanent agents so that work can be handed off, acknowledged, observed, retried, escalated, and recovered without depending on implicit chat history.

## 2. Design Goals

- Stable identity independent of transport.
- Same contract for same-host and remote-node agents.
- Separate human-facing delivery from machine-facing acknowledgement.
- Deterministic handling of duplicates, retries, and late completions.
- Fail-closed trust model with explicit auth and capability allowlists.
- Auditability across user conversation, agent workflow, and operator intervention.

## 3. Non-Goals

- This protocol does not require a distributed scheduler in the first rollout.
- This protocol does not assume Telegram or any other chat transport is the source of truth for machine-to-machine exchange.
- This protocol does not standardize every future agent capability now; it standardizes the contract they must publish.

## 4. Identity Model

Each permanent agent is defined by one canonical `agent_id` and several transport-specific endpoints.

### Required Identity Fields

- `agent_id`: stable machine identifier, for example `moltinger` or `clawdiy`
- `display_name`: human-readable name
- `role`: primary role classification
- `owner`: operator/team responsible for the agent
- `capabilities`: declared capabilities and prerequisites
- `public_endpoints`: human-facing addresses such as subdomain or Telegram bot
- `internal_endpoint`: service-to-service address used for authoritative handoff
- `auth_profile_refs`: references to the agent's own auth materials
- `state_scope`: reference to the agent's persistent state boundary

### Identity Rule

One canonical `agent_id` may map to many endpoints, but no two active runtimes may share the same canonical `agent_id`.

## 5. Addressing and Discovery

### Canonical Addressing

- Human-facing: `https://clawdiy.ainetic.tech`, `telegram:@clawdiy_bot`
- Internal logical address: `agent://clawdiy`
- Internal transport endpoint: private API/RPC endpoint resolved from the registry

### Phase-1 Discovery Model

- Use a version-controlled static registry for permanent agents.
- Each registry entry publishes reachability state, capabilities, and allowed callers.
- Operators update registry changes through git so discovery changes are auditable.

### Discovery Outcomes

- `reachable`
- `degraded`
- `unreachable`
- `auth_required`
- `quarantined`

## 6. Transport Model

### Primary Transport

Authenticated platform-native RPC/API transport over an internal endpoint.

Requirements:

- explicit request/response correlation
- deterministic acknowledgements
- transport-independent payload references
- private or explicitly authenticated network path

### Secondary Transport

Operator-mediated or queued fallback for degraded conditions.

Examples:

- manual reroute by coordinator/operator
- deferred replay after auth recovery
- dead-letter review queue

### Explicit Rejection

Telegram and other human chat channels are not the authoritative inter-agent transport. They may carry notifications or manual escalation prompts, but not the only copy of machine-to-machine state.

## 7. Trust Boundary

### Separate Credential Classes

- human login credentials
- API/service credentials
- Telegram bot credentials
- provider/OAuth credentials

### Trust Rules

- Agents may only call capabilities explicitly allowlisted for them.
- Human session state must not be reused as service-to-service auth.
- Provider auth degradation fails closed for the affected capability.
- Internal service credentials are distinct from human-facing credentials.

## 8. Message Envelope

The planning phase should refine the exact schema, but the envelope must contain at least:

```json
{
  "schema_version": "v1",
  "message_id": "uuid",
  "idempotency_key": "string",
  "correlation_id": "uuid",
  "causation_id": "uuid-or-null",
  "submitted_at": "2026-03-09T12:00:00Z",
  "expires_at": "2026-03-09T12:05:00Z",
  "sender": {
    "agent_id": "moltinger",
    "run_id": "run-123"
  },
  "recipient": {
    "agent_id": "clawdiy",
    "capability": "coding.orchestration"
  },
  "conversation": {
    "user_conversation_id": "conv-456",
    "workflow_id": "wf-789"
  },
  "task": {
    "kind": "delegate_task",
    "summary": "Investigate and implement fix",
    "payload_ref": "artifact://task/123",
    "priority": "high",
    "requested_timeout_secs": 1800
  },
  "delivery": {
    "attempt": 1,
    "reply_to": "agent://moltinger",
    "user_visible": false
  }
}
```

## 9. Handoff State Machine

### Required States

- `submitted`
- `accepted`
- `rejected`
- `started`
- `progress`
- `completed`
- `failed`
- `timed_out`
- `cancelled`

### State Rules

- Every `submitted` handoff must become `accepted`, `rejected`, or `timed_out`.
- Every `accepted` handoff must become `started`, `failed`, `cancelled`, or `timed_out`.
- Every non-terminal long-running handoff must emit progress or heartbeat before the silence timeout.
- Every terminal state must include reason and evidence reference.

## 10. Acknowledgement Policy

### Mandatory Acknowledgements

- delivery acknowledgement
- acceptance or rejection acknowledgement
- execution start acknowledgement
- terminal acknowledgement

### Optional Acknowledgements

- progress heartbeat
- partial result notice
- cancellation acceptance

### Target Defaults For Planning

- delivery ack deadline: `10s`
- start ack deadline: `60s`
- progress heartbeat: every `300s`
- terminal deadline: task-specific, required in the request

## 11. Retry Policy

### Safe Retry Cases

- transport failure before acceptance
- explicit `retryable` rejection class
- operator-approved replay using the same idempotency key

### Unsafe Automatic Retry Cases

- any handoff already `accepted`
- any case where recipient side effects are not known to be idempotent
- auth failure that requires operator repeat-auth

### Backoff Defaults

- attempt 1: immediate
- attempt 2: `30s`
- attempt 3: `120s`
- after max attempts: dead-letter plus escalation

## 12. Timeout Policy

### Timeout Classes

- delivery timeout
- start timeout
- silence timeout
- absolute execution timeout

### Timeout Actions

- mark handoff `timed_out`
- preserve last known evidence
- raise escalation according to severity and role
- require operator decision for replay when idempotency is uncertain

## 13. Audit Trail and Correlation

The authoritative audit trail should record:

- message and correlation ids
- sender and recipient ids
- timestamps for every state transition
- transport path used
- operator interventions
- auth errors and repeat-auth events
- rollback and restore events
- references to artifacts, logs, or payloads

### Correlation Rule

User conversation id, workflow id, and inter-agent message id must be linkable but not conflated. A user-facing reply is not proof that the machine-facing handoff completed correctly.

## 14. Escalation Rules

### Automatic Escalation Triggers

- no delivery ack before deadline
- no start ack before deadline
- auth profile invalid or missing required scopes
- duplicate or conflicting canonical identity
- dead-letter after retry budget exhausted
- late completion after timeout

### Escalation Targets

- originating agent
- coordinator agent
- operator on-call/runbook owner

### Escalation Outcomes

- manual replay
- route disable/quarantine
- repeat-auth workflow
- rollback
- restore from snapshot

## 15. Failure Handling Matrix

| Failure Case | Expected Policy |
|---|---|
| Unknown recipient | Reject immediately with operator-visible error |
| Duplicate handoff | Deduplicate by idempotency key and return prior state |
| Late terminal result after timeout | Record as late result, do not silently overwrite timeout without audit |
| Recipient restart mid-task | Recover from durable state or mark timed_out with evidence |
| Auth scope missing | Fail closed, quarantine capability, invoke repeat-auth runbook |
| Telegram duplicate delivery | Do not create second authoritative handoff; record notification anomaly separately |
| User-visible completion but no internal ack | Treat as incomplete workflow until machine-facing ack exists |
| Shared canonical identity on two runtimes | Quarantine the newer or conflicting runtime until resolved |

## 16. Rollout Implications

### Same-Host Phase

- Keep Clawdiy as separate runtime unit with separate state and secrets.
- Reuse shared ingress and monitoring only where ownership remains distinguishable.
- Validate protocol flow before adding more permanent agents.

### Remote-Node Phase

- Preserve canonical agent ids and message schema.
- Replace only endpoint resolution and trust material needed for remote routing.
- Re-run acceptance, rollback, and restore drills after extraction.

## 17. Open Questions For Planning

These are planning questions, not blockers for the specification:

- What exact internal transport should implement the primary handoff path in phase 1?
- Where should the phase-1 registry live in repo and runtime?
- Which auth mechanism best separates same-host private traffic from future remote-node traffic?
- What artifact store should back `payload_ref` and evidence references?
