# Clawdiy deploy must attest live runtime contract

**Applies to:** `scripts/deploy.sh`, `.github/workflows/deploy-clawdiy.yml`, operator runbooks, Clawdiy upgrade/canary slices

## Rule

Clawdiy rollout success is not proven by container liveness or `/health` alone.
Every green deploy or upgrade canary must also prove the live runtime contract:

1. the running image matches the tracked pinned baseline;
2. the live OpenClaw version matches the tracked expected version when one is declared;
3. the runtime auth store exists at the expected path;
4. the expected provider is ready (`status=ok`);
5. the resolved default model matches tracked config.

The repo-approved proof path is:

```bash
./scripts/clawdiy-runtime-attestation.sh --json
```

## Why

Clawdiy can be "healthy" while still drifting on image provenance, provider auth
readiness, or default model state. Health-only verification allowed repo-managed
truth to lag behind the already-healed live runtime.

## Required

- `scripts/deploy.sh` must run `clawdiy-runtime-attestation.sh` before declaring the
  Clawdiy target verified.
- `.github/workflows/deploy-clawdiy.yml` must expose the same attestation in the
  remote rollout path.
- Runbooks must document runtime attestation as part of operator evidence.
- New Clawdiy upgrade candidates must be evaluated against runtime attestation, not
  just `/health` and Docker health.

## Forbidden

- declaring Clawdiy rollout green from `/health` alone;
- updating the tracked image pin without also proving the runtime auth/default-model
  contract;
- treating a healthy container as proof that the expected OAuth provider is ready.
