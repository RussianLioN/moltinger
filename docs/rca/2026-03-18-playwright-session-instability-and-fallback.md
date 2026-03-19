# RCA: Playwright Session Instability And Non-Deterministic Fallbacks

Date: 2026-03-18
Feature: `024-web-factory-demo-adapter`
Context: full regression cycle for web-demo + user-reported UI issues

## Error

During end-to-end verification the browser stack behaved non-deterministically:

1. MCP Playwright intermittently failed with `Opening in existing browser session`, then `Transport closed`.
2. Playwright CLI runs were flaky when session bootstrap steps were inconsistent (`run-code` without explicit `open`) or session ids were too long for local socket paths.
3. `e2e_browser` lane in dockerized test-runner hung and direct run showed `Playwright runtime is not available in the test runner image`.

Evidence:
- `output/playwright/ui-regression/arcu1.unsafe.log`
- `output/playwright/ui-regression/arcu2.safe.log`
- `output/playwright/ui-regression/ui_flow_unsafe_sync.clean.open.log`
- command output: `TEST_TIMEOUT=30 node tests/e2e_browser/agent_factory_web_demo.mjs`

## 5 Whys

1. Why did Playwright runs alternate between success and failure?
   - Because different execution paths (MCP, CLI, docker e2e) were used ad hoc without a strict single-path protocol.
2. Why was there no strict protocol?
   - Because preflight/cleanup and fallback boundaries were documented partially, but not enforced as one deterministic runbook.
3. Why did MCP fail specifically with stale session symptoms?
   - Because persistent browser context remained occupied (`mcp-chrome`) and MCP transport restart sequencing was not always clean.
4. Why did CLI flow fail in some attempts?
   - Because `run-code` was called without guaranteed `open` bootstrap for the new session, and overly long session ids hit socket path limitations.
5. Why did automated e2e lane fail to give reliable signal?
   - Because test-runner image/runtime contract for Playwright was broken (runtime missing), but lane execution path did not fail-fast with an explicit infrastructure verdict.

## Root Cause

Root cause is process-level inconsistency in browser test orchestration:
- no single enforced execution protocol across MCP/CLI/e2e lanes;
- missing hard preflight checks for runtime/session readiness;
- missing deterministic fail-fast behavior when browser runtime is unavailable.

## Fixes Applied

1. Captured and attached concrete reproductions in backlog:
   - `molt-j51` (MCP stale session recovery),
   - `molt-x3o` (runtime availability in test runner),
   - plus product-flow bugs `molt-kft`, `molt-ypy`.
2. Added explicit run evidence from clean CLI sessions:
   - unsafe clarification deadlock reproduction,
   - safe-flow confirmation regression reproduction.
3. Updated operational rule with deterministic sequence and session constraints:
   - short session ids,
   - mandatory `open -> run-code`,
   - MCP one-cleanup-only + immediate CLI fallback.

## Prevention

1. For visual regression in this repo use one deterministic order:
   - MCP (single attempt + one cleanup) -> CLI fallback -> record evidence.
2. For CLI always:
   - use short session ids (`<= 12` chars),
   - run `open` before `run-code`.
3. For `e2e_browser` lane:
   - fail-fast on missing Playwright runtime and mark as infra failure, not product pass/fail.
4. Never mix product bug triage and tooling instability into one conclusion; track separately in Beads.

## Уроки

1. **Один прогон — один протокол браузера** — нельзя хаотично переключаться между MCP/CLI/e2e без явного fallback порядка.
2. **Playwright CLI требует явного bootstrap** — для новой сессии сначала `open`, затем `run-code`.
3. **Короткие session id обязательны** — длинные идентификаторы могут ломать unix socket путь (`listen EINVAL`).
4. **Инфраструктурная недоступность runtime должна падать явно** — `e2e_browser` не должен зависать при отсутствии Playwright в runner image.
