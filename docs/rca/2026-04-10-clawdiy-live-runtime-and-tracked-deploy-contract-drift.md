# RCA: Clawdiy Live Runtime and Tracked Deploy Contract Drift

Date: 2026-04-10
Severity: high
Scope: Clawdiy deploy contract, OpenClaw image pinning, runtime auth attestation
Status: fixed

## Summary

The open `molt-zze` and `molt-1mn` backlog still described Clawdiy as if production
was pinned to `2026.3.11` and still blocked on the writable runtime-home fix. Live
evidence on `ainetic.tech` showed a different reality: Clawdiy had already been
running healthy for weeks on `ghcr.io/openclaw/openclaw:latest`, resolving to
version label `2026.3.13-1`, with a working OAuth store and persisted default model
`openai-codex/gpt-5.4`.

Root cause: the repo-managed deploy contract tracked only coarse health plus an old
image baseline, so repo truth drifted away from the live runtime. There was no
shared fail-closed attestation proving image digest, runtime auth-store presence,
provider readiness, and tracked default model together.

## RCA "5 Why"

### 1. Why did the backlog still treat Clawdiy as blocked on `2026.3.11`?

Because the tracked deploy/config/runbook contract still pointed at the old baseline
even though the live runtime had already healed and moved forward.

### 2. Why did tracked repo truth not notice that drift?

Because Clawdiy verification focused on container health and `/health`, not on the
full runtime contract that operators actually cared about.

### 3. Why was health-only verification insufficient?

Because Clawdiy can be "healthy" while still drifting on the exact image provenance,
the persisted default model, or the runtime auth-store state.

### 4. Why did operators and backlog continue reasoning from stale assumptions?

Because there was no repo-approved attestation command that could answer, in one
place, "what image is really running, which default model is resolved, and is the
expected OAuth provider actually ready?"

### 5. Why was that attestation missing?

Because earlier Clawdiy fixes were handled as isolated symptoms (writable home,
warmup tolerance, canary pinning) without elevating the combined runtime contract
into a single deploy-time guard.

## Root Cause

The systemic failure was contract fragmentation: image pinning, default model, and
runtime OAuth readiness were each partially documented, but the deploy pipeline had
no single shared fail-closed attestation tying them together. That allowed the repo
baseline and backlog to stay stale while production had already changed.

## Fix

1. Added `scripts/clawdiy-runtime-attestation.sh` as the shared deploy/runtime proof.
2. Wired attestation into `scripts/deploy.sh` and `.github/workflows/deploy-clawdiy.yml`.
3. Re-pinned the tracked Clawdiy baseline from stale `2026.3.11` to the live-verified
   digest `ghcr.io/openclaw/openclaw@sha256:d7e8c5c206b107c2e65b610f57f97408e8c07fe9d0ee5cc9193939e48ffb3006`
   (OCI version label `2026.3.13-1`).
4. Updated runbooks and rules so Clawdiy success criteria now include runtime
   attestation, not just health.
5. Added regression coverage for the new attestation script and wired it into the
   canonical `component` lane.

## Verification

- `bash -n scripts/clawdiy-runtime-attestation.sh`
- `bash tests/component/test_clawdiy_runtime_attestation.sh`
- `./tests/run.sh --lane component --filter clawdiy_runtime_attestation --json`
- `bash tests/static/test_config_validation.sh`
- `bash tests/security_api/test_clawdiy_auth_boundaries.sh`
- `bash scripts/scripts-verify.sh --refresh-hashes`
- `bash scripts/scripts-verify.sh`
- live evidence collected from `ainetic.tech`:
  - container healthy
  - `/health` returns `200`
  - live image digest matches pinned baseline
  - live version label is `2026.3.13-1`
  - `defaultModel = openai-codex/gpt-5.4`
  - OAuth store exists and provider status is `ok`

## Prevention

- Do not treat Clawdiy `/health` as sufficient rollout proof on its own.
- Keep image pinning, default model, and runtime auth-store readiness under one
  repo-managed attestation command.
- When live Clawdiy state changes, update the tracked baseline and runbooks in the
  same slice instead of leaving backlog/tasks to imply stale production truth.
