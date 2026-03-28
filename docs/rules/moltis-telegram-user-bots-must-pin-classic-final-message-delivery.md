# Rule: Moltis user-facing Telegram bots must pin classic final-message delivery

If a Telegram account is allowed to talk to real users, its tracked Moltis config must
explicitly pin:

```toml
[channels.telegram.<account>]
stream_mode = "off"
```

## Why

- Official Moltis sources are currently inconsistent:
  - the public channels docs still describe the classic non-streaming Telegram path;
  - changelog `0.8.38` added Telegram reply streaming with per-account `stream_mode`
    gating and says `off` keeps the classic final-message delivery path.
- If the runtime default changes, or if an account inherits a streaming-capable path, a
  user-facing Telegram chat can leak partial replies, internal activity, tool-progress,
  or other non-final transport artifacts.
- User chats must fail closed toward final human-readable replies only.

## Required invariants

1. Every user-facing Telegram bot account in tracked config explicitly sets
   `stream_mode = "off"`.
2. Static validation must fail if that pin disappears from the tracked config.
3. Production troubleshooting must verify both:
   - tracked `config/moltis.toml`
   - live runtime config / channel DB state
4. Streaming experiments belong only in controlled debug lanes, not in the main user bot.

## Not enough on its own

This rule prevents Telegram delivery drift. It does not prove that browser/runtime issues
are fixed. If users still hit browser timeouts, investigate browser session lifecycle,
pool pressure, and timeout budgets separately.
