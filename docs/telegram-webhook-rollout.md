# Telegram Webhook Controlled Rollout

Date: 2026-03-07
Issue: `moltinger-dmi`

## Goal

Enable/verify/disable Telegram webhook mode in a controlled way after polling stabilization, with explicit rollback path.

## Baseline

- Current stable mode is polling (`deleteWebhook` applied).
- The rollout must detect redirect regressions (`3xx`) on webhook endpoint before traffic cutover.
- Current external probe snapshot (2026-03-07):
  - `POST /telegram/webhook` -> `303` redirect to `/login`
  - `POST /telegram-webhook` -> `303` redirect to `/login`
  - Webhook cutover remains blocked until target endpoint returns non-redirect response for Telegram callbacks.

## Required GitHub Secrets

- `TELEGRAM_BOT_TOKEN` (already required)
- `TELEGRAM_WEBHOOK_URL` (optional for polling mode, required for webhook rollout)
- `TELEGRAM_WEBHOOK_SECRET` (optional but strongly recommended)

## Manual Workflow

Use GitHub Actions workflow: `Telegram Webhook Rollout`

Actions:

1. `status`:
   - Validates bot token and prints current webhook state.
2. `enable`:
   - Calls `setWebhook` with `TELEGRAM_WEBHOOK_URL`.
   - Applies `drop_pending_updates` as configured.
   - Immediately runs verification checks.
3. `verify`:
   - Confirms `getWebhookInfo.url` matches expected URL.
   - Fails if pending updates exceed threshold (`pending_max` input).
   - Fails on non-empty `last_error_message` when strict mode enabled.
   - Probes webhook endpoint and fails on `3xx` redirects.
4. `disable`:
   - Calls `deleteWebhook` and verifies URL is empty (returns to polling baseline).

## Fast Rollback

If verification fails or bot stops answering:

1. Run workflow action `disable`.
2. Confirm `status` shows empty webhook URL.
3. Send `/status` in Telegram to validate live response.

## Local Command Alternative

```bash
TELEGRAM_BOT_TOKEN=... \
TELEGRAM_WEBHOOK_URL=https://moltis.ainetic.tech/telegram/webhook \
TELEGRAM_WEBHOOK_SECRET=... \
./scripts/telegram-webhook-rollout.sh verify
```

## Notes

- Deploy pipeline now propagates optional webhook secrets into server `.env`.
- `config/moltis.toml` keeps webhook fields commented by default to preserve polling baseline until explicit webhook cutover PR.
