# Clawdiy / OpenClaw Browser Bootstrap Research

**Date**: 2026-03-12  
**Status**: Research complete, operator handoff ready  
**Scope**: What a first-time browser user actually sees on `https://clawdiy.ainetic.tech` and how hosted Control UI bootstrap works before any provider OAuth is attempted

**Breadcrumbs**: [Docs](/Users/rl/coding/moltinger-openclaw-control-plane/docs) / [Research](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/README.md) / `clawdiy-openclaw-browser-bootstrap-2026-03-12`

**Related artifacts**:
- [docs/runbooks/clawdiy-browser-bootstrap.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-browser-bootstrap.md)
- [docs/runbooks/clawdiy-repeat-auth.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-repeat-auth.md)
- [docs/research/clawdiy-openclaw-remote-oauth-runtime-2026-03-12.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/clawdiy-openclaw-remote-oauth-runtime-2026-03-12.md)
- [specs/017-clawdiy-remote-oauth-lifecycle/spec.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/spec.md)

## Executive Summary

Current OpenClaw docs and live Clawdiy behavior agree on one important point: hosted browser access bootstrap is not the same thing as provider OAuth bootstrap.

For a fresh browser profile on `https://clawdiy.ainetic.tech`, the operator should expect:

- a disconnected dashboard shell, not a dedicated welcome wizard
- `Version n/a` and `Health Offline` before connection
- an `Overview` page with a `Gateway Access` card
- browser-side entry of `Gateway Token`
- a new device identity that requires pairing approval

Only after that browser bootstrap succeeds does it make sense to inspect whether the current build exposes any provider-auth UI. As of the current live Clawdiy build, browser bootstrap works, but there is no validated evidence that a first-run UI wizard performs `codex-oauth` runtime login by itself.

## Official Evidence

| Source | Checked | Official evidence | Impact |
|---|---|---|---|
| https://docs.openclaw.ai/web/dashboard | 2026-03-12 | Dashboard docs describe the hosted control surface where connection parameters are entered and reused client-side. | First-run browser access should be documented around the dashboard access card, not a server-driven wizard. |
| https://docs.openclaw.ai/web/control-ui | 2026-03-12 | Control UI docs explain that browser/device state is local and new browser profiles behave like new devices. | A fresh browser session must be expected to need new pairing. |
| https://docs.openclaw.ai/cli/devices | 2026-03-12 | Device docs describe listing and approving pending browser devices. | Hosted browser bootstrap requires a pairing approval step outside the page itself. |
| https://docs.openclaw.ai/gateway/troubleshooting | 2026-03-12 | Troubleshooting docs describe device/token drift and re-pair flows. | `Version n/a` / `Health Offline` on a fresh browser is consistent with missing browser-side bootstrap, not necessarily a dead gateway. |
| https://docs.openclaw.ai/start/auth/codex-oauth | 2026-03-12 | Provider auth is documented as a separate auth flow. | Browser bootstrap must be documented separately from provider OAuth lifecycle. |

## Repo-Local Live Evidence

These observations are live Clawdiy evidence, not official docs:

| Observation | Evidence | Impact |
|---|---|---|
| Fresh browser opens a disconnected shell | Live Playwright snapshot on `2026-03-12` showed `Version n/a`, `Health Offline`, and disabled chat controls. | Operators must not be told to expect a finished setup screen on first load. |
| First actionable screen is `Overview -> Gateway Access` | Live snapshot showed fields `WebSocket URL`, `Gateway Token`, `Password (not stored)`, and `Connect`. | The runbook must start from `Overview`, not from `Settings`. |
| Fresh browser creates a new device identity | Clean browser replay generated a pending device request that had to be approved server-side. | Pairing approval is part of the real browser bootstrap contract. |
| Browser bootstrap success normalizes the dashboard | After token injection and pairing approval, live Clawdiy showed `Version 2026.3.11` and `Health OK`. | Success criteria are dashboard health/version, not just “page opened.” |
| Provider auth remains separate | Live `main` agent still lacked provider auth after browser bootstrap. | Browser bootstrap alone must not be marketed as `gpt-5.4` readiness. |

## Explicit Inference

The following points are inference, not direct quotes:

- A “new user setup” document for Clawdiy must describe browser access bootstrap first and provider OAuth second.
- `Gateway Token` entry and device pairing are required operator steps for hosted Clawdiy and should be treated as normal, not as incident symptoms.
- Any local project doc that tells the user to start in `Settings` for OAuth before dashboard bootstrap is misleading for the current live build.

## Recommended Operator Path

1. Open `https://clawdiy.ainetic.tech`.
2. Go to `Overview` if the browser lands elsewhere.
3. Expect a disconnected shell with `Version n/a` / `Health Offline` before bootstrap.
4. In `Gateway Access`, keep `WebSocket URL=wss://clawdiy.ainetic.tech`.
5. Paste the current `CLAWDIY_GATEWAY_TOKEN`.
6. Leave password empty when using token mode.
7. Click `Connect`.
8. Approve the pending browser device through the OpenClaw device flow.
9. Refresh and confirm `Version` and `Health` normalize.
10. Only then inspect `Agents` / `Config` for provider/model state.

## Non-Goals

This browser bootstrap research does not claim:

- that first-run Clawdiy shows a dedicated onboarding wizard
- that browser bootstrap alone writes `auth-profiles.json`
- that `codex-oauth` login is currently proven to exist as a UI-native first-run step in the live build

## See Also

- [docs/runbooks/clawdiy-browser-bootstrap.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-browser-bootstrap.md)
- [docs/runbooks/clawdiy-repeat-auth.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-repeat-auth.md)
- [specs/017-clawdiy-remote-oauth-lifecycle/quickstart.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/quickstart.md)
