# Quickstart: Codex Upstream Watcher

## Goal

Validate that Moltinger can watch official Codex upstream sources on a schedule, produce a deterministic upstream report with Russian severity/explanations, optionally batch alerts into a digest, and send one Telegram alert per fresh upstream fingerprint without depending on a locally installed Codex CLI. Also validate the opt-in flow that asks the user whether they want practical project recommendations.

## Manual Watch Run

Expected user flow:
- operator runs the watcher manually
- watcher reads the official Codex changelog and optional advisory issue signals
- watcher prints a short upstream summary with severity and plain-Russian explanations and writes a machine-readable report

Validation target:
- no local `codex` binary is required
- repeated identical runs are recognized as already known
- practical project recommendations are prepared through the advisor bridge

## Scheduled Telegram Alert

Expected user flow:
- scheduler runs the watcher on the Moltinger host
- watcher sees a fresh upstream fingerprint
- one Telegram alert is sent through the existing Moltinger bot sender

Validation target:
- repeated identical runs do not resend the same Telegram alert
- cron-safe execution remains fail-open for the rest of the host
- the first alert can also ask whether the user wants practical project recommendations

## Digest And Practical Guidance

Expected user flow:
- scheduler runs the watcher in digest mode
- the first non-critical upstream event is queued
- a later run flushes one combined digest instead of multiple separate alerts
- after an alert, the user can answer `да` in Telegram to receive practical project recommendations

Validation target:
- digest mode reduces alert noise without hiding critical states
- a positive Telegram reply results in a second project-facing recommendation message
- a negative reply closes the follow-up without a second message
- live reply reading remains opt-in so the watcher does not compete with the main Telegram bot consumer by default

## Failure And Recovery

Expected user flow:
- one or more official sources fail or return malformed data
- watcher records investigate or failed state without sending a misleading success alert
- later source recovery either suppresses an already-known fingerprint or sends a new alert for a new fingerprint

Validation target:
- failure state is explicit in the JSON report
- recovery does not create duplicate alerts for the same fingerprint

## Verification Checklist

1. Confirm the manual watcher run returns a Russian plain-language upstream answer with severity.
2. Confirm the watcher report remains deterministic and machine-readable.
3. Confirm scheduled Telegram delivery is duplicate-safe and can ask whether practical recommendations are needed.
4. Confirm digest mode can queue non-critical events and flush one combined alert.
5. Confirm source failure and recovery keep watcher state coherent and retry-safe.
