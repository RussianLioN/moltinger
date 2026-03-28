# Upstream Issue Artifact: Telegram codex-update sandbox mismatch and Activity log leakage

## Summary

Live Moltis/OpenClaw Telegram sessions show two coupled but distinct problems:

1. `codex-update` is live-discovered as available, but a Telegram sandboxed session can still
   conclude the skill is missing after probing host-style paths it cannot read.
2. Telegram user-facing delivery can still show `📋 Activity log` even when the final assistant
   turn in `chat.history` is clean and channel config already pins `stream_mode = "off"`.

## Minimal Reproduction Signals

### A. Skill mismatch

- `/api/skills` reports `codex-update` as enabled
- `chat.raw_prompt` advertises skill paths under `/home/moltis/.moltis/skills/...`
- same Telegram session sandbox cannot read `/home/moltis/.moltis/skills` or `/server`
- assistant replies that the skill path does not exist

### B. Activity log leakage

- `channels.list` reports Telegram `stream_mode = "off"`
- `chat.history` final assistant reply is clean
- user-facing Telegram still shows `📋 Activity log`

## Why This Looks Upstream-Owned

- The prompt/runtime contract advertises skill activation paths that the sandboxed `exec` surface
  cannot actually read.
- The delivery leak survives even when the final assistant reply content is not the leaking text.

## Repo-Owned Mitigation Already Applied

- user-facing prompt guardrails now forbid using sandbox file probes as truth for skill existence
- Telegram authoritative UAT now fails on:
  - host path leakage
  - `codex-update` false negatives
  - `Activity log` leakage

## Requested Upstream Clarification / Fix

1. Ensure skill activation instructions do not advertise host paths that the session sandbox
   cannot read.
2. Or expose the required skill/runtime files consistently to sandboxed `exec`.
3. Ensure Telegram delivery does not publish internal `Activity log`/tool-progress to user-facing
   chats when classic final-message delivery is pinned.

## Closure Criteria

- A Telegram sandboxed session no longer turns sandbox-invisible host paths into “skill missing”.
- User-facing Telegram no longer shows `Activity log` for this path when final assistant content is
  already clean.
- Official docs or issue discussion clearly document the expected runtime/sandbox behavior.

