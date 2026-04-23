---
title: "Telegram direct fastpath BeforeLLMCall block assumption was superseded by the official shell-hook contract"
date: 2026-04-23
severity: P1
category: product
tags: [telegram, hooks, runtime, skill-detail, codex-update]
root_cause: "This RCA was later superseded. Official Moltis `20260423.01` source showed that shell-hook stdout `{\"action\":\"block\"}` is not a block at all, BeforeLLMCall modify is ignored for typed payloads, and silent user-clean terminalization cannot be achieved by the repo through that path alone."
---

# RCA: Telegram direct fastpath BeforeLLMCall block assumption was superseded by the official shell-hook contract

Date: 2026-04-23
Status: Superseded by `2026-04-23-telegram-shell-hook-block-contract-and-message-sending-assumptions-were-false.md`
Context: follow-up investigation for Telegram `skill_detail` / `codex-update` runtime leakage

## Error

User-facing Telegram turns still leaked fallback text like:

- `Не могу проверить: read_skill в этой сессии сломан.`
- repeated `missing 'command' / 'query' / 'action' parameter`

even though the repo hook already:

- generated the correct deterministic `skill_detail` answer,
- sent it through the direct Bot API fastpath,
- and returned a terminalizing `BeforeLLMCall` modify payload.

The bug therefore survived after classifier and reply-text fixes.

## Проверка прошлых уроков

Checked first:

- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag hooks`
- `./scripts/query-lessons.sh --tag codex-update`
- `docs/rca/2026-04-01-telegram-skill-visibility-and-create-hook-modify-bypass.md`
- `docs/rca/2026-04-14-telegram-codex-update-live-runtime-ignored-inband-modify.md`

Relevant prior lessons already covered two crucial facts:

1. live Telegram routes cannot treat synthetic hook `modify` as production proof by itself;
2. direct Bot API fastpaths remain the reliable repo-owned delivery contract for some Telegram turns.

What was still missing:

- the source contract after a successful direct fastpath still tried to end the turn via `BeforeLLMCall modify`;
- we had not reduced that assumption to the stricter live-supported contract: `direct send -> block -> suppress blocked tail`.

## Evidence

Authoritative evidence gathered during the investigation:

1. production hook capture for the failing `skill_detail` turn showed the correct direct fastpath reply text and `AfterLLMCall` suppression output;
2. production Docker logs still showed the final bad reply delivered to chat;
3. live binary strings from `/usr/local/bin/moltis` explicitly contained:
   - `BeforeLLMCall ModifyPayload ignored (messages are typed)`
   - `LLM call blocked by BeforeLLMCall hook`
   - `hook blocked event`
4. the direct send transport itself was healthy when invoked manually from both host and container.

This ruled out:

- stale deploy drift,
- broken direct-send transport,
- bad `skill_detail` text generation,
- and classifier-only explanations.

## 5 Whys

| Level | Question | Answer | Evidence |
|---|---|---|---|
| 1 | Why did Telegram still show the bad fallback? | Because the runtime still executed the underlying LLM path after the direct fastpath answer. | production Telegram reply + `docker logs` |
| 2 | Why was the underlying LLM path still alive? | Because the hook terminalized the turn with `BeforeLLMCall modify`, not with a hard block. | captured hook output |
| 3 | Why was `modify` insufficient? | Because the live Moltis runtime explicitly ignores `BeforeLLMCall ModifyPayload` for typed messages. | binary string: `BeforeLLMCall ModifyPayload ignored (messages are typed)` |
| 4 | Why did earlier tests not catch this root cause? | Because component tests only validated hook JSON shape, not the live runtime contract that consumes it. | green synthetic tests + red authoritative Telegram run |
| 5 | Why did this become systemic? | Because the repo contract still encoded an outdated assumption: after direct send, `modify ""` was treated as terminal, even though the live runtime only guaranteed `block` for that boundary. | source design before fix + runtime evidence |

## Root Cause

The root cause was a delivery-contract mismatch in the repo-owned Telegram hook:

- after a successful direct Bot API fastpath send, the hook still relied on `BeforeLLMCall modify` to silence the rest of the turn;
- the live Moltis runtime did not honor that `modify` path for typed `BeforeLLMCall` payloads;
- therefore the only reliable terminalization contract was to hard-block the LLM pass and let the existing `MessageSending` suppression hide the synthetic blocked tail.

## Fixes Applied

1. `scripts/telegram-safe-llm-guard.sh`
   - added explicit `emit_blocked_payload`;
   - changed same-turn fastpath terminalization from `modify` to `block`;
   - changed repeat direct-fastpath guard and codex terminal repeat guard from `modify` to `block`;
   - changed direct `codex-update` fastpath terminalization from `modify` to `block`.
2. `tests/component/test_telegram_safe_llm_guard.sh`
   - updated direct-fastpath component expectations from `modify` payloads to `block`;
   - kept suppression / late-tail rewrite assertions intact so the runtime tail contract stays covered end-to-end.
3. `.moltis/hooks/telegram-safe-llm-guard/HOOK.md`
   - documented the owning delivery contract as:
     `direct send -> block BeforeLLMCall -> suppress blocked tail`.

## Prevention

1. For Telegram direct fastpaths, do not treat `modify` as terminal proof unless live runtime evidence shows it is applied.
2. When the production binary exposes a stronger contract than synthetic tests, encode the stronger contract in source.
3. Keep component tests focused on the real invariant:
   the user-visible direct reply is sent once, the LLM pass is blocked, and all trailing blocked/runtime tails are suppressed.

## Уроки

1. In Moltis Telegram runtime, `hook generated the right JSON` is not the same thing as `runtime applied it`.
2. For direct fastpaths, `block` is a delivery primitive, not just an error path.
3. The reliable fix for Telegram leakage was architectural, not another layer of response filtering.
