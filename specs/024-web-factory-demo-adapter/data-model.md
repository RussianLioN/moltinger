# Data Model: Web Factory Demo Adapter

## Overview

This feature adds the primary browser-facing demo layer on top of the existing factory runtime:

`browser session -> web adapter -> discovery session -> confirmed brief -> factory handoff -> concept pack -> browser downloads`

The model deliberately avoids redefining the core entities already owned by:

- `022-telegram-ba-intake` for discovery and confirmed brief logic
- `020-agent-factory-prototype` for downstream concept-pack generation
- `023-telegram-factory-adapter` for future Telegram transport concerns

Instead, this feature adds the browser-access, session, rendering, and download entities needed to expose that runtime through a dedicated web demo surface.

## Entities

### 1. DemoAccessGrant

Represents one controlled access credential or operator-issued entry grant for the demo surface.

**Fields**

- `demo_access_grant_id`
- `grant_type`
- `grant_value_hash`
- `issued_by`
- `issued_for`
- `status`
- `expires_at`
- `created_at`

**Grant type values**

- `shared_demo_token`
- `single_use_token`
- `allowlisted_session`

**Status values**

- `active`
- `consumed`
- `revoked`
- `expired`

### 2. WebDemoSession

Represents one browser-bound adapter session that maps a user access context to the current factory project flow.

**Fields**

- `web_demo_session_id`
- `session_cookie_id`
- `access_grant_id`
- `status`
- `active_project_key`
- `active_discovery_session_id`
- `active_brief_id`
- `last_user_turn_at`
- `last_agent_turn_at`
- `created_at`
- `updated_at`

**Status values**

- `gate_pending`
- `active`
- `awaiting_user_reply`
- `awaiting_confirmation`
- `handoff_running`
- `download_ready`
- `completed`
- `error`

### 3. BrowserProjectPointer

Represents the adapter-level pointer that decides which project or brief the next browser action belongs to.

**Fields**

- `pointer_id`
- `web_demo_session_id`
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
- `download_ready`
- `status_only`

**Pointer status values**

- `active`
- `superseded`
- `closed`

### 4. WebConversationEnvelope

Represents one normalized inbound browser turn and the correlated adapter response payload.

**Fields**

- `web_conversation_envelope_id`
- `web_demo_session_id`
- `request_id`
- `transport_mode`
- `user_text`
- `ui_action`
- `normalized_payload`
- `linked_discovery_session_id`
- `linked_brief_id`
- `received_at`

**Transport mode values**

- `form_post`
- `fetch_request`
- `synthetic_fixture`
- `browser_probe`

**UI action values**

- `start_project`
- `submit_turn`
- `request_brief_review`
- `request_brief_correction`
- `confirm_brief`
- `reopen_brief`
- `request_status`
- `download_artifact`

### 5. WebReplyCard

Represents one rendered user-visible unit in the browser UI.

**Fields**

- `web_reply_card_id`
- `web_demo_session_id`
- `card_kind`
- `title`
- `body_text`
- `section_id`
- `action_hints`
- `linked_discovery_session_id`
- `linked_brief_id`
- `linked_handoff_id`
- `created_at`

**Card kind values**

- `discovery_question`
- `clarification_prompt`
- `brief_summary_section`
- `confirmation_prompt`
- `status_update`
- `download_prompt`
- `error_message`

### 6. BriefDownloadArtifact

Represents one downloadable artifact made available to the browser after downstream generation.

**Fields**

- `brief_download_artifact_id`
- `web_demo_session_id`
- `project_key`
- `artifact_kind`
- `artifact_path`
- `download_token`
- `download_status`
- `size_bytes`
- `created_at`
- `available_at`

**Artifact kind values**

- `project_doc`
- `agent_spec`
- `presentation`
- `bundle_manifest`

**Download status values**

- `pending`
- `available`
- `expired`
- `failed`

### 7. WebDemoStatusSnapshot

Represents one safe status projection for the current browser session and project.

**Fields**

- `web_demo_status_snapshot_id`
- `web_demo_session_id`
- `project_key`
- `user_visible_status`
- `next_recommended_action`
- `brief_version`
- `download_readiness`
- `needs_operator_attention`
- `captured_at`

**User visible status values**

- `discovery_in_progress`
- `awaiting_clarification`
- `awaiting_confirmation`
- `confirmed`
- `handoff_running`
- `downloads_ready`
- `needs_attention`

### 8. WebDemoAuditRecord

Represents one correlation-friendly audit snapshot for adapter-level routing and downstream orchestration.

**Fields**

- `web_demo_audit_id`
- `web_demo_session_id`
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

- `access_granted`
- `browser_turn_received`
- `discovery_routed`
- `brief_rendered`
- `brief_confirmed`
- `handoff_started`
- `artifacts_generated`
- `downloads_published`
- `adapter_failed`

**Stage status values**

- `started`
- `completed`
- `blocked`
- `failed`

## Relationships

- One `DemoAccessGrant` may open many `WebDemoSession` records if shared access is allowed, but each session references exactly one active grant.
- One `WebDemoSession` may reference one active `DiscoverySession` from `022` at a time.
- One `BrowserProjectPointer` belongs to one `WebDemoSession`.
- Many `WebConversationEnvelope` records can belong to one `WebDemoSession`.
- Many `WebReplyCard` records can belong to one `WebDemoSession`.
- Many `BriefDownloadArtifact` records can belong to one `WebDemoSession`.
- Many `WebDemoAuditRecord` records can belong to one `WebDemoSession`.
- One `WebDemoStatusSnapshot` captures the latest safe status view for one `WebDemoSession`.
