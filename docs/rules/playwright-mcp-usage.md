# Playwright MCP Usage Rule

Date: 2026-03-15

This rule exists because browser automation in Codex can fail in repetitive and wasteful ways when the MCP Playwright browser session is stale or when the task does not actually require MCP at all.

## Scope

Use this rule whenever:

- the user explicitly mentions `Playwright`
- the task requires `mcp__playwright__browser_*` tools
- the task requires browser automation, UI inspection, screenshots, or page interaction

## Source Of Truth

Before using MCP Playwright browser tools, read:

1. the local Codex skill: `~/.codex/skills/playwright/SKILL.md`
2. its concise workflow references:
   - `~/.codex/skills/playwright/references/workflows.md`
   - `~/.codex/skills/playwright/references/cli.md`

Repo-level behavior in this document takes precedence over ad hoc retries.

## Decision Rule

1. First decide whether the task actually needs a live browser.
2. If a live browser is not required, do not invoke MCP Playwright.
3. If browser automation is required, prefer a deterministic workflow:
   - use the `playwright` skill as the workflow reference
   - prefer one clear browser path instead of mixing MCP retries, local server retries, and unrelated fallbacks

## MCP Browser Workflow

When using `mcp__playwright__browser_*` tools:

1. Start with a clean browser state when possible:
   - call `mcp__playwright__browser_close` if a previous run likely left a stale session
2. If the tool reports that the browser is not installed:
   - call `mcp__playwright__browser_install`
3. Only then begin the normal loop:
   - `browser_navigate`
   - `browser_snapshot`
   - interact using refs from the latest snapshot
   - snapshot again after substantial UI changes

## Stop Conditions

Do not blindly retry the same MCP Playwright action.

If you hit one of these cases:

- `browserType.launchPersistentContext` failure
- `Opening in existing browser session`
- repeated launch failure after one cleanup attempt

then:

1. stop the retry loop
2. state clearly that MCP Playwright is blocked by browser-session state
3. either switch to the Playwright CLI skill workflow or ask the user whether to continue with explicit browser repair

## Mandatory Incident Response

If MCP Playwright fails (including `Transport closed`, launch failure, or stale session symptoms), it must be treated as an incident, not ignored.

Required actions:

1. perform a short RCA in the same session:
   - collect local evidence (active processes, Codex logs, MCP config)
   - collect at least one official/public source (Playwright MCP/Codex docs or issue tracker)
2. propose a concrete remediation plan (what will be changed, how success will be verified)
3. execute the remediation (or explicitly state why execution is blocked)
4. report outcome with pass/fail and next step

Never silently bypass MCP failures without diagnosis and an explicit mitigation path.

## CLI Fallback Protocol (RCA-2026-03-18)

When switching from MCP to Playwright CLI:

1. Use a short session id (recommended: up to 12 characters).
2. Always run `open` first for a new session before `run-code`.
3. Keep one session per regression scenario to avoid cross-test contamination.
4. Store artifacts under `output/playwright/<label>/` and reference exact log files in backlog notes.

If CLI returns `listen EINVAL ... .sock`, treat it as a session/path bootstrap issue:
- shorten session id,
- reopen session,
- rerun.

## Transport Closed Recovery Checklist

When `playwright/*` MCP tools fail with `Transport closed`, run this exact recovery sequence:

1. Validate MCP config:

```bash
codex mcp get playwright
```

2. Prefer direct binary instead of `npx` wrapper:

```bash
npm install -g @playwright/mcp@0.0.68
codex mcp remove playwright
codex mcp add playwright -- playwright-mcp --isolated --headless
```

3. Verify configuration changed:

```bash
codex mcp get playwright
```

4. If transport is still closed in the same Codex session, restart Codex session once.
   Reason: connection manager can keep a broken MCP transport handle and does not always hot-reload stdio server process changes.

## Sandbox Rule

If the task also requires a local server, local port bind, or a GUI/browser process outside the sandbox:

1. do not keep retrying the same blocked local launch
2. note the sandbox limitation once
3. either use the documented remote target or request the required escalation

## Repo-Specific Expectation

For this repository:

- use MCP Playwright for real browser inspection only
- do not treat repeated MCP launch failures as a product bug by default
- when the user asks to “look with your eyes”, first follow this rule instead of repeatedly calling `browser_navigate`
