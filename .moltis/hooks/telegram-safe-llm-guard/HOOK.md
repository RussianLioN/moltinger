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

This project-local hook is the active discovery path for the Telegram safe lane.
It rewrites `AfterLLMCall` payloads when the `custom-zai-telegram-safe` provider
tries to fall back into tool execution or emits internal telemetry markers.

Repository note:

- keep this hook discoverable from the workspace mount at `/server`
- do not add `jq` to `requires.bins`; the production Moltis container does not ship it
- the tracked `config/moltis.toml` hook stanza remains as forward-compatible
  documentation, but production `0.10.18` must not rely on config-defined hook
  registration alone
