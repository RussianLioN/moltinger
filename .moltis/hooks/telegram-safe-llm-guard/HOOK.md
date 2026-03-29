+++
name = "telegram-safe-llm-guard"
description = "Blocks Telegram-safe tool fallbacks before they become user-visible activity leakage"
events = ["AfterLLMCall"]
command = "./handler.sh"
timeout = 5

[requires]
os = ["linux", "darwin"]
bins = ["bash", "grep", "sed", "tr"]
+++

# Telegram Safe LLM Guard

Project-local hook for the user-facing Telegram safe lane.

This hook exists in the workspace-local `.moltis/hooks/` path so the runtime
can discover it from `/server` during startup without relying on config-defined
hook registration.
