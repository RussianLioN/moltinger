---
title: "Telegram shell-hook block contract and MessageSending assumptions were false"
date: 2026-04-23
severity: P1
category: product
tags: [telegram, hooks, runtime, upstream-contract, shell-hooks]
root_cause: "The repo treated shell-hook stdout `{\"action\":\"block\"}` as a real block and treated MessageSending cleanup as a reliable tail-suppression layer. Official Moltis `20260423.01` source disproved both assumptions: shell hooks only block on exit code 1 with stderr reason; `BeforeLLMCall` and `AfterLLMCall` modify are ignored for typed payloads; and MessageSending is not part of the observed official dispatch path. As a result, previous repo fixes could look correct in local script tests while live Telegram runs still continued into provider/tool execution."
---

# RCA: Telegram shell-hook block contract and MessageSending assumptions were false

Date: 2026-04-23
Status: Resolved in repo-owned contract/tests; live user-facing silent terminalization still depends on upstream/runtime architecture
Context: follow-up investigation after PR #208 and PR #209 still left authoritative Telegram `/status` failing with `semantic_activity_leak`

## Error

After merging the Telegram direct-fastpath fixes and upgrading tracked Moltis to `20260423.01`, authoritative Telegram Web UAT still failed:

- run `24854162952`
- failure code `semantic_activity_leak`
- observed reply leaked internal/tool/runtime wording instead of a clean user-facing answer

Live audit proved the repo hook believed it had already terminalized the turn, but the runtime still executed the provider loop.

## Official Evidence

Checked against official Moltis `20260423.01` source:

- `crates/plugins/src/shell_hook.rs`
  - exit `0` + stdout JSON only supports `{"action":"modify","data":...}`
  - real shell-hook block happens only via exit `1` with `stderr = reason`
- `crates/agents/src/runner/non_streaming.rs` and `streaming.rs`
  - `BeforeLLMCall ModifyPayload ignored (messages are typed)`
- `crates/agents/src/runner/helpers.rs`
  - `AfterLLMCall ModifyPayload ignored (response is typed)`
- `crates/chat/src/channels.rs`
  - `MessageReceived Block(reason)` is surfaced through channel error formatting (`Message rejected: ...`)
- repo-wide grep over official `20260423.01` sources did not show a live dispatch path for `MessageSending`

## Root Cause

The incident had three stacked causes:

1. The repo relied on a non-existent shell-hook contract.
   - `scripts/telegram-safe-llm-guard.sh` emitted stdout `{"action":"block"}`.
   - Official Moltis shell hooks ignore that as a block and continue normally.

2. The repo assumed in-band modify could still rescue typed LLM payloads.
   - Official runtime ignores `BeforeLLMCall` and `AfterLLMCall` modify for typed payloads.
   - Local script-level tests therefore overstated what live runtime would actually honor.

3. The repo over-trusted `MessageSending` as a cleanup layer.
   - Official runtime/docs/code path did not support the repo assumption that a final user-visible tail could always be sanitized there.

## Fix

Repo-owned fixes in this lane:

1. Register `MessageReceived` in the tracked Telegram-safe hook config and bundle.
2. Move deterministic one-shot Telegram-safe ingress handling to `MessageReceived`.
   - direct-send the user-visible reply through Bot API at ingress time
   - rewrite the inbound content into a no-tool terminalized turn before generic chat sees the original risky prompt
3. Keep `BeforeToolCall` fail-closed for residual same-turn tool attempts armed by the ingress marker.
4. Update config/docs/watcher wording so the repo no longer repeats the false `MessageReceived read-only` claim.
5. Add/adjust tests to encode the real official shell-hook contract instead of the repo-invented one.

## What This Changes

- The repo no longer treats stdout `{"action":"block"}` as a valid terminalization primitive.
- The repo no longer claims one-way Telegram watcher UX is caused by a read-only `MessageReceived`.
- Telegram-safe deterministic answers now start at ingress instead of waiting for `BeforeLLMCall`.

## Residual Risk

Official Moltis still does not expose a repo-owned, silent, user-clean terminalization primitive for Telegram turns:

- `MessageReceived Block(reason)` is user-visible as a formatted rejection, not a clean assistant reply
- `BeforeLLMCall`/`AfterLLMCall` modify do not terminalize typed payloads

So this repo can reduce live drift earlier and suppress residual tool paths, but a perfect silent-stop contract still depends on upstream runtime capability or a separate repo-owned ingress architecture.
