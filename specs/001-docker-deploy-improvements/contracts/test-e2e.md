# Test Contract: E2E Compatibility

**Feature**: 001-docker-deploy-improvements
**Compatibility scope**: historical `e2e`-family test references

## Purpose

Этот документ заменяет отсутствовавший `test-e2e.md` и описывает, как legacy E2E references отображаются на новую lane-based архитектуру.

## Mapping To Canonical Lanes

| Historical family | Canonical lane | Mode |
| --- | --- | --- |
| User-facing browser flow | `e2e_browser` | blocking on `push main` |
| Destructive recovery/failover | `resilience` | nightly/manual live-only |

## Contract Rules

- Все E2E suites запускаются только через `./tests/run.sh`.
- Browser E2E must validate the real user transport via Playwright and must not degrade into HTTP-only substitutes.
- `e2e_browser` may use the hermetic stack from `compose.test.yml` and must not rely on production secrets.
- The hermetic browser fixture must pre-complete onboarding so browser assertions exercise `/chats/*` rather than stopping at `/onboarding`.
- Hermetic browser E2E is a test fixture for CI/local reproducibility and does not replace the authoritative remote runtime used for live validation.
- `resilience` must run in an isolated compose project and may not mutate shared environments.
- Live-only E2E suites require explicit `--live`.
- JSON and exit-code semantics are inherited from `test-lanes.md`.

## Required Assertions

### `e2e_browser`

- login flow through the real UI
- send message through the real browser transport
- receive user-visible response
- refresh/reconnect behaviour
- session continuity after reload

### `resilience`

- user-visible degradation and recovery
- failover path correctness
- restart/recovery scenarios in isolated runtime
- persistence/recovery expectations surfaced at case level
