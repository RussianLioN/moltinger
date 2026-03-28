---
title: "Moltis Telegram user bots needed explicit stream_mode off"
date: 2026-03-28
severity: P1
category: configuration
tags: [moltis, telegram, channels, streaming, activity-log, docs]
root_cause: "Tracked Telegram bot config relied on an implicit delivery default even though official Moltis sources had already introduced per-account streaming with stream_mode gating, so user-facing chats were not explicitly pinned to the classic final-message path"
---

# RCA: Moltis Telegram user bots needed explicit `stream_mode = "off"`

Date: 2026-03-28
Severity: high
Scope: production Moltis Telegram delivery, user-facing activity log leakage, authoritative Telegram UAT
Status: fixed in git, pending canonical landing from `main`

## Summary

After the browser sandbox and operator-session fixes, Telegram users could still see noisy
messages such as:

- `📋 Activity log`
- raw tool names
- partial progress around browser/navigation failures

The user-facing leak was not explained by pairing drift. Fresh evidence showed:

- Telegram send still worked;
- authoritative Telegram Web state was present and active;
- the remaining browser problem was real, but the user-facing `Activity log` leak was a
  separate Telegram delivery problem.

The repo-side root cause was that the tracked Telegram account config did not explicitly pin
the classic final-message path. Official Moltis sources had already introduced per-account
Telegram reply streaming via `stream_mode`, where `off` preserves classic final-message
delivery. Leaving that implicit was too weak for a production user bot.

## Evidence

- Live authoritative Telegram UAT reproduced:
  - `pre_send_invalid_activity`
  - attributable incoming text containing `Activity log ... Navigating to t.me/...`
- Production database inspection showed the Telegram channel config lacked any explicit
  `stream_mode`.
- Tracked `config/moltis.toml` also lacked `stream_mode` under `[channels.telegram.moltis-bot]`.
- Official Moltis sources are currently split:
  - the public channels docs still describe Telegram as the classic polling/final-message path;
  - changelog `0.8.38` added Telegram reply streaming and says per-account
    `stream_mode = "off"` keeps the classic final-message delivery path.

## 5 Whys

### 1. Why did Telegram users still see internal activity-like output?

Because the Telegram delivery path was still able to surface non-final reply material instead
of being pinned to final-message-only behavior.

### 2. Why was the delivery path able to do that?

Because the Telegram bot account config did not explicitly set `stream_mode = "off"`.

### 3. Why was that omission easy to make?

Because the public docs and the newer changelog were inconsistent, so it was possible to think
Telegram still had only the classic non-streaming path.

### 4. Why did that survive into tracked config?

Because the repo had prompt-level guardrails and UAT semantics for activity leakage, but did
not yet enforce the per-account Telegram delivery mode in config.

### 5. Why is that dangerous?

Because user-facing transport behavior must fail closed. Relying on implicit runtime defaults
lets upstream feature changes or account-level drift re-expose internal progress in chat.

## Root Cause

Primary root cause:

- the tracked Telegram bot config relied on an implicit delivery default instead of explicitly
  pinning `stream_mode = "off"` for a real user-facing bot.

Contributing factors:

- official Moltis documentation was split between the older channels page and the newer
  changelog entry;
- browser/runtime incidents produced partial progress and timeout text that became much more
  visible once Telegram delivery was not pinned to the classic final-message path;
- prompt guidance alone cannot override channel delivery semantics.

## Fix

1. Add explicit tracked config:

   ```toml
   [channels.telegram.moltis-bot]
   stream_mode = "off"
   ```

2. Add static validation so the user-facing Telegram bot cannot silently lose that pin.
3. Record the delivery contract in a durable rule and runbook.

## Verification

- `bash tests/static/test_config_validation.sh`
- authoritative Telegram UAT continues to fail on leaked activity until the new config is
  deployed, which is expected and proves the check is meaningful

## Prevention

- Treat Telegram delivery as an explicit runtime contract, not a default.
- For every user-facing Telegram account, pin `stream_mode = "off"` unless the bot is a
  deliberate debug/streaming surface.
- When official docs disagree, prefer the more specific and newer official evidence, then
  document the contradiction in the repo so future sessions do not guess.

## Уроки

1. User-facing channel delivery policy must be pinned in config, not inferred from older docs.
2. Prompt-level “do not leak activity log” guidance is not a substitute for transport-level
   delivery mode control.
3. When official docs and changelog disagree, repo rules should encode the safe default
   explicitly and cite the contradiction.
