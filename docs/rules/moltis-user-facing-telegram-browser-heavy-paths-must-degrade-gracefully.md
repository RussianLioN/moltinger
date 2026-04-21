# Rule: Moltis user-facing Telegram browser-heavy paths must degrade gracefully until browser/session closure is proven

## Scope

Applies to user-facing Telegram and other DM/messaging channels in Moltis when browser/search/
memory-heavy workflows are likely to produce multi-step tool activity or long browser/session
lifecycles.

## Rule

Until browser/session closure is proven on the authoritative target:

1. Do not silently trigger browser-heavy workflows in user-facing Telegram/DM chats.
2. Prefer direct human-readable answers, `web_fetch`, or asking the user to continue in the
   web UI/operator lane when the task would require browser automation or long tool chains.
3. Treat `Activity log`, raw tool names, raw shell commands, or progress traces in Telegram as
   failures, not as acceptable degraded UX.
4. Pin real user-facing Telegram accounts to the canonical guarded safe provider identity
   (`model = openai-codex::gpt-5.4`, `model_provider = openai-codex`) and enforce no-tool delivery
   semantics through the repo-owned Telegram-safe hook/guard layer instead of relying on a
   dedicated `tool_mode = "off"` lane.
5. Treat tracked provider identity as necessary but not sufficient. Verify with authoritative
   UAT and session artifacts that the live Telegram turn did not execute tools anyway and that the
   final delivery stayed on the exact safe-text contract.
6. For Telegram `/status`, require a deterministic short text reply with the canonical
   Telegram-safe model contract and no tool calls.
7. Do not recommend `Pair` as the default fix unless the evidence actually shows missing session
   state, QR/login prompt, or other pairing/auth drift.

## Why

- Official Moltis docs say browser sandbox follows the session sandbox mode; they do not say
  that Pair fixes browser/session lifecycle defects.
- Official OpenClaw Pairing docs cover DM/device approval, not browser cache cleanup.
- Current live evidence shows an upstream gap:
  - stale browser session reuse after browser death;
  - Telegram delivery of internal activity logbook.

## Minimum Verification Before Removing The Degraded Mode

1. `t.me/...` browser canary succeeds on the authoritative target.
2. Repeated browser runs do not reuse a stale `browser-*` session after failure.
3. Telegram authoritative UAT shows only final user-facing replies and no `Activity log`.
4. Browser failure recovery no longer collapses into `PoolExhausted`.
