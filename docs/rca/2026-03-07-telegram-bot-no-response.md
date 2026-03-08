# RCA: Telegram bot stopped responding to commands

Date: 2026-03-07
Issue: moltinger-2kj

## Error
Telegram bot `@moltinger_bot` stopped replying to `/start`, `/status`, `/help`, and free-form prompts.

## 5 Whys

1. Why did the bot stop replying?
   - Telegram updates were not reliably processed in the expected production inbound path.

2. Why were updates not processed in the expected path?
   - Production checks showed webhook mode was not active (`inbound_mode=polling`, empty `getWebhookInfo.url`).

3. Why was webhook mode not active?
   - Repository configuration did not enforce webhook URL/runtime wiring for Telegram channel deployment.

4. Why was this not detected/prevented earlier?
   - Integration checks treated missing webhook and missing probe user as `skip`, not as explicit failures under strict monitor expectations.

5. Why did monitoring not fully cover the incident path?
   - No dedicated webhook monitor script/workflow was present in the current branch baseline, and `TELEGRAM_TEST_USER` was not consistently provided.

## Root Cause
Deployment/config baseline lacked strict webhook-mode enforcement and strict probe validation for Telegram channel health in production.

## Actions
1. Restored stable polling baseline and removed conflicting webhook sidecar routing.
2. Normalized Telegram allowlist to string IDs with explicit `dm_policy="allowlist"`.
3. Added controlled webhook rollout tooling:
   - `scripts/telegram-webhook-rollout.sh`
   - GitHub Actions workflow `telegram-webhook-rollout.yml`
   - Runbook `docs/telegram-webhook-rollout.md`
4. Added optional deploy secret propagation for webhook URL/secret (`TELEGRAM_WEBHOOK_URL`, `TELEGRAM_WEBHOOK_SECRET`) without forcing cutover.

## Prevention
- Keep polling as default fail-safe until webhook endpoint contract is re-validated.
- Use controlled rollout workflow (`status` -> `enable` -> `verify`) and immediate `disable` on any regression.
- Keep webhook URL and secret managed only via GitHub Secrets + CI/CD generated `.env`.
