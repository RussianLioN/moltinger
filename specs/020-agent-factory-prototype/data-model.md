# Data Model: Agent Factory Prototype

## Overview

This feature models one end-to-end prototype path:

`idea -> concept pack -> defense -> approved concept -> swarm run -> playground package -> feedback / MVP1 handoff`

The model is deliberately source-first and workflow-oriented. It preserves traceability between user intent, concept artifacts, approval state, production evidence, and final playground output.

## Entities

### 1. ConceptRequest

Represents the raw intake request as it first enters the factory.

**Fields**

- `concept_request_id`
- `request_channel`
- `requester_identity`
- `request_language`
- `raw_problem_statement`
- `captured_answers`
- `missing_information_topics`
- `created_at`
- `status`

**Status values**

- `new`
- `clarifying`
- `ready_for_pack`
- `abandoned`

### 2. ConceptRecord

Canonical, versioned representation of one future agent concept after intake is sufficiently structured.

**Fields**

- `concept_id`
- `source_request_id`
- `title`
- `problem_statement`
- `target_users`
- `current_process`
- `success_metrics`
- `constraints`
- `assumptions`
- `open_risks`
- `applied_factory_patterns`
- `current_version`
- `decision_state`
- `review_history`
- `feedback_history`
- `production_approval`
- `created_at`
- `updated_at`

**Decision state values**

- `draft`
- `in_defense`
- `pending_decision`
- `rework_requested`
- `approved`
- `rejected`
- `in_production`
- `playground_ready`
- `archived`

### 3. ArtifactSet

Synchronized trio of concept artifacts attached to one concept record version.

**Fields**

- `artifact_set_id`
- `concept_id`
- `concept_version`
- `project_doc_artifact_id`
- `agent_spec_artifact_id`
- `presentation_artifact_id`
- `sync_status`
- `generated_at`

**Sync status values**

- `aligned`
- `drift_detected`
- `partial`

### 4. ArtifactVersion

One immutable revision of one artifact inside the concept pack.

**Fields**

- `artifact_id`
- `concept_id`
- `concept_version`
- `artifact_type`
- `revision`
- `working_source_ref`
- `download_ref`
- `generated_from`
- `change_reason`
- `created_at`

**Artifact type values**

- `project_doc`
- `agent_spec`
- `presentation`

### 5. DefenseReview

Recorded result of one defense round for a specific concept version.

**Fields**

- `review_id`
- `concept_id`
- `concept_version`
- `outcome`
- `reviewers`
- `feedback_summary`
- `decision_notes`
- `reviewed_at`

**Outcome values**

- `approved`
- `rework_requested`
- `rejected`
- `pending_decision`

### 6. FeedbackItem

One structured feedback point captured during or after concept review.

**Fields**

- `feedback_item_id`
- `review_id`
- `category`
- `severity`
- `summary`
- `affected_artifacts`
- `required_action`
- `resolution_state`

**Resolution state values**

- `open`
- `accepted`
- `deferred`
- `resolved`

### 7. ProductionApproval

Explicit authorization that unlocks swarm execution for one approved concept version.

**Fields**

- `approval_id`
- `concept_id`
- `approved_version`
- `approved_by`
- `approval_basis`
- `approved_at`
- `expires_at`
- `status`

**Status values**

- `active`
- `superseded`
- `revoked`

### 8. SwarmRun

Represents one autonomous production attempt created from one approved concept version.

**Fields**

- `swarm_run_id`
- `concept_id`
- `concept_version`
- `approval_id`
- `requested_at`
- `started_at`
- `completed_at`
- `run_status`
- `requested_roles`
- `current_stage`
- `terminal_summary`
- `audit_trail`

**Run status values**

- `queued`
- `running`
- `blocked`
- `failed`
- `completed`
- `cancelled`

### 9. SwarmStageExecution

Role-owned stage inside the swarm run.

**Fields**

- `stage_execution_id`
- `swarm_run_id`
- `stage_name`
- `role_owner`
- `depends_on`
- `status`
- `evidence_refs`
- `started_at`
- `ended_at`
- `failure_class`

**Stage name values**

- `coding`
- `testing`
- `validation`
- `audit`
- `assembly`

**Status values**

- `pending`
- `running`
- `blocked`
- `failed`
- `completed`

### 10. PlaygroundPackage

Runnable result bundle published after a successful swarm run.

**Fields**

- `playground_package_id`
- `swarm_run_id`
- `container_ref`
- `launch_instructions_ref`
- `data_profile`
- `evidence_bundle_ref`
- `published_at`
- `review_status`

**Data profile values**

- `synthetic`
- `test`

**Review status values**

- `ready_for_demo`
- `feedback_pending`
- `rework_requested`

### 11. EscalationPacket

Operator-facing incident bundle created only for blocker or integrity failures.

**Fields**

- `escalation_id`
- `concept_id`
- `swarm_run_id`
- `stage_name`
- `severity`
- `summary`
- `recommended_action`
- `evidence_refs`
- `evidence_bundle_ref`
- `evidence_manifest_ref`
- `assigned_to`
- `created_at`
- `status`

**Status values**

- `open`
- `acknowledged`
- `resolved`
- `dismissed`

### 12. KnowledgeMirrorRecord

Tracks provenance and freshness of the in-repo ASC documentation mirror.

**Fields**

- `mirror_record_id`
- `upstream_repository`
- `verified_commit`
- `mirror_scope`
- `refreshed_at`
- `status`

**Status values**

- `fresh`
- `stale`
- `missing`

### 13. StatusPublication

Review-safe status snapshot derived from a concept pack and, when available, one swarm run.

**Fields**

- `concept_id`
- `concept_version`
- `user_visible_status`
- `operator_status`
- `current_stage`
- `next_action`
- `active_escalation_count`
- `evidence_refs`
- `audit_event_count`
- `published_at`

**User visible status values**

- `concept`
- `defense`
- `rework`
- `production`
- `playground_ready`
- `needs_admin_attention`

## State Transitions

### ConceptRecord

```text
draft
  -> in_defense
  -> archived

in_defense
  -> approved
  -> rework_requested
  -> rejected

rework_requested
  -> draft
  -> in_defense

approved
  -> in_production
  -> archived

in_production
  -> playground_ready
  -> rework_requested
  -> archived

playground_ready
  -> rework_requested
  -> archived
```

### SwarmRun

```text
queued -> running -> completed
queued -> running -> blocked
queued -> running -> failed
queued -> cancelled
blocked -> running
blocked -> failed
```

### ArtifactSet Sync

```text
partial -> aligned
aligned -> drift_detected
drift_detected -> aligned
```

## Invariants

- A `SwarmRun` cannot exist without an `active` `ProductionApproval`.
- A `ProductionApproval` must target one specific `ConceptRecord.current_version`.
- Every `ArtifactSet` must contain exactly one current project doc, one current agent spec, and one current presentation for its concept version.
- Every `PlaygroundPackage` must reference a completed `SwarmRun`.
- Every `EscalationPacket` must point to a concept or swarm stage with an evidence reference.
- `KnowledgeMirrorRecord.status=missing` blocks planning readiness for this feature.
