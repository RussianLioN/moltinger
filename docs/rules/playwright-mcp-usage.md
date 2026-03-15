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
