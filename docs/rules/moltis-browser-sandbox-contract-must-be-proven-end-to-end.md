# Rule: Moltis Browser Sandbox Contract Must Be Proven End-To-End

For Docker-backed Moltis browser automation, do not treat `browser enabled = true` or restored Docker socket access as proof that browser runtime is healthy.

The browser contract is complete only when all of the following are true:

1. The official Moltis sandbox/browser baseline is satisfied.
   Minimum examples:
   - sandbox mode is enabled for the session/runtime path that needs isolated browser execution
   - host Docker access is available when Moltis itself runs in Docker
   - `container_host` is configured when sibling browser containers must be reached from inside the Moltis container
2. The tracked repo-specific browser contract is satisfied.
   Minimum examples:
   - tracked `sandbox_image` is present and pullable/buildable
   - tracked `profile_dir` matches the intended host-visible path
   - `persist_profile` matches the chosen runtime strategy
   - the shared browser profile mount exists at the same absolute path inside the Moltis container
   - the shared browser profile directory is writable for the effective browser-container user
3. Recovery proof must include at least one exercised browser canary.
   Acceptable examples:
   - a real `browser` navigate/snapshot canary
   - the same Telegram or authoritative user-facing path that previously timed out
4. Transport-green checks are not enough.
   The following alone are insufficient:
   - `/health = 200`
   - successful image pull
   - successful sibling container start
   - restored Docker socket permissions

Interpretation rule:

- If the first fix restores only Docker/socket access but browser launch still fails because the browser profile storage is not writable or the canary path was not re-run, treat that as an incomplete contract repair, not as “official docs were ignored”.
- The process failure is stopping after a partial invariant, not necessarily choosing the wrong baseline.

Required follow-up when browser timeout/activity leakage is observed:

1. Re-check official Moltis browser/sandbox docs first.
2. Re-check repo-specific browser profile and image contract.
3. Inspect sibling browser container logs for lock-file/profile-dir failures.
4. Re-run an exercised browser canary on the same user-facing path.
5. Record the result in RCA/lessons if a new failure mode is found.

Why:

- browser incidents in Moltis are often multi-layered
- Docker/socket recovery can still leave profile-path or websocket-path failures
- only end-to-end browser proof closes the incident for real users
