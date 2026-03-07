# Data Model: On-Demand Telegram E2E Harness

## Entity: E2ETestRun

- `run_id` (string, required): unique run identifier
- `mode` (enum, required): `synthetic` | `real_user`
- `trigger_source` (enum, required): `cli` | `workflow_dispatch`
- `message` (string, required): input message payload
- `started_at` (datetime, required)
- `finished_at` (datetime, required)
- `duration_ms` (integer, required)
- `transport` (string, required): execution transport name

## Entity: E2EReportArtifact

- `status` (enum, required):
  - `completed`
  - `timeout`
  - `precondition_failed`
  - `upstream_failed`
- `observed_response` (string, optional): textual/JSON-stringified observed response
- `error_code` (string, optional)
- `error_message` (string, optional)
- `context` (object, required): structured diagnostic metadata (no secrets)

## Entity: ExecutionContext

- `moltis_url` (string, optional)
- `login_http_code` (integer, optional)
- `send_http_code` (integer, optional)
- `poll_attempts` (integer, optional)
- `timeout_sec` (integer, optional)
- `missing_prerequisites` (array[string], optional)
- `bot_username` (string, optional)
- `bot_user_id` (integer, optional)
- `chat_id` (integer, optional)
- `sent_message_id` (integer, optional)
- `reply_message_id` (integer, optional)
- `notes` (array[string], optional)
