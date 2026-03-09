# Quickstart: Codex Update Delivery UX

## Goal

Validate that users can access Codex update status through plain-language entrypoints, see a launch-time alert when starting Codex through the repo launcher, and optionally receive Telegram delivery through the existing bot path.

## On-Demand Plain-Language Request

Expected user flow:
- user asks to check Codex CLI updates for this repo
- command or skill wrapper runs the delivery script
- user receives a short report with recommendation, freshness, and repo follow-up suggestions

Validation target:
- no raw script flags are required from the user-facing entrypoint
- the response is readable without opening JSON

## Launch-Time Alert

Expected user flow:
- user launches Codex through `scripts/codex-profile-launch.sh`
- launcher performs a fast non-blocking delivery check
- if a fresh actionable update exists, launcher prints a short alert before entering Codex

Validation target:
- launcher still starts Codex even if delivery check fails
- repeated launches do not repeat the same alert for the same fingerprint

## Telegram Delivery

Expected user flow:
- Telegram delivery is enabled with a configured chat target
- delivery flow runs against a fresh actionable advisor result
- one concise Telegram message is sent through the existing bot sender

Validation target:
- repeated identical runs do not resend the same Telegram message
- send failure is visible in the delivery report

## Verification Checklist

1. Confirm the user-facing entrypoint returns a plain-language answer.
2. Confirm launcher alert is short and non-blocking.
3. Confirm Telegram delivery is opt-in and duplicate-safe.
4. Confirm shared delivery state reflects each supported surface separately.
