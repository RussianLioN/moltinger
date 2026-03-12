# Clawdiy Browser Bootstrap Runbook

**Status**: Active operator runbook  
**Scope**: First browser access to hosted Clawdiy on `https://clawdiy.ainetic.tech`

**Related research**:
- [Clawdiy / OpenClaw Browser Bootstrap Research](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/clawdiy-openclaw-browser-bootstrap-2026-03-12.md)
- [Clawdiy / OpenClaw Remote Runtime OAuth Research](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/clawdiy-openclaw-remote-oauth-runtime-2026-03-12.md)

## Purpose

Bring a fresh browser profile from zero to a usable hosted Clawdiy dashboard.

This runbook is intentionally narrower than provider OAuth:

- it gets the browser connected to the live gateway
- it proves device pairing and dashboard usability
- it does not by itself create `codex-oauth` runtime auth for `gpt-5.4`

## What A New User Should Expect

On the first visit, a new browser profile should expect:

- no dedicated welcome wizard
- `Version n/a`
- `Health Offline`
- disabled chat controls until connection succeeds
- the real first operator screen in `Overview -> Gateway Access`

This is normal for hosted Clawdiy.

## Prerequisites

- `CLAWDIY_GATEWAY_TOKEN`
- a platform operator who can approve a pending browser device
- live Clawdiy health already green on the server side

## Browser Path From Zero

1. Open `https://clawdiy.ainetic.tech`.
2. If the browser lands on `Chat`, open `Overview`.
3. In `Gateway Access`, confirm:
   - `WebSocket URL` is `wss://clawdiy.ainetic.tech`
   - `Gateway Token` is empty and ready for input
   - `Password (not stored)` may be visible, but token mode is canonical for hosted Clawdiy
4. Paste `CLAWDIY_GATEWAY_TOKEN` into `Gateway Token`.
5. Leave `Password` empty unless you are explicitly using a temporary compatibility fallback.
6. Click `Connect`.
7. Wait for the new browser/device to appear as a pending device on the gateway.
8. Approve the pending device.
9. Click `Refresh` or reload the page.
10. Confirm the dashboard becomes usable.

Example pairing commands for the platform operator:

```bash
ssh root@ainetic.tech "docker exec clawdiy openclaw devices list --json"
ssh root@ainetic.tech "docker exec clawdiy openclaw devices approve <request-id> --token '\$CLAWDIY_GATEWAY_TOKEN' --url 'wss://clawdiy.ainetic.tech' --json"
```

## Expected Success State

- `Version` shows a real build value such as `2026.3.11`
- `Health` changes from `Offline` to `OK`
- `Config` opens without the old gateway-auth error
- `Chat` input is enabled
- `Agents` page becomes usable for model/provider inspection

## Evidence To Capture

- screenshot or note of the initial disconnected state
- screenshot or note of the `Gateway Access` card
- device approval evidence from the gateway
- screenshot or note of the final `Version` / `Health` state

## Important Boundaries

- Browser bootstrap is not provider OAuth.
- Browser bootstrap is not proof that `gpt-5.4` is ready.
- If `Agents` shows `No configured models` or chat fails on missing provider auth, browser bootstrap still counts as successful and the operator should move to the provider-auth lifecycle next.

## Next Step After Browser Bootstrap

For provider/runtime auth:
- use [Clawdiy Repeat-Auth Runbook](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-repeat-auth.md)
- use [specs/017-clawdiy-remote-oauth-lifecycle/quickstart.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/quickstart.md)
