# Upstream Issue Artifact: Browser stale session cache survives failure and Telegram leaks activity logbook

## Proposed Title

Browser stale session cache survives dead connection and causes `PoolExhausted`; Telegram outbound path leaks internal `Activity log` / channel status logbook to end users

## Summary

After repo-side browser sandbox/profile/connectivity fixes were already in place, the remaining
production issue moved into upstream runtime behavior:

- browser runs can die with `browser connection dead`;
- later work in the same lane reuses a stale `browser-*` session id;
- repeated runs degrade into `pool exhausted: no browser instances available`;
- Telegram user-facing delivery can include `📋 Activity log` with internal tool steps.

## Evidence

### Live browser/session evidence

- first browser tool call raw args started with `session_id: null`
- the same run already reached manager/browser execution with
  `session_id="browser-027f2350dc1ebb16"`
- live logs then showed:
  - `browser connection dead, closing session and retrying`
  - `pool exhausted: no browser instances available`

### Telegram evidence

- end user received:
  - `⚠️ Timed out: Agent run timed out after 30s`
  - `📋 Activity log`
  - tool names / browser navigation traces such as `Navigating to t.me/tsingular`

## Expected Behavior

1. If a browser session dies, runtime should invalidate or quarantine that stale browser session
   before the next tool step or next run can reuse it.
2. Subsequent runs should not hit `PoolExhausted` because of a poisoned stale session.
3. Telegram user-facing delivery should not append internal activity/status logbook by default.
4. User-facing channels should receive only the final assistant reply unless explicit debug mode
   is enabled.

## Official Baseline

- Moltis browser sandbox follows session sandbox mode:
  - https://docs.moltis.org/browser-automation.html
- Moltis Docker/sandbox docs require host-visible paths and sibling-container routing:
  - https://docs.moltis.org/browser-automation.html
  - https://docs.moltis.org/sandbox.html
- OpenClaw Pairing docs describe DM/node approval, not browser cache cleanup:
  - https://docs.openclaw.ai/channels/pairing
- OpenClaw sandbox docs point toward sandbox recreate/reset after runtime/config drift:
  - https://docs.openclaw.ai/gateway/sandboxing

## Acceptance Criteria

1. First browser run on `t.me/...` starts with a fresh healthy session.
2. Repeated browser runs do not reuse a stale `browser-*` session after failure.
3. Browser death does not poison the pool into `PoolExhausted`.
4. Telegram no longer receives `Activity log`, raw tool names, or progress traces in normal
   user chat.
5. If debug/verbose status is needed, it is explicitly gated and not on by default.
