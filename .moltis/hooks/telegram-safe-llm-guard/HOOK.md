+++
name = "telegram-safe-llm-guard"
description = "Blocks Telegram-safe LLM/tool leakage and sanitizes internal telemetry before it reaches the chat"
events = ["AfterLLMCall", "BeforeToolCall", "MessageSending"]
command = "./handler.sh"
timeout = 5

[requires]
os = ["linux", "darwin"]
bins = ["awk", "grep", "sed", "tr"]
+++

# Telegram Safe LLM Guard

Project-local guardrail for user-facing Telegram lanes.

- `AfterLLMCall`: replaces contaminated LLM output before textual tool fallback can execute.
- `BeforeToolCall`: fails closed if the Telegram-safe lane still reaches tool execution.
- `MessageSending`: strips internal telemetry if a runtime/tool trace still leaks into the outbound text.

This hook is intentionally shell-only so it stays eligible inside the tracked
Moltis container without `jq` or Python.
