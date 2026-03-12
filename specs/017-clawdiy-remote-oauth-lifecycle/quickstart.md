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

1. Use the approved operator bootstrap method against the actual target runtime auth store.
2. Confirm the runtime auth artifact lands in the intended persistent location.
3. Preserve repeat-auth evidence.

Expected result:
- Runtime auth store exists in the authoritative Clawdiy path.

## Stage 3: Activate provider explicitly

1. Render/update runtime config so `openai-codex` is explicitly active.
2. Redeploy or restart Clawdiy as required.
3. Verify provider status reflects the intended activation.

Expected result:
- `openai-codex` is visible as an activated provider, not just an auth profile on disk.

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
