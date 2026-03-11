# Data Model: Production-Aware Remote UAT Hardening

## RemoteUATRun

- **Purpose**: Represents one operator-initiated production-aware verification attempt.
- **Fields**:
  - `run_id`: unique identifier for the verification attempt
  - `target_environment`: named target being checked, such as production
  - `trigger_source`: manual trigger source, such as CLI or workflow dispatch
  - `authoritative_path`: canonical path used for verdict generation
  - `started_at`: run start timestamp
  - `finished_at`: run end timestamp
  - `verdict`: pass or fail outcome for the authoritative path
  - `stage`: latest stage reached before completion or failure
  - `production_transport_mode`: recorded transport mode of the deployed system
  - `operator_intent`: reason for the run, such as post-deploy verification or rerun after fix

## DiagnosticArtifact

- **Purpose**: Review-safe output document for operators and RCA.
- **Fields**:
  - `run`: embedded `RemoteUATRun` summary
  - `failure_classification`: normalized failure category for failed runs
  - `attribution_evidence`: correlation details proving or disproving request/reply linkage
  - `diagnostic_context`: stage-specific context useful for investigation
  - `artifact_status`: artifact generation outcome
  - `redactions_applied`: record of sensitive fields removed or masked
  - `follow_up_hint`: suggested next operational step based on verdict

## AttributionEvidence

- **Purpose**: Demonstrates whether the observed chat activity belongs to the current run.
- **Fields**:
  - `quiet_window_ms`: quiet-window duration used before probe attribution
  - `baseline_max_message_id`: latest known message boundary before send
  - `last_pre_send_activity`: most recent message seen before the probe send point
  - `sent_message_fingerprint`: normalized representation of the sent probe
  - `sent_message_id`: identified sent-message boundary for the run
  - `matched_reply_fingerprint`: normalized representation of the attributed reply
  - `matched_reply_id`: identified reply boundary for the run
  - `reply_observed_at`: timestamp when the reply was attributed
  - `attribution_confidence`: whether attribution is proven, absent, or invalidated by noise

## FailureClassification

- **Purpose**: Stable taxonomy for deterministic remote-UAT failures.
- **Fields**:
  - `code`: normalized failure identifier
  - `stage`: execution stage where failure occurred
  - `summary`: operator-facing description
  - `actionability`: whether the failure is immediately actionable, diagnostic-only, or environment-related
  - `fallback_relevant`: whether optional secondary diagnostics may help
- **Expected categories**:
  - `missing_session_state`
  - `ui_drift`
  - `chat_open_failure`
  - `stale_chat_noise`
  - `send_failure`
  - `bot_no_response`
  - `fallback_unavailable`

## FallbackAssessment

- **Purpose**: Optional secondary diagnostic result captured only when the operator requests additional evidence beyond the authoritative Telegram Web verdict.
- **Fields**:
  - `requested`: whether fallback diagnostics were requested
  - `path_used`: secondary diagnostic path used, if any
  - `prerequisites_present`: whether the secondary path prerequisites were available
  - `outcome`: result of the secondary diagnostic attempt
  - `decision_note`: operator-facing note about whether fallback remains worth enabling after primary-path remediation

## State Transitions

- `RemoteUATRun.verdict`: `in_progress` -> `passed` or `failed`
- `AttributionEvidence.attribution_confidence`: `unknown` -> `proven` or `invalidated`
- `FallbackAssessment.outcome`: `not_requested` -> `unavailable`, `completed`, or `not_needed`
