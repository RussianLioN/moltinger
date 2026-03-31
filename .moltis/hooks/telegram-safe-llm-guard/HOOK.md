+++
name = "telegram-safe-llm-guard"
description = "Guarded Telegram lane hook that blocks internal activity leakage, rewrites risky skill-path probes, and preserves dedicated skill-tool flows."
events = ["BeforeLLMCall", "AfterLLMCall", "BeforeToolCall", "MessageSending"]
command = "./handler.sh"
timeout = 5

[requires]
os = ["linux", "darwin"]
bins = ["awk", "cut", "grep", "sed", "tr"]
+++

# Telegram Safe LLM Guard

This repo-managed hook bundle is synced into the runtime-discovered project hook
path for the Telegram safe lane. It rewrites `BeforeLLMCall`,
`AfterLLMCall`, `BeforeToolCall`, and `MessageSending` payloads when the
`custom-zai-telegram-safe` provider tries to drift into tool-backed or
telemetry-leaking behavior or filesystem-based skill false negatives.

Repository note:

- keep this hook tracked in the repo at `/server/.moltis/hooks/...`
- deploy sync copies it into `<data_dir>/.moltis/hooks/...` for live discovery
- keep `handler.sh` as the bundle-local entrypoint that the runtime executes
- do not add `jq` to `requires.bins`; the production Moltis container does not ship it
- the tracked `config/moltis.toml` hook stanza remains as forward-compatible
  documentation, but production `0.10.18` must not rely on config-defined hook
  registration alone
