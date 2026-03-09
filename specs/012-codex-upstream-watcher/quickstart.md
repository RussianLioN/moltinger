# Quickstart: Codex Upstream Watcher

## Goal

Validate that Moltinger can watch official Codex upstream sources on a schedule, produce a deterministic upstream report, and send one Telegram alert per fresh upstream fingerprint without depending on a locally installed Codex CLI.

## Manual Watch Run

Expected user flow:
- operator runs the watcher manually
- watcher reads the official Codex changelog and optional advisory issue signals
- watcher prints a short upstream summary and writes a machine-readable report

Validation target:
- no local `codex` binary is required
- repeated identical runs are recognized as already known

## Scheduled Telegram Alert

Expected user flow:
- scheduler runs the watcher on the Moltinger host
- watcher sees a fresh upstream fingerprint
- one Telegram alert is sent through the existing Moltinger bot sender

Validation target:
- repeated identical runs do not resend the same Telegram alert
- cron-safe execution remains fail-open for the rest of the host

## Failure And Recovery

Expected user flow:
- one or more official sources fail or return malformed data
- watcher records investigate or failed state without sending a misleading success alert
- later source recovery either suppresses an already-known fingerprint or sends a new alert for a new fingerprint

Validation target:
- failure state is explicit in the JSON report
- recovery does not create duplicate alerts for the same fingerprint

## Verification Checklist

1. Confirm the manual watcher run returns a plain-language upstream answer.
2. Confirm the watcher report remains deterministic and machine-readable.
3. Confirm scheduled Telegram delivery is opt-in and duplicate-safe.
4. Confirm source failure and recovery keep watcher state coherent and retry-safe.
