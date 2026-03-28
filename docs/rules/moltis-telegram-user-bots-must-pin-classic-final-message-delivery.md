# Rule: Moltis user-facing Telegram bots must pin classic final-message delivery

If a Telegram account is allowed to talk to real users, its tracked Moltis config must
explicitly pin:

```toml
[channels.telegram.<account>]
stream_mode = "off"
```

## Why

- Official Moltis Telegram docs and changelog both expose per-account streaming controls,
  including `stream_mode`, and `off` keeps the classic final-message delivery path.
- If the runtime default changes, or if an account inherits a streaming-capable path, a
  user-facing Telegram chat can leak partial replies, internal activity, tool-progress,
  or other non-final transport artifacts.
- User chats must fail closed toward final human-readable replies only.
- Current Moltis runtime schema is account-only. A legacy root `[channels.telegram]`
  table with `enabled = true` can be misread as a fake Telegram account named `enabled`
  and must not remain in tracked config.

## Required invariants

1. Every user-facing Telegram bot account in tracked config explicitly sets
   `stream_mode = "off"`.
2. Tracked config uses only `[channels.telegram.<account>]` tables and does not keep
   a legacy root `[channels.telegram]` boolean table.
3. Static validation and runtime attestation must fail if either invariant disappears from
   the tracked/live config contract.
4. Production troubleshooting must verify both:
   - tracked `config/moltis.toml`
   - live runtime config / channel DB state
5. Streaming experiments belong only in controlled debug lanes, not in the main user bot.

## Not enough on its own

This rule prevents streaming/default drift. It does **not** prove that user-facing
Telegram replies will never contain an `Activity log` suffix, because current upstream
runtime can still append channel status/logbook HTML via `send_text_with_suffix(...)`
when a tool run buffered status entries and `stream_mode = "off"` is already set.

If users still see `Activity log` after these invariants hold:

1. inspect live logs for `telegram outbound text+suffix send`;
2. treat it as a channel-runtime/logbook boundary issue, not as a missing `stream_mode`
   pin;
3. investigate browser/runtime failures separately if the suffix was triggered by a real
   tool error such as browser navigation timeout.
