+++
name = "telegram-safe-llm-guard"
description = "Fail-closed Telegram safe-lane guard that strips tool fallback and internal activity leakage after the LLM reply."
events = ["AfterLLMCall"]
command = "/server/scripts/telegram-safe-llm-guard.sh"
timeout = 5

[requires]
os = ["linux", "darwin"]
+++

# Telegram Safe LLM Guard

This repo-managed hook bundle is synced into the runtime-discovered project hook
path for the Telegram safe lane. It rewrites `AfterLLMCall` payloads when the
`custom-zai-telegram-safe` provider tries to fall back into tool execution or
emits internal telemetry markers.

Repository note:

- keep this hook tracked in the repo at `/server/.moltis/hooks/...`
- deploy sync copies it into `<data_dir>/.moltis/hooks/...` for live discovery
- do not add `jq` to `requires.bins`; the production Moltis container does not ship it
- the tracked `config/moltis.toml` hook stanza remains as forward-compatible
  documentation, but production `0.10.18` must not rely on config-defined hook
  registration alone
