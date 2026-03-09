# Data Model: Clawdiy Agent Platform

**Feature**: 001-clawdiy-agent-platform  
**Date**: 2026-03-09

## Entities

### 1. AgentIdentity

Represents one permanent named agent in the platform fleet.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| agent_id | string | Canonical machine identifier | unique, kebab-safe, immutable after activation |
| display_name | string | Human-readable identity | non-empty |
| role | enum | Primary fleet role | `coordinator`, `coder`, `tester`, `researcher`, `architect`, `custom` |
| runtime_engine | enum | Runtime family | `moltis`, `openclaw` |
| owner | string | Operator/team owner | non-empty |
| lifecycle_state | enum | Runtime lifecycle | `planned`, `active`, `degraded`, `quarantined`, `retired` |
| domain | string | Primary human-facing domain | unique DNS hostname |
| telegram_bot | string | Telegram bot identity | unique bot username or null |

**Invariants**:
- `agent_id` is the only canonical identity key.
- No two active runtimes may share the same `agent_id`, domain, or Telegram bot identity.

### 2. AgentEndpoint

Represents a transport-specific endpoint attached to one agent.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| agent_id | string | Owning agent | must reference `AgentIdentity` |
| endpoint_type | enum | Endpoint category | `public_web`, `internal_api`, `telegram`, `metrics`, `health` |
| address | string | Reachable address/URI | valid URI or bot handle |
| visibility | enum | Exposure level | `public`, `private`, `internal_only` |
| auth_mode | enum | Auth expectation | `human_auth`, `service_bearer`, `telegram_token`, `none` |
| active | boolean | Whether endpoint is enabled | true/false |

### 3. AgentRegistryEntry

Represents the authoritative discovery and authorization record for a permanent agent.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| agent_id | string | Registry key | must reference `AgentIdentity` |
| internal_endpoint | string | Authoritative handoff target | non-empty internal URI |
| public_endpoints | array | Human-facing endpoints | may be empty |
| capabilities | array | Allowed task capabilities | non-empty for active agent |
| allowed_callers | array | Agents allowed to invoke this agent | explicit list or wildcard policy |
| reachability | enum | Current route status | `reachable`, `degraded`, `unreachable`, `auth_required`, `quarantined` |
| policy_version | string | Policy revision | semantic version or git SHA |
| last_validated_at | datetime | Last route/policy validation | ISO 8601 |

### 4. AgentCredentialSet

Represents the authentication inventory for one agent.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| agent_id | string | Owning agent | must reference `AgentIdentity` |
| human_auth_secret_ref | string | Human login secret reference | non-empty for public agent |
| service_auth_secret_ref | string | Service-to-service auth reference | non-empty |
| telegram_token_ref | string | Telegram bot token reference | optional if no Telegram |
| provider_auth_profiles | array | External provider auth references | may be empty |
| repeat_auth_required | boolean | Whether operator action is required | true/false |
| last_validated_at | datetime | Latest validation time | ISO 8601 or null |
| rotation_state | enum | Rotation status | `healthy`, `pending`, `expired`, `failed` |

### 5. HandoffEnvelope

Represents one cross-agent task handoff request.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| schema_version | string | Contract version | required |
| message_id | string | Unique transport message id | UUID |
| idempotency_key | string | Deduplication key | non-empty |
| correlation_id | string | Workflow correlation id | UUID |
| causation_id | string | Parent reference | UUID or null |
| sender_agent_id | string | Originating agent | must reference `AgentIdentity` |
| recipient_agent_id | string | Target agent | must reference `AgentIdentity` |
| capability | string | Requested capability | must exist in registry entry |
| payload_ref | string | Artifact reference | non-empty |
| submitted_at | datetime | Submission time | ISO 8601 |
| expires_at | datetime | Delivery deadline | greater than `submitted_at` |
| user_visible | boolean | Whether the payload is user-facing | true/false |

### 6. HandoffExecution

Represents execution state for one correlated handoff.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| correlation_id | string | Workflow key | must reference `HandoffEnvelope` |
| state | enum | Current lifecycle state | `submitted`, `accepted`, `rejected`, `started`, `progress`, `completed`, `failed`, `timed_out`, `cancelled` |
| attempt_count | integer | Delivery/execution attempts | >= 1 |
| delivery_deadline | datetime | Ack deadline | ISO 8601 |
| start_deadline | datetime | Start deadline | ISO 8601 |
| absolute_deadline | datetime | Final completion deadline | ISO 8601 |
| last_progress_at | datetime | Last heartbeat | ISO 8601 or null |
| terminal_reason | string | Failure/reject/timeout reason | required for terminal non-success |
| evidence_refs | array | Related audit/artifact refs | may be empty only before execution |

**State Transitions**:

```text
submitted -> accepted -> started -> progress -> completed
submitted -> rejected
submitted -> timed_out
accepted -> failed
accepted -> cancelled
accepted -> timed_out
started  -> failed
started  -> timed_out
progress -> completed
progress -> failed
progress -> timed_out
```

### 7. AcknowledgementRecord

Represents a mandatory or optional acknowledgement emitted during handoff lifecycle.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| ack_id | string | Unique ack id | UUID |
| correlation_id | string | Related handoff | must reference `HandoffExecution` |
| ack_type | enum | Ack kind | `delivery`, `accept`, `reject`, `start`, `progress`, `terminal`, `cancel_accept` |
| emitted_by | string | Emitting agent | must reference `AgentIdentity` |
| emitted_at | datetime | Ack timestamp | ISO 8601 |
| status_summary | string | Human-readable summary | non-empty |
| evidence_ref | string | Artifact/log reference | optional |

### 8. AuditEvent

Represents one append-only operational event.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| event_id | string | Unique event key | UUID |
| event_type | enum | Event category | `handoff`, `auth`, `operator`, `rollback`, `restore`, `routing`, `health` |
| severity | enum | Severity level | `info`, `warning`, `critical` |
| agent_id | string | Primary subject agent | must reference `AgentIdentity` |
| correlation_id | string | Related workflow | UUID or null |
| occurred_at | datetime | Event time | ISO 8601 |
| payload_ref | string | Evidence location | optional |
| actor | string | Human or system actor | non-empty |

### 9. StateSnapshot

Represents a recoverable backup or rollback point for one agent.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| snapshot_id | string | Snapshot identifier | UUID or timestamp-based unique id |
| agent_id | string | Owning agent | must reference `AgentIdentity` |
| snapshot_scope | enum | What is captured | `config`, `state`, `audit`, `full` |
| created_at | datetime | Snapshot time | ISO 8601 |
| storage_location | string | Backup location | non-empty |
| verification_state | enum | Verification result | `pending`, `verified`, `failed` |
| rollback_eligible | boolean | Can be used for rollback | true/false |

## Relationships

```text
AgentIdentity 1--* AgentEndpoint
AgentIdentity 1--1 AgentRegistryEntry
AgentIdentity 1--1 AgentCredentialSet
AgentIdentity 1--* StateSnapshot
HandoffEnvelope 1--1 HandoffExecution
HandoffExecution 1--* AcknowledgementRecord
HandoffExecution 1--* AuditEvent
AgentIdentity 1--* AuditEvent
```

## Derived Views

### Fleet Reachability View

Derived from `AgentRegistryEntry.reachability` + recent `AuditEvent` health data to answer:
- which agents can receive work now
- which agents are auth-blocked
- which agents are quarantined

### Handoff Incident View

Derived from `HandoffExecution`, `AcknowledgementRecord`, and `AuditEvent` to answer:
- whether a handoff is late, lost, or terminal
- whether a user-visible message was emitted without machine-facing completion
- whether replay is safe

## Validation Rules

- `agent_id`, domain, and Telegram bot identity must remain globally unique across active agents.
- Any `recipient_agent_id` in `HandoffEnvelope` must exist in `AgentRegistryEntry` and expose the requested capability.
- `HandoffExecution` cannot skip mandatory states.
- `AcknowledgementRecord.ack_type=terminal` requires a terminal `HandoffExecution.state`.
- `StateSnapshot.rollback_eligible=true` requires `verification_state=verified`.
