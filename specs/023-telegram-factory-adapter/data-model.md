# Data Model: Telegram Factory Adapter

## Overview

This feature adds the preserved follow-up Telegram interface layer on top of the existing factory runtime:

`Telegram update -> Telegram adapter -> discovery session -> confirmed brief -> factory handoff -> concept pack -> Telegram delivery`

The model deliberately avoids redefining the core entities already owned by:

- `022-telegram-ba-intake` for discovery and confirmed brief logic
- `020-agent-factory-prototype` for downstream concept-pack generation

Instead, this feature adds the adapter-side transport, routing, delivery, and recovery entities needed to expose that runtime to a real user in Telegram.

## Entities

### 1. TelegramUpdateEnvelope

Represents one normalized inbound Telegram update before it is routed into the factory runtime.

**Fields**

- `telegram_update_id`
- `bot_id`
- `chat_id`
- `chat_type`
- `message_id`
- `from_user_id`
- `from_display_name`
- `language_code`
- `message_text`
- `command_text`
- `callback_data`
- `received_at`
- `transport_mode`

**Transport mode values**

- `webhook`
- `synthetic_fixture`
- `live_probe`

### 2. TelegramAdapterSession

Represents one Telegram-bound adapter session that maps a user/chat context to the currently active factory project flow.

**Fields**

- `telegram_adapter_session_id`
- `chat_id`
- `from_user_id`
- `status`
- `active_project_key`
- `active_discovery_session_id`
- `active_brief_id`
- `last_seen_update_id`
- `last_seen_message_id`
- `last_user_message_at`
- `last_agent_message_at`
- `created_at`
- `updated_at`

**Status values**

- `idle`
- `routing_to_discovery`
- `awaiting_user_reply`
- `awaiting_confirmation`
- `handoff_running`
- `delivering_artifacts`
- `completed`
- `error`

### 3. ActiveProjectPointer

Represents the adapter-level pointer that decides which project or brief the next Telegram message belongs to.

**Fields**

- `pointer_id`
- `telegram_adapter_session_id`
- `project_key`
- `selection_mode`
- `linked_discovery_session_id`
- `linked_brief_id`
- `linked_brief_version`
- `pointer_status`
- `updated_at`

**Selection mode values**

- `new_project`
- `continue_active`
- `review_brief`
- `reopen_brief`
- `status_only`

**Pointer status values**

- `active`
- `superseded`
- `closed`

### 4. TelegramIntent

Represents one user-visible control intent extracted from a Telegram message.

**Fields**

- `telegram_intent_id`
- `telegram_adapter_session_id`
- `intent_type`
- `raw_text`
- `normalized_payload`
- `confidence`
- `recorded_at`

**Intent type values**

- `start_project`
- `continue_project`
- `answer_discovery_question`
- `request_brief_review`
- `request_brief_correction`
- `confirm_brief`
- `reopen_brief`
- `request_status`
- `request_help`

### 5. TelegramReplyPayload

Represents one adapter-generated outbound reply prepared for Telegram delivery.

**Fields**

- `telegram_reply_payload_id`
- `telegram_adapter_session_id`
- `reply_kind`
- `rendered_text`
- `chunk_index`
- `chunk_total`
- `parse_mode`
- `reply_markup`
- `linked_discovery_session_id`
- `linked_brief_id`
- `linked_handoff_id`
- `created_at`

**Reply kind values**

- `discovery_question`
- `clarification_prompt`
- `brief_summary`
- `confirmation_prompt`
- `status_update`
- `delivery_ack`
- `error_message`

### 6. TelegramArtifactDelivery

Represents one user-facing attempt to deliver a generated artifact back into Telegram.

**Fields**

- `telegram_artifact_delivery_id`
- `telegram_adapter_session_id`
- `project_key`
- `artifact_kind`
- `artifact_path`
- `telegram_file_id`
- `delivery_status`
- `delivery_message_id`
- `delivery_error_code`
- `created_at`
- `delivered_at`

**Artifact kind values**

- `project_doc`
- `agent_spec`
- `presentation`
- `bundle_manifest`

**Delivery status values**

- `pending`
- `sent`
- `failed`
- `retried`

### 7. TelegramAdapterAuditRecord

Represents one correlation-friendly audit snapshot for adapter-level routing and downstream orchestration.

**Fields**

- `telegram_adapter_audit_id`
- `telegram_adapter_session_id`
- `project_key`
- `correlation_id`
- `stage`
- `stage_status`
- `summary_text`
- `linked_discovery_session_id`
- `linked_brief_id`
- `linked_handoff_id`
- `linked_concept_manifest_id`
- `recorded_at`

**Stage values**

- `update_received`
- `intent_resolved`
- `discovery_routed`
- `brief_rendered`
- `brief_confirmed`
- `handoff_started`
- `artifacts_generated`
- `artifacts_delivered`
- `adapter_failed`

**Stage status values**

- `started`
- `completed`
- `blocked`
- `failed`

### 8. TelegramResumeSnapshot

Represents the minimum adapter snapshot required to resume an interrupted Telegram conversation without losing project context.

**Fields**

- `telegram_resume_snapshot_id`
- `telegram_adapter_session_id`
- `active_project_key`
- `pending_question_text`
- `pending_clarification_id`
- `last_brief_version`
- `resume_status`
- `captured_at`

**Resume status values**

- `ready_to_resume`
- `awaiting_user_reply`
- `awaiting_confirmation`
- `handoff_in_progress`

## Relationships

- One `TelegramAdapterSession` may reference one active `DiscoverySession` from `022` at a time.
- One `ActiveProjectPointer` belongs to one `TelegramAdapterSession`.
- Many `TelegramIntent` records can belong to one `TelegramAdapterSession`.
- Many `TelegramReplyPayload` records can belong to one `TelegramAdapterSession`.
- Many `TelegramArtifactDelivery` records can belong to one `TelegramAdapterSession`.
- Many `TelegramAdapterAuditRecord` records can belong to one `TelegramAdapterSession`.
- One `TelegramResumeSnapshot` captures resumable state for one `TelegramAdapterSession`.
- Adapter entities link downstream to:
  - `DiscoverySession`
  - `RequirementBrief`
  - `ConfirmationSnapshot`
  - `FactoryHandoffRecord`
  - downstream concept-pack manifest

## State Boundaries

### Adapter session lifecycle

`idle -> routing_to_discovery -> awaiting_user_reply -> awaiting_confirmation -> handoff_running -> delivering_artifacts -> completed`

Failure branch:

`any active state -> error`

Resume branch:

`awaiting_user_reply | awaiting_confirmation | handoff_running -> resume snapshot -> restored active state`

### Project pointer lifecycle

`active -> superseded -> closed`

Trigger examples:

- new project starts: new pointer becomes `active`
- reopened brief: previous pointer becomes `superseded`, new pointer becomes `active`
- project fully handed off and archived: pointer can move to `closed`

### Artifact delivery lifecycle

`pending -> sent`

Failure branch:

`pending -> failed -> retried -> sent | failed`

## Validation Rules

- A Telegram user reply cannot route downstream if there is no `ActiveProjectPointer`.
- `confirm_brief` intent is valid only when the linked brief is in `awaiting_confirmation`.
- `reopen_brief` must create a new active pointer version rather than mutating a previously confirmed brief in place.
- `TelegramArtifactDelivery` cannot start until the linked `FactoryHandoffRecord` is `ready` or `consumed` and the downstream concept-pack generation succeeds.
- User-facing `TelegramReplyPayload` records must never contain repo filesystem paths, raw stack traces, or secrets.

## External References

- Discovery core entities remain defined by [../022-telegram-ba-intake/data-model.md](../022-telegram-ba-intake/data-model.md)
- Downstream concept-pack lifecycle remains defined by [../020-agent-factory-prototype/data-model.md](../020-agent-factory-prototype/data-model.md)
