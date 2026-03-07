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
1. Added webhook runtime config wiring for Telegram (`TELEGRAM_WEBHOOK_URL`) and deployment env propagation.
2. Added `TELEGRAM_TEST_USER` propagation in deployment and `.env.example` to support active probe checks.
3. Added `scripts/telegram-webhook-monitor.sh`, cron entry, manifest registration, and CI workflow for continuous webhook health checks.
4. Hardened `tests/integration/test_telegram_integration.sh` so webhook/test-user gaps can fail under strict flags instead of always skipping.

## Prevention
- Keep webhook monitor active (`telegram-webhook-monitor.yml` + cron) and treat failures as blocking incidents.
- Keep `TELEGRAM_TEST_USER` and webhook URL configured in production secret/env pipeline.
- Use strict integration flags (`TELEGRAM_REQUIRE_WEBHOOK=true`, `TELEGRAM_REQUIRE_TEST_USER=true`) for release validation.
