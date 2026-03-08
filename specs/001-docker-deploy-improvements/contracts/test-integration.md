# Test Contract: Integration Compatibility

**Feature**: 001-docker-deploy-improvements
**Compatibility scope**: historical `integration`-family test references

## Purpose

Некоторые test files всё ещё ссылаются на `contracts/test-integration.md`. Этот документ сохраняет совместимость со старыми ссылками, но canonical model теперь lane-based.

## Mapping To Canonical Lanes

| Historical family | Canonical lane | Mode |
| --- | --- | --- |
| API integration | `integration_local` | blocking |
| MCP runtime with fake backend | `mcp_fake` | blocking |
| MCP runtime against real backends | `mcp_real` / `live_external` | live-only |
| Telegram integration | `telegram_live` / `live_external` | live-only |
| Real LLM/provider reachability | `provider_live` / `live_external` | live-only |

## Contract Rules

- All integration-family suites must be invocable through `./tests/run.sh`.
- Blocking integration suites must work from a clean checkout without production secrets.
- Blocking integration suites must use hermetic dependencies and may recurse into `compose.test.yml`.
- Live integration suites require explicit `--live` and may consume secrets from GitHub Secrets, `/opt/moltinger/.env`, or `TEST_ENV_FILE`.
- JSON output and exit-code semantics are inherited from `test-lanes.md`.

## Required Assertions By Mode

### `integration_local`

- login contract
- protected API behaviour
- chat API contract
- metrics endpoint shape
- session persistence and logout invalidation
- expected error responses on malformed or unauthorized requests

### `mcp_fake`

- `initialize`
- `tools/list`
- `callTool`
- cold start
- connection reuse
- restart after crash
- teardown

### Live-only integration lanes

- explicit secret discovery
- clear skip/fail distinction
- real backend health surfaced in case-level results
