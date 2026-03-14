# Verify Clawdiy Browser Bootstrap Before Documenting Provider Auth (RCA-012)

**Status:** Active  
**Effective date:** 2026-03-12  
**Scope:** Hosted Clawdiy/OpenClaw operator docs, runbooks, and UI troubleshooting for `https://clawdiy.ainetic.tech`

## Problem This Rule Prevents

Hosted Clawdiy browser access bootstrap and provider OAuth are different operator layers. If docs skip the first layer and send the user straight to a supposed `Settings/OAuth` path, the user is likely to miss the real first screen and treat normal bootstrap behavior as a broken deployment.

## Mandatory Protocol

Before documenting a new Clawdiy UI path:

1. Re-check official OpenClaw docs for dashboard, control-ui, and device pairing behavior.
2. Reproduce the live first-run browser state in a fresh browser profile or equivalent clean context.
3. Document browser bootstrap separately from provider/runtime auth.
4. Treat `Overview -> Gateway Access -> token -> Connect -> pairing` as the default hosted Clawdiy browser bootstrap unless the live build proves otherwise.
5. Mention a provider-auth UI path only after confirming that the current live build actually exposes it.

## Hard Guardrail

For hosted Clawdiy docs, do **not**:

- promise a dedicated welcome wizard unless a fresh browser session actually shows it
- use `Settings/OAuth` as the first operator step by assumption
- equate “UI opened” with “provider auth is ready”

## Expected Behavior

- First-time browser users are guided through the real dashboard bootstrap path.
- Provider auth is documented as a second layer with its own evidence.
- Official docs, live browser behavior, and repo runbooks describe the same first-run experience.
