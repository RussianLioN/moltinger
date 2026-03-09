# Contract: Agent Handoff

**Feature**: 001-clawdiy-agent-platform  
**Purpose**: Define the authoritative machine-to-machine handoff interface for permanent agents.

## Transport Posture

- Authoritative transport: private authenticated HTTP JSON
- Human chat channels are notifications/ingress only
- Every request must be tied to one canonical sender agent and one canonical recipient agent

## Required Headers

| Header | Purpose |
|--------|---------|
| `Authorization: Bearer <service-token>` | Service-to-service auth |
| `X-Agent-Id` | Sender canonical id |
| `X-Correlation-Id` | Workflow correlation |
| `Idempotency-Key` | Duplicate suppression |

## Endpoints

### `POST /internal/v1/agent-handoffs`

Submit a new handoff request.

**Request body**:
- `schema_version`
- `message_id`
- `idempotency_key`
- `correlation_id`
- `causation_id`
- `sender`
- `recipient`
- `conversation`
- `task`
- `delivery`

**Success response**:

```json
{
  "status": "accepted_for_delivery",
  "correlation_id": "7b2f42da-77bf-4bb9-b5f2-a472bf6b49c2",
  "delivery_deadline": "2026-03-09T12:00:10Z"
}
```

### `POST /internal/v1/agent-handoffs/{correlation_id}/acks`

Emit delivery, accept, start, progress, reject, timeout, failure, or terminal acknowledgement.

**Request body**:
- `ack_id`
- `ack_type`
- `emitted_by`
- `emitted_at`
- `status_summary`
- `evidence_ref`

### `GET /internal/v1/agent-handoffs/{correlation_id}`

Fetch current state and evidence for one handoff.

**Response body**:
- `correlation_id`
- `state`
- `attempt_count`
- `deadlines`
- `last_progress_at`
- `terminal_reason`
- `evidence_refs`

### `POST /internal/v1/agent-handoffs/{correlation_id}/cancel`

Request cancellation of a non-terminal handoff.

## Status Semantics

| State | Meaning |
|-------|---------|
| `submitted` | Request created and recorded |
| `accepted` | Recipient accepted responsibility |
| `rejected` | Recipient refused the handoff |
| `started` | Execution began |
| `progress` | Non-terminal heartbeat/update |
| `completed` | Successful terminal state |
| `failed` | Failed terminal state |
| `timed_out` | Deadline or silence timeout reached |
| `cancelled` | Cancellation accepted |

## Non-Negotiable Rules

- User-visible output is not a substitute for machine-facing acknowledgement.
- Duplicate `Idempotency-Key` must return the prior known state rather than creating new work.
- Missing or invalid service auth fails closed.
- Unknown recipients or capabilities fail with explicit rejection.
