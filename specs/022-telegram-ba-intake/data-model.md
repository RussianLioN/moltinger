# Data Model: Factory Business Analyst Intake

## Overview

This feature adds a discovery-first layer ahead of the existing factory pipeline:

`factory interface dialogue -> discovery session -> draft brief -> confirmed brief -> factory handoff -> concept pack`

The model deliberately separates business-facing discovery from downstream concept approval, swarm execution, and playground packaging.

## Entities

### 1. DiscoverySession

Represents one active or historical factory-owned requirements interview for a future AI-agent project.

**Fields**

- `discovery_session_id`
- `project_key`
- `request_channel`
- `requester_identity`
- `working_language`
- `status`
- `current_topic`
- `next_recommended_action`
- `latest_brief_version`
- `created_at`
- `updated_at`

**Status values**

- `new`
- `in_progress`
- `awaiting_user_reply`
- `awaiting_clarification`
- `awaiting_confirmation`
- `confirmed`
- `reopened`
- `abandoned`

### 2. ConversationTurn

One recorded turn inside the discovery dialogue.

**Fields**

- `turn_id`
- `discovery_session_id`
- `actor`
- `turn_type`
- `raw_text`
- `extracted_topics`
- `linked_clarification_ids`
- `recorded_at`

**Actor values**

- `user`
- `agent`
- `system`

**Turn type values**

- `idea_statement`
- `clarifying_question`
- `business_answer`
- `summary`
- `confirmation_request`
- `confirmation_reply`
- `revision_request`

### 3. RequirementTopic

One named requirement area tracked during discovery.

**Fields**

- `topic_id`
- `discovery_session_id`
- `topic_name`
- `category`
- `status`
- `summary`
- `source_turn_ids`
- `last_updated_at`

**Category values**

- `problem`
- `actor`
- `workflow`
- `goal`
- `user_story`
- `input`
- `output`
- `rule`
- `exception`
- `constraint`
- `success_metric`
- `risk`

**Status values**

- `unasked`
- `partial`
- `clarified`
- `confirmed`
- `unresolved`

### 4. ClarificationItem

One missing, ambiguous, or contradictory point that must be resolved or explicitly carried as an open question.

**Fields**

- `clarification_item_id`
- `discovery_session_id`
- `topic_name`
- `reason`
- `status`
- `question_text`
- `opened_at`
- `resolved_at`

**Reason values**

- `missing_information`
- `ambiguous_answer`
- `contradictory_examples`
- `scope_conflict`
- `unsafe_data_example`

**Status values**

- `open`
- `answered`
- `deferred`
- `resolved`

### 5. ExampleCase

One user-provided case used to ground future agent behavior.

**Fields**

- `example_case_id`
- `discovery_session_id`
- `case_type`
- `input_summary`
- `expected_output_summary`
- `linked_rules`
- `exception_notes`
- `data_safety_status`

**Case type values**

- `representative`
- `edge_case`
- `exception_case`

**Data safety status values**

- `sanitized`
- `synthetic`
- `needs_redaction`

### 6. RequirementBrief

The structured, reviewable brief generated from the discovery conversation.

**Fields**

- `brief_id`
- `discovery_session_id`
- `project_key`
- `version`
- `problem_statement`
- `target_users`
- `current_process`
- `desired_outcome`
- `user_story`
- `input_examples`
- `expected_outputs`
- `business_rules`
- `exceptions`
- `constraints`
- `success_metrics`
- `open_risks`
- `status`
- `created_at`
- `updated_at`

**Status values**

- `draft`
- `awaiting_confirmation`
- `confirmed`
- `superseded`
- `reopened`

### 7. BriefRevision

One meaningful change set applied to a brief version before or after confirmation.

**Fields**

- `brief_revision_id`
- `brief_id`
- `version`
- `change_reason`
- `changed_sections`
- `requested_by`
- `created_at`

### 8. ConfirmationSnapshot

Immutable record of one explicit user confirmation event for a brief version.

**Fields**

- `confirmation_snapshot_id`
- `brief_id`
- `brief_version`
- `confirmed_by`
- `confirmation_text`
- `confirmed_at`
- `status`

**Status values**

- `active`
- `superseded`
- `revoked`

### 9. FactoryHandoffRecord

Canonical upstream record passed from confirmed discovery into the existing concept-pack pipeline.

**Fields**

- `factory_handoff_id`
- `discovery_session_id`
- `brief_id`
- `brief_version`
- `confirmation_snapshot_id`
- `handoff_status`
- `next_stage`
- `downstream_target`
- `created_at`
- `consumed_at`

**Handoff status values**

- `ready`
- `consumed`
- `blocked`
- `superseded`

### 10. RecoverySnapshot

Derived runtime metadata that explains how an interrupted discovery session or reopened brief was restored.

**Fields**

- `resumed`
- `resumed_from_status`
- `restored_status`
- `current_topic`
- `pending_question`
- `resolved_topic_names`
- `remaining_topics`
- `open_clarification_ids`
- `latest_brief_version`
- `latest_confirmed_brief_version`
- `summary_text`

## Relationships

- One `DiscoverySession` contains many `ConversationTurn` records.
- One `DiscoverySession` tracks many `RequirementTopic`, `ClarificationItem`, and `ExampleCase` records.
- One `DiscoverySession` produces many `RequirementBrief` versions over time, but only one current active draft or confirmed version.
- One confirmed `RequirementBrief` may have one active `ConfirmationSnapshot`.
- Archived confirmation snapshots are preserved in `confirmation_history` when a confirmed brief is reopened.
- One active `ConfirmationSnapshot` may unlock one `FactoryHandoffRecord`.
- Archived handoff records are preserved in `handoff_history` when a previously confirmed brief is superseded by a newer version.
- One `FactoryHandoffRecord` becomes the upstream source for downstream concept-pack generation in the existing factory flow.

## Clarification Notes

- `request_channel` identifies the active interface adapter, not the identity of the agent itself.
- The agent remains one factory-owned business-analyst role on `Moltis`, regardless of whether the user currently interacts through `Telegram`, `Moltinger UI`, `Moltis UI`, or a future factory UI.

## State Transitions

### DiscoverySession

`new -> in_progress -> awaiting_clarification -> awaiting_confirmation -> confirmed`

Optional branches:

- `in_progress -> abandoned`
- `confirmed -> reopened -> awaiting_clarification`

### RequirementBrief

`draft -> awaiting_confirmation -> confirmed -> superseded`

Optional branch:

- `confirmed -> reopened -> draft`

### FactoryHandoffRecord

`blocked -> ready -> consumed`

Optional branch:

- `ready -> superseded`

## Model Rules

- No `FactoryHandoffRecord` may reach `ready` unless there is an active `ConfirmationSnapshot` for the exact brief version.
- A reopened brief must create a new version instead of overwriting an already confirmed version.
- Reopening a confirmed brief must archive the prior active `ConfirmationSnapshot` and current `FactoryHandoffRecord` instead of deleting them.
- Resume responses should expose `RecoverySnapshot` metadata whenever the runtime restores prior discovery state instead of starting from a fresh raw idea.
- `ClarificationItem` records may remain open only if they are explicitly represented in `RequirementBrief.open_risks`.
- `ExampleCase` records marked `needs_redaction` cannot be treated as safe prototype examples until replaced or sanitized.
