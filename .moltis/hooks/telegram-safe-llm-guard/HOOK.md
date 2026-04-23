+++
name = "telegram-safe-llm-guard"
description = "Guarded Telegram lane hook that blocks internal activity leakage, rewrites risky skill-path probes, and preserves dedicated skill-tool flows."
events = ["MessageReceived", "BeforeLLMCall", "AfterLLMCall", "BeforeToolCall", "MessageSending"]
command = "./handler.sh"
timeout = 5

[requires]
os = ["linux", "darwin"]
bins = ["awk", "cut", "grep", "sed", "tr"]
+++

# Telegram Safe LLM Guard

This repo-managed hook bundle is synced into the runtime-discovered project hook
path for the Telegram safe lane. It now intercepts deterministic one-shot
Telegram turns as early as `MessageReceived`, and it still rewrites
`BeforeLLMCall`, `AfterLLMCall`, `BeforeToolCall`, and `MessageSending`
payloads when the guarded Telegram-safe lane tries to drift into tool-backed
or telemetry-leaking behavior or filesystem-based skill false negatives.
It also fail-closes skill/codex-update maintenance-debug turns (`почини`,
`исправь`, `отладь`, logs/root-cause requests) into a deterministic text-only
boundary instead of letting runtime tool chatter leak back into Telegram.
For deterministic Telegram-safe replies, the owning delivery contract is:

- send the user-visible reply directly through Bot API
- rewrite the same-turn inbound `MessageReceived` content into a no-op text-only
  payload before generic chat sees the original request
- keep `BeforeToolCall` fail-closed for any residual same-turn tool attempt

Repository note:

- keep this hook tracked in the repo at `/server/.moltis/hooks/...`
- deploy sync copies it into `<data_dir>/.moltis/hooks/...` for live discovery
- keep `handler.sh` as the bundle-local entrypoint that the runtime executes
- do not add `jq` to `requires.bins`; the production Moltis container does not ship it
- the tracked `config/moltis.toml` hook stanza remains as forward-compatible
  documentation, but production `0.10.18` must not rely on config-defined hook
  registration alone
