title: Telegram OTP bootstrap loop produced stale/invalid codes
date: 2026-03-07
severity: P2
category: telegram
tags: [telegram, otp, telethon, e2e, auth]

# RCA: Telegram OTP bootstrap loop produced stale/invalid codes

Date: 2026-03-07
Context: On-demand `real_user` e2e bootstrap via MTProto/Telethon.

## Error
During bootstrap, OTP requests were repeatedly restarted. User observed no clearly matching new OTP event and entered a code that failed with `PhoneCodeInvalidError`.

## 5 Whys

1. Why did sign-in fail with `PhoneCodeInvalidError`?
   - The entered OTP did not match the active `phone_code_hash` for that specific request cycle.

2. Why was OTP/hash pairing mismatched?
   - The flow was restarted multiple times, creating uncertainty about which OTP belonged to which request.

3. Why did operators restart flow repeatedly?
   - The bootstrap script lacked an in-session resend/retry path and did not expose delivery details (`sent.type`, `next_type`, `timeout`).

4. Why were delivery details missing?
   - Initial implementation optimized for minimal happy-path bootstrap and omitted operational diagnostics.

5. Why did this become user-visible friction?
   - Operational playbook did not explicitly instruct to avoid restarting and to resend within a single authorization session.

## Root Cause
Bootstrap process design relied on repeated restarts instead of single-session retry/resend, causing OTP/hash desynchronization risk and poor observability.

## Actions
1. Updated bootstrap helper `scripts/telegram-real-user-bootstrap.py`:
   - Added delivery diagnostics (`sent_type`, `next_type`, `timeout`).
   - Added interactive `/resend` command in the same session.
   - Added explicit handling for `PhoneCodeInvalidError` and `PhoneCodeExpiredError` without forced process restart.
2. Updated runbook and quickstart to require in-session `/resend` instead of restarting.

## Prevention
- Use one bootstrap session per login attempt.
- If OTP is invalid/expired, call `/resend` inside the same process.
- Capture and review delivery metadata before retrying.

## Уроки

1. **Не перезапускать OTP bootstrap без необходимости** — перезапуски повышают риск рассинхронизации OTP и `phone_code_hash`.
2. **Resend должен быть in-session** — новый код нужно запрашивать через `/resend` внутри того же процесса, а не новым запуском.
3. **Диагностика доставки обязательна** — `SentCodeTypeApp/next_type/timeout` должны быть видны оператору перед повторной попыткой.
