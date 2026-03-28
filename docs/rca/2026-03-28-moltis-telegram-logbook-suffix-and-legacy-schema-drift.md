---
title: "Moltis Telegram logbook suffix remained user-visible after stream_mode off, and tracked config still carried a legacy schema table"
date: 2026-03-28
severity: P1
category: configuration
tags: [moltis, telegram, channels, activity-log, docs, upstream, rca]
root_cause: "The tracked Telegram config mixed a legacy root [channels.telegram] boolean table with the current account-only schema, and the incident analysis initially over-attributed user-visible Activity log leakage to streaming defaults even though current upstream runtime still appends channel status/logbook HTML via send_text_with_suffix(...) when stream_mode is already off."
---

# RCA: Moltis Telegram logbook suffix remained user-visible after `stream_mode = "off"`, and tracked config still carried a legacy schema table

Date: 2026-03-28
Scope: production Moltis Telegram delivery, tracked Telegram config shape, official-docs alignment, post-deploy authoritative repro

## Summary

After `stream_mode = "off"` was merged and deployed, authoritative Telegram repro still
showed user-visible `Activity log` text. Live Moltis logs proved the remaining path was
`telegram outbound text+suffix send`, not edit-in-place streaming. During the same review,
runtime startup also warned:

```text
invalid type: boolean true, expected struct TelegramAccountConfig
account_id="enabled" channel_type="telegram"
```

That warning mapped directly to a tracked legacy config block:

```toml
[channels.telegram]
enabled = true
```

Current official Telegram docs use account-only tables (`[channels.telegram.<account>]`),
so the tracked config still carried schema drift from an older contract.

## What happened

1. The repo correctly pinned `stream_mode = "off"` for the user-facing Telegram bot.
2. Production deploy applied that config and live runtime showed it was present.
3. Authoritative Telegram repro still failed with user-visible `Activity log`.
4. Live Moltis logs showed `telegram outbound text+suffix send start` with non-zero
   `suffix_len`.
5. Upstream Moltis source confirmed `deliver_channel_replies_to_targets(...)` uses
   `send_text_with_suffix(...)` whenever a channel reply has buffered `status_log`
   entries and the reply was not already streamed.
6. Independent of that, startup warnings showed the tracked config still contained a
   legacy root Telegram table that runtime misread as a fake account.

## Evidence

- Live runtime config contained `stream_mode = "off"` under
  `[channels.telegram.moltis-bot]`.
- Live logs after authoritative repro contained:
  - `tool execution failed ... navigation failed: Request timed out.`
  - `telegram outbound text+suffix send start ... suffix_len=148`
- Upstream Moltis Telegram docs expose per-account streaming controls but do not document
  a per-account switch that disables channel status/logbook suffix delivery:
  - `docs/src/telegram.md`
- Upstream Moltis source currently sends suffix HTML when `logbook_html` is non-empty:
  - `crates/chat/src/lib.rs`
  - `crates/telegram/src/outbound.rs`
- Live startup warning matched the tracked legacy block `[channels.telegram] enabled = true`.

## Five Whys

### 1. Why did Telegram still show `Activity log` after `stream_mode = "off"`?

Because the remaining leak was no longer edit-in-place streaming. Runtime appended the
channel status/logbook HTML to the final text reply via `send_text_with_suffix(...)`.

### 2. Why was the incident initially attributed too heavily to streaming?

Because earlier failures really did involve partial/progress delivery, so `stream_mode`
was a necessary containment step. That led to an incomplete mental model after the first
fix landed.

### 3. Why did the repo still hold a legacy Telegram schema table?

Because tracked config preserved an older root `[channels.telegram] enabled = true`
pattern even after official Moltis docs moved to account-only tables.

### 4. Why did that schema drift survive into production?

Because static validation only enforced the positive invariant (`stream_mode = "off"`)
and did not fail on the negative invariant (presence of a legacy root Telegram table).

### 5. Why did this create operational confusion?

Because three different contracts overlapped:

- official Telegram account schema
- streaming-mode containment
- upstream channel status/logbook delivery

The repo guarded the second one, but not the first, and it treated the third one as if it
were also covered by the second.

## Root causes

1. **Schema drift in tracked config**: the repo kept a legacy root Telegram table even
   though current Moltis runtime expects account-only Telegram tables.
2. **Over-narrow mitigation model**: `stream_mode = "off"` was treated as if it disabled
   all user-visible activity leakage, while current upstream runtime still has a separate
   `status_log -> send_text_with_suffix(...)` delivery path.

## Fixes applied

1. Removed the legacy root `[channels.telegram] enabled = true` block from tracked
   `config/moltis.toml`.
2. Added static validation and runtime attestation that fail if tracked/live config keeps
   a root `[channels.telegram]` table.
3. Updated the Telegram delivery rule and remote Docker runbook to document the real
   boundary:
   - `stream_mode = "off"` is necessary
   - it is not sufficient to disable status/logbook suffixes
4. Recorded the remaining `text+suffix` behavior as an upstream/runtime boundary instead
   of misclassifying it as unresolved streaming drift.

## What remains open

1. User-facing Telegram `Activity log` leakage can still happen in current upstream
   runtime when `status_log` is populated.
2. Official Telegram docs do not currently expose a documented per-account switch that
   disables status/logbook suffix delivery for user-facing bots.
3. Browser timeout on `https://t.me/tsingular` remains a separate defect and still needs
   its own root-cause closure.

## Preventive actions

1. Treat negative schema invariants as first-class static checks, not just positive pins.
2. When official docs expose one transport control (`stream_mode`), do not assume it also
   governs adjacent reply-shaping features unless the docs say so explicitly.
3. Use live log signatures (`telegram outbound text+suffix send`) to distinguish
   streaming leaks from logbook-suffix leaks before deciding the next fix.

## Уроки

1. Positive config pins are not enough when old schema keys still parse and create fake
   runtime objects; static checks must also reject legacy table shapes.
2. `stream_mode = "off"` is a delivery-mode control, not a universal Telegram
   no-telemetry switch.
3. When user-visible leakage survives after a transport-level fix, inspect upstream reply
   assembly paths before adding more prompt text or more UAT heuristics.
