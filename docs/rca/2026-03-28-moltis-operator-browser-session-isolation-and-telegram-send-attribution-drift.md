---
title: "Moltis operator browser session isolation and Telegram send attribution drift"
date: 2026-03-28
severity: P1
category: process
tags: [moltis, browser, telegram, ws-rpc, session, canary, production]
root_cause: "Operator browser smoke changed sessions in one WS connection and sent chat in another, while Telegram send attribution relied on exact-only outgoing bubble matching."
---

# RCA: Moltis operator browser canaries leaked shared session state and Telegram send attribution drifted on preview-appended bubbles

Date: 2026-03-28
Severity: high
Scope: production Moltis browser canaries, authoritative Telegram Web UAT, shared browser capacity on `ainetic.tech`
Status: fixed in git, pending canonical landing from `main`

## Summary

After the browser sandbox/image/profile fixes were already deployed, Telegram users still
hit a noisy failure mode:

- browser work could still time out with `pool exhausted: no browser instances available`;
- contaminated chats still showed internal `Activity log` messages;
- the authoritative Telegram Web helper sometimes reported `send_failure` even when the
  outgoing probe had actually been sent successfully.

The new investigation showed two different problems:

1. the authoritative Telegram helper still had an observability bug: it required an exact
   outgoing bubble match, but Telegram can append page-preview text to the sent bubble;
2. the operator browser smoke path tried to isolate itself with `sessions.switch`, but that
   switch happened in one WS connection while `chat.send` ran in a different WS connection,
   so the smoke still executed in the default session instead of a dedicated one.

The resulting operator path was not safely isolated on shared production. That did not prove
that all remaining user-facing browser incidents came from the operator canary, but it did
prove that the repo-side verification contract was still incomplete and could interfere with
shared browser capacity.

## Evidence

- Live production browser startup was already healthy:
  - no more `permission denied while trying to connect to the docker API`
  - no more browser image pull failure on the current path
  - `tool execution succeeded tool=browser` appeared in live logs for operator browser runs
- Fresh Telegram incident logs showed a new failure shape:
  - `browser connection dead, closing session and retrying`
  - `tool execution failed ... pool exhausted: no browser instances available`
- The same period also contained stale user-facing `Activity log` contamination in Telegram.
- Fresh authoritative Telegram Web probe evidence showed:
  - wrapper verdict `send_failure`
  - but debug snapshots proved the outgoing probe bubble existed and the bot had already replied
  - the outgoing bubble text included the probe plus appended preview text
- Live RPC proof against production showed the old smoke contract was wrong:
  - first attempt with separate `sessions.switch` and later `chat.send` produced final
    `sessionKey = "main"`
  - after switching the whole chat workflow into one WS RPC sequence, the final event used
    `sessionKey = "operator:browser-canary:..."`
  - the dedicated operator session was then removed successfully and no longer appeared in
    `sessions.list`
- Official Moltis docs support the relevant invariants:
  - browser sessions are tracked/reused within the current chat session
  - browser lifecycle cleanup belongs at the session/browser layer, not via ad-hoc guesswork
  - the public Telegram/channels docs and the newer changelog are currently inconsistent:
    the channels page still describes the classic non-streaming path, while changelog
    `0.8.38` adds per-account reply streaming plus `stream_mode` gating where `off` keeps
    classic final-message delivery
  - Docker/sandbox docs require correct sibling-container routing, but do not say that
    “re-pair” is the default answer to browser/session incidents

## 5 Whys

### 1. Why did the authoritative Telegram helper still say `send_failure` on a successful send?

Because it matched only exact outgoing bubble text and ignored Telegram's preview-appended
variant of the same sent message.

### 2. Why did operator browser canaries still touch shared session state?

Because the smoke path switched sessions and then opened a new WS connection for `chat.send`,
which silently fell back to the default session.

### 3. Why was that dangerous on shared production?

Because browser session reuse/capacity in Moltis is scoped to the current chat session, so a
fake isolation step can still leave operator browser work attached to the shared default lane.

### 4. Why was this not caught before the next production incident?

Because component tests covered the individual RPC calls, but not the connection-level
invariant that session switching must survive into the actual `chat.send`.

### 5. Why did debugging still drift toward “maybe pair again”?

Because Telegram Web state is an obvious operational suspect, but the current evidence showed
valid send behavior and no mandatory re-pair signal. Pairing was a possible operational action,
not the demonstrated root cause of this incident.

## Root Cause

Primary root causes:

- authoritative Telegram send attribution was too strict for the real Telegram Web bubble shape;
- operator browser smoke did not preserve session switching through the actual `chat.send`
  connection, so its isolation contract was logically false.

Contributing factors:

- shared production browser capacity remained tight with `max_instances = 1`;
- prompt-level “do not leak Activity log” guardrails are not a substitute for transport/runtime
  filtering;
- earlier browser repair waves correctly fixed Docker/browser startup layers but had not yet
  proven end-to-end operator session isolation.

## Fix

1. Update `telegram-web-user-probe.mjs` so outgoing probe attribution:
   - prefers exact outgoing bubble matches;
   - falls back to a post-baseline prefix match when Telegram appends preview text.
2. Update the browser smoke path so the operator chat workflow runs in one WS connection:
   - `sessions.switch`
   - `chat.clear`
   - `chat.send`
   - `sessions.delete`
3. Keep dedicated operator browser canary session keys and delete them after the run.
4. Keep browser canary log proof ANSI-safe.

## Verification

- `node --check tests/lib/ws_rpc_cli.mjs`
- `node --check scripts/telegram-web-user-probe.mjs`
- `bash -n scripts/test-moltis-api.sh`
- `bash -n scripts/moltis-browser-canary.sh`
- `bash tests/component/test_moltis_api_smoke.sh`
- `bash tests/component/test_moltis_browser_canary.sh`
- `bash tests/component/test_telegram_web_probe_correlation.sh`
- `bash tests/static/test_config_validation.sh`
- live RPC proof:
  - final `chat` event used the dedicated `operator:browser-canary:...` session key
  - dedicated session disappeared from `sessions.list` after cleanup

## Prevention

- Do not treat session isolation as valid unless the request that matters (`chat.send`) runs in
  the same WS connection as `sessions.switch`.
- Do not use exact-only bubble matching for Telegram Web send attribution.
- Do not assume re-pair is the default answer when Telegram Web state still sends successfully.
- Treat operator browser canaries on shared production as a session-lifecycle problem, not only
  a browser-startup problem.
- Keep the remaining channel/runtime activity-leak investigation as an explicit follow-up; prompt
  guardrails alone are insufficient proof.

## Уроки

1. Session isolation в Moltis нельзя доказывать ответом `sessions.switch`; доказывать нужно final
   `chat` event, который реально пришёл в ожидаемый `sessionKey`.
2. Для Telegram Web authoritative UAT нельзя держать exact-only корреляцию sent bubble, потому что
   Telegram может дописывать preview text и ломать ложным образом `send_failure`.
3. Operator browser canary на shared production должен жить в dedicated session lifecycle и
   завершаться cleanup этой session, иначе он сам становится источником drift.
4. Re-pair Telegram Web — не дефолтный ответ. Если send уже состоялся и reply уже пришёл, pairing
   не является доказанной первопричиной.
