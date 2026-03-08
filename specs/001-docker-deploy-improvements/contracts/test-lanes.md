# Test Contract: Lane-Based Runner

**Feature**: 001-docker-deploy-improvements
**Canonical entrypoint**: `./tests/run.sh --lane <lane-or-group>`

## Purpose

Этот контракт определяет единственный поддерживаемый public interface для запуска тестов после перехода от taxonomy `unit/integration/security/e2e` к dependency-based lanes.

## Canonical CLI

```bash
./tests/run.sh --lane <lane-or-group> [--json] [--junit] [--filter PATTERN] [--verbose] [--live] [--compose-project NAME] [--keep-stack]
```

## Supported Lanes

| Lane | Description | Default Gate |
| --- | --- | --- |
| `static` | Config/render/static validation | PR |
| `component` | Production shell logic component tests | PR |
| `integration_local` | Local API integration on hermetic stack | PR |
| `security_api` | Auth/input/rate-limit API security on hermetic stack | PR |
| `mcp_fake` | MCP lifecycle via fake JSON-RPC harness | PR |
| `e2e_browser` | Real browser transport via Playwright | `push main` |
| `resilience` | Destructive recovery/failover scenarios | nightly/manual |
| `live_external` | Telegram, real LLM providers, real MCP backends | nightly/manual |

## Supported Groups

| Group | Expansion |
| --- | --- |
| `pr` | `static`, `component`, `integration_local`, `security_api`, `mcp_fake` |
| `main` | `pr` + `e2e_browser` |
| `nightly` | `resilience`, `live_external`, `security_runtime_smoke` |
| `all` | `main` + `nightly` |
| `unit_legacy` | `static`, `component` |
| `integration_legacy` | `integration_local`, `provider_live`, `telegram_live`, `mcp_real` |
| `security_legacy` | `security_api`, `security_runtime_smoke` |
| `e2e_legacy` | `e2e_browser`, `resilience` |

## Runtime Rules

- Blocking lanes must be runnable from a clean checkout without production secrets.
- Blocking lanes must not implicitly read `/opt/moltinger/.env`.
- `integration_local`, `security_api`, and `e2e_browser` may recurse into `compose.test.yml` automatically.
- Live-only lanes require explicit `--live` or `TEST_LIVE=1`.
- Destructive suites must use isolated compose projects and may not mutate shared runtime stacks.

## Environment Variables

| Variable | Meaning |
| --- | --- |
| `TEST_REPORT_DIR` | Output directory for reports and diagnostics |
| `TEST_ENV_FILE` | Explicit env file for opt-in live runs |
| `TEST_BASE_URL` | Base URL used by HTTP or browser suites |
| `TEST_TIMEOUT` | Timeout budget for suites/runtime |
| `TEST_LIVE` | Enables live-only suites when set to `1` |
| `COMPOSE_PROJECT_NAME` | Compose project name |

## Exit Codes

| Code | Meaning |
| --- | --- |
| `0` | All selected cases passed |
| `1` | At least one selected case failed |
| `2` | All selected work skipped or unrunnable |
| `3` | Harness or invocation error |

## Report Contract

`summary.json` is the authoritative CI/gate artifact.

### Required top-level fields

```json
{
  "lane": "pr",
  "timestamp": "2026-03-08T12:00:00Z",
  "status": "passed",
  "summary": {
    "total_suites": 5,
    "total_cases": 17,
    "passed": 17,
    "failed": 0,
    "skipped": 0
  },
  "suites": [],
  "cases": []
}
```

### Status values

- Aggregate `status`: `passed`, `failed`, `skipped`
- Per-case `status`: `passed`, `failed`, `skipped`, `error`

### Non-negotiable semantics

- `summary.total_cases` counts test cases, not files.
- `skipped` must be explicit and must not be collapsed into success.
- Full-skip suites return `2` from the runner and remain visible in `summary.json`.
- `junit.xml` must be derived from the same case-level source of truth as `summary.json`.

## Diagnostics

On failure, the report directory must preserve enough context for RCA:

- `summary.json`
- `junit.xml` when requested
- `suites/*.json`
- `logs/*.log`
- `diagnostics/compose-ps.txt`
- `diagnostics/compose-logs.txt`
- any captured response bodies or timeout phase markers written by suites
