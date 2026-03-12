# Quickstart: Clawdiy Remote OAuth Runtime Lifecycle

## Goal

Move Clawdiy from metadata-only `codex-oauth` readiness to real runtime `gpt-5.4` readiness.

## Stage 1: Confirm current baseline

1. Verify Clawdiy baseline deploy remains healthy.
2. Verify metadata gate state from `/opt/moltinger/clawdiy/.env`.
3. Confirm runtime auth store is either missing or explicitly visible.

Expected result:
- Clawdiy baseline health is green.
- `codex-oauth` is either quarantined or clearly marked metadata-only.

## Stage 2: Bootstrap the real runtime auth store

1. Preferred first step: open `https://clawdiy.ainetic.tech` and complete hosted browser bootstrap through `Overview -> Gateway Access -> Gateway Token -> Connect -> device pairing`.
2. Confirm the dashboard normalizes from `Version n/a` / `Health Offline` to a usable connected state.
3. Inspect the live UI to see whether the current build actually exposes a provider-auth path for `OpenAI Codex` / `codex-oauth`.
4. Only if the live UI truly exposes provider auth and writes into the actual runtime store, continue there.
5. Otherwise use the remote CLI paste-back flow as fallback.
6. Confirm the runtime auth artifact lands in the intended persistent location.
7. Preserve repeat-auth evidence.

Expected result:
- Browser bootstrap is complete and the runtime auth-store result is explicit: either it exists in the authoritative Clawdiy path or the operator has evidence that browser bootstrap alone did not create it.

## Stage 3: Activate provider explicitly

1. Render/update runtime config so `codex-oauth` is explicitly active.
2. Redeploy or restart Clawdiy as required.
3. Verify provider status reflects the intended activation.

Expected result:
- `codex-oauth` is visible as an activated provider, not just an auth profile on disk.

## Stage 4: Verify and quarantine correctly

1. Run `clawdiy-auth-check.sh` against metadata and runtime store.
2. Run `clawdiy-smoke.sh` auth stage.
3. Confirm failures quarantine the provider without taking baseline Clawdiy down.

Expected result:
- Validation distinguishes metadata-only, runtime-ready, and fully promoted states.

## Stage 5: Run post-auth canary

1. Execute a real `gpt-5.4` canary.
2. Record evidence.
3. Promote provider only on success.

Expected result:
- Promotion is backed by upstream execution evidence.

## Stage 6: Rollback and recovery

1. If canary fails, keep `codex-oauth` quarantined.
2. Preserve evidence and repeat-auth notes.
3. Re-run bootstrap or disable the provider while keeping Clawdiy baseline healthy.
