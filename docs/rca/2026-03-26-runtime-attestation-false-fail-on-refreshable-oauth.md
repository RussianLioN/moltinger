# RCA: Runtime Attestation False Failure on Refreshable OAuth

Date: 2026-03-26
Severity: high
Scope: production deploy attestation for Moltis `openai-codex`
Status: fixed

## Summary

Canonical production deploy from `main` reached a healthy live Moltis runtime, but
`scripts/moltis-runtime-attestation.sh` failed with `AUTH_PROVIDER_INVALID`.
The runtime was not actually broken: a real authenticated operator-path canary
prompt succeeded and `docker exec moltis moltis auth status` flipped from
`openai-codex [expired]` to `openai-codex [valid ...]`.

Root cause: attestation treated pre-refresh `auth status` as terminal truth and did
not account for refreshable OAuth tokens that only become valid after the first real
provider use.

## RCA "5 Why"

### 1. Why did deploy fail after the container was already healthy?

Because runtime attestation required `moltis auth status` to contain
`openai-codex [valid ...]` immediately after restart.

### 2. Why was `auth status` not valid immediately after restart?

Because the persisted OAuth state was present but in an `expired` pre-refresh state.

### 3. Why did that not mean the provider was actually broken?

Because a real authenticated `chat.send` request refreshed the provider state and the
same runtime then reported `openai-codex [valid ...]`.

### 4. Why did attestation still fail?

Because it used a single status snapshot and had no repo-approved live canary path
for the refreshable-but-expired case.

### 5. Why was that gap present?

Because the deploy contract assumed `auth status` was authoritative immediately after
restart, instead of modelling lazy OAuth refresh behavior in the live runtime.

## Root Cause

`moltis-runtime-attestation.sh` encoded an overly strict auth invariant:
`expected provider must already be [valid] before any real request is sent`.
That invariant was false for refreshable OAuth state persisted in
`oauth_tokens.json`.

## Fix

1. Keep the strict fast-path for already-valid providers.
2. If the expected provider is `expired` and `oauth_tokens.json` contains a
   refresh token for that provider, run a repo-approved authenticated WS canary
   (`chat.send`) against the live runtime.
3. Re-check `moltis auth status`.
4. Pass only if the provider becomes valid after the canary; otherwise fail with a
   specific auth-canary error code.

## Verification

- `bash -n scripts/moltis-runtime-attestation.sh`
- `bash tests/component/test_moltis_runtime_attestation.sh`
  - direct valid path
  - runtime config drift failure
  - workspace provenance drift failure
  - refreshable expired provider recovers via canary
  - refreshable expired provider fails to recover
  - wrong provider remains invalid

## Prevention

- Treat persisted OAuth plus immediate `expired` as a possible lazy-refresh state, not
  automatic re-auth evidence.
- Keep the operator-path canary in runtime attestation instead of forcing manual
  browser login during deploy recovery.
- Preserve runbook guidance: if `oauth_tokens.json` exists, verify with a real canary
  before attempting interactive re-auth.
