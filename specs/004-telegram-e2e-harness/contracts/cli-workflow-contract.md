# Contract: CLI and Workflow Interface

## CLI Command

Path: `scripts/telegram-e2e-on-demand.sh`

### Arguments

- `--mode synthetic|real_user` (required)
- `--message "<text>"` (required)
- `--timeout-sec <int>` (optional, default 30)
- `--output <path>` (optional, default `${TMPDIR:-/tmp}/telegram-e2e-result.json`)
- `--moltis-url <url>` (optional, default `http://localhost:13131`)
- `--moltis-password-env <ENV_NAME>` (optional, default `MOLTIS_PASSWORD`)
- `--verbose` (optional)

### Exit Codes

- `0`: completed with report
- `2`: precondition/config error
- `3`: timeout/no observed response
- `4`: upstream/auth error

## Workflow Dispatch

Path: `.github/workflows/telegram-e2e-on-demand.yml`

### Inputs

- `mode`
- `message`
- `timeout_sec`
- `moltis_url`
- `artifact_name`
- `verbose`

### Secrets

- `MOLTIS_PASSWORD` (required for synthetic)
- `TELEGRAM_TEST_API_ID` (required for `real_user`)
- `TELEGRAM_TEST_API_HASH` (required for `real_user`)
- `TELEGRAM_TEST_SESSION` (required for `real_user`)
- `TELEGRAM_TEST_BOT_USERNAME` (optional, default `@moltinger_bot`)

### Artifacts

- `${TMPDIR:-/tmp}/telegram-e2e-result.json` by default, or the explicit `--output` path
- optional `telegram-e2e.log`
- Sample artifact: `specs/004-telegram-e2e-harness/contracts/sample-result-synthetic.json`

## Result Schema

```json
{
  "run_id": "string",
  "mode": "synthetic|real_user",
  "trigger_source": "cli|workflow_dispatch",
  "message": "string",
  "started_at": "ISO-8601",
  "finished_at": "ISO-8601",
  "duration_ms": 0,
  "transport": "string",
  "observed_response": "string",
  "status": "completed|timeout|precondition_failed|upstream_failed",
  "error_code": "string",
  "error_message": "string",
  "context": {}
}
```
