# Quickstart: Production-Aware Remote UAT Hardening

## Goal

Give operators one authoritative manual flow to answer: does the deployed production service work right now through the real Telegram user path?

## Intended Operator Flow

1. Confirm deploy completed and the production health endpoint is green.
2. Trigger the authoritative remote UAT check using the manual Telegram Web path:

   ```bash
   gh workflow run telegram-e2e-on-demand.yml \
     -f message='/status' \
     -f timeout_sec='45' \
     -f operator_intent='post_deploy_verification' \
     -f run_secondary_mtproto=false \
     -f upload_restricted_debug=false
   ```
3. Review the structured artifact:
   - if `passed`, confirm request/reply attribution for the current run
   - if `failed`, identify the deterministic failure class and stage
4. If a fix is applied or the root cause is narrowed, rerun the same authoritative path and compare evidence.
5. Only after that comparison, decide whether optional MTProto fallback diagnostics are still necessary for production operations.

## MVP Expectations

- Telegram Web is the authoritative path.
- Production remains on polling.
- The check is manual/on-demand.
- PR and main CI remain hermetic-only for blocking gates.
- Periodic Telegram production monitoring remains disabled by default.

## Reproduction Objective

The first implementation milestone must be able to reproduce the current production-aware Telegram Web failure and capture enough diagnostic detail to determine whether the problem is:

- missing login or session state
- Telegram Web UI drift
- chat-open failure
- stale chat noise
- send failure
- bot no-response

## Post-Fix Validation Objective

After the probe is hardened or the root cause is narrowed:

1. Re-run the authoritative remote UAT check.
2. Compare the new artifact with the original failing artifact.
3. Confirm whether the failure classification changed, disappeared, or narrowed.
4. Record whether MTProto fallback remains optional only, becomes unnecessary, or needs a separate follow-up decision.

## Operator Review Checklist

- Was Telegram Web used as the authoritative path?
- Did the artifact identify the run stage and final verdict?
- Did the artifact prove or reject request/reply attribution for the current run?
- Did the run preserve production polling mode?
- Was the check manual/on-demand rather than scheduled or CI-blocking?
- Were before/after artifacts stored under `tests/fixtures/telegram-web/` after the real post-deploy run?
