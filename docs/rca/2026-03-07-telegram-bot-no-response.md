title: Telegram bot stopped responding to commands
date: 2026-03-07
severity: P1
category: telegram
tags: [telegram, webhook, e2e, process, rca-protocol]

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

## Уроки

1. **RCA считается незавершенным без индексации уроков** — после любого RCA обязательно выполнить `./scripts/build-lessons-index.sh` и проверку через `./scripts/query-lessons.sh`.
2. **Операционные команды должны идти с явным `cwd`** — в runbook всегда указывать точную директорию запуска, чтобы исключить ошибки исполнения в другой папке.
3. **Real-user E2E требует отдельного one-time bootstrap шага** — `TELEGRAM_TEST_SESSION` генерируется через OTP и хранится в GitHub Secret, а не в постоянных локальных файлах.
4. **Штатный режим бота и тестовый контур должны быть разделены** — on-demand `real_user/synthetic` проверки не должны менять постоянный прод-режим Telegram-канала.
