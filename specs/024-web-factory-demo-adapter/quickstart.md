# Quickstart: Web Factory Demo Adapter

## Purpose

This quickstart validates the primary web-first demo adapter on top of the factory business-analyst runtime.

It confirms seven things:

1. web-first is the new primary demo path
2. `023` remains preserved as follow-up Telegram transport scope
3. a browser user can start discovery from one HTTPS URL
4. the user can review and confirm the brief in the browser
5. confirmation automatically launches the downstream factory pipeline
6. the 3 concept-pack artifacts are exposed as browser downloads
7. resume/reopen and controlled subdomain demo boundaries remain explicit and traceable

## 1. Verify Package Integrity

Run:

```bash
git status --short specs/024-web-factory-demo-adapter docs/GIT-TOPOLOGY-REGISTRY.md
.specify/scripts/bash/check-prerequisites.sh --json --include-tasks
rg -n "024-web-factory-demo-adapter|Web Factory Demo Adapter|web-first" \
  specs/024-web-factory-demo-adapter/spec.md \
  specs/024-web-factory-demo-adapter/plan.md \
  specs/024-web-factory-demo-adapter/research.md \
  specs/024-web-factory-demo-adapter/data-model.md \
  specs/024-web-factory-demo-adapter/contracts \
  specs/024-web-factory-demo-adapter/quickstart.md \
  specs/024-web-factory-demo-adapter/tasks.md
```

Expected result:

- the Speckit package exists for `024-web-factory-demo-adapter`
- planning artifacts clearly reference `022` as the upstream discovery runtime
- planning artifacts clearly reference `020` as the downstream concept-pack pipeline
- planning artifacts clearly reference `023` as preserved follow-up adapter scope

## 2. Validate Pivot Boundaries

Use:

- [spec.md](./spec.md)
- [research.md](./research.md)
- [../023-telegram-factory-adapter/spec.md](../023-telegram-factory-adapter/spec.md)
- [../022-telegram-ba-intake/spec.md](../022-telegram-ba-intake/spec.md)
- [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md)

Expected boundary:

1. `024` owns the primary browser-accessible demo path.
2. `023` remains a valid follow-up Telegram transport slice.
3. `022` still owns discovery, brief generation, and canonical handoff creation.
4. `020` still owns concept-pack generation and later factory stages.

Validation questions:

- Is the pivot recorded as a priority change rather than a rewrite of the core architecture?
- Does the web adapter stay thin?
- Is the factory agent identity still owned by `Moltis`, not by the browser UI?

## 3. Validate Same-Host Demo Deployment Pattern

Use:

- [../../docker-compose.clawdiy.yml](../../docker-compose.clawdiy.yml)
- [../../docs/runbooks/clawdiy-deploy.md](../../docs/runbooks/clawdiy-deploy.md)
- [spec.md](./spec.md)

Expected design boundary:

- the web demo gets its own same-host subdomain and health surface
- the demo remains operationally separate from `moltis.ainetic.tech`
- the deployment pattern reuses existing Traefik and compose conventions where possible

Validation questions:

- Is the chosen publish path realistic for `asc.ainetic.tech`?
- Does the demo surface avoid cross-contaminating the main Moltis runtime?
- Is there a clear operator health/status story?

## 4. Validate Browser Discovery Turns

Use:

- [contracts/web-session-access-contract.md](./contracts/web-session-access-contract.md)
- [contracts/web-discovery-turn-contract.md](./contracts/web-discovery-turn-contract.md)

Target runtime command after implementation:

```bash
python3 scripts/agent-factory-web-adapter.py handle-turn \
  --source tests/fixtures/agent-factory/web-demo/session-new.json \
  --output /tmp/web-demo-discovery.json
```

Expected result:

- the adapter grants or restores one safe browser session
- the user sees the first useful discovery question
- no raw internal JSON is rendered in the browser

Validation questions:

- Can one raw browser turn start a new project?
- Does the adapter preserve enough context for resume?
- Does the core flow work without websocket-only assumptions?

## 5. Validate Brief Review And Confirmation

Use:

- [contracts/web-brief-confirmation-contract.md](./contracts/web-brief-confirmation-contract.md)

Target runtime command after implementation:

```bash
python3 scripts/agent-factory-web-adapter.py handle-turn \
  --source tests/fixtures/agent-factory/web-demo/session-awaiting-confirmation.json \
  --output /tmp/web-demo-confirmation.json
```

Expected result:

- the brief is rendered into readable sections
- conversational correction requests are accepted
- explicit confirmation or reopen updates the linked brief version correctly

Validation questions:

- Does the user know exactly what is being confirmed?
- Can the user request corrections without leaving the browser?
- Is reopen treated as versioned history rather than in-place mutation?

## 6. Validate Automatic Handoff And Browser Downloads

Use:

- [contracts/web-artifact-delivery-contract.md](./contracts/web-artifact-delivery-contract.md)
- [../020-agent-factory-prototype/quickstart.md](../020-agent-factory-prototype/quickstart.md)

Target runtime chain after implementation:

```bash
python3 scripts/agent-factory-web-adapter.py handle-turn \
  --source tests/fixtures/agent-factory/web-demo/session-download-ready.json \
  --output /tmp/web-demo-downloads.json
```

Expected result:

- the adapter acknowledges downstream launch after confirmation
- the existing handoff/intake/artifact chain runs without manual copy-paste
- the user receives browser downloads for:
  - project doc
  - agent spec
  - presentation

Validation questions:

- Is downstream generation blocked until the brief is confirmed?
- Do all 3 artifacts become browser-downloadable from the same session?
- Can an operator trace the downloads back to the confirmed brief version?

## 7. Validate Browser Resume And Demo Accessibility

Use:

- [data-model.md](./data-model.md)
- [contracts/web-session-access-contract.md](./contracts/web-session-access-contract.md)

Target browser validation after implementation:

```bash
./tests/run.sh --lane e2e_browser --filter agent_factory_web_demo --json
```

Expected result:

- refresh or revisit restores the active project
- the browser UI reconnects to the right pending question, brief state, or download status
- the controlled demo surface remains accessible through a standard browser flow

Validation questions:

- Does refresh preserve the active project pointer?
- Does the browser remain usable in a constrained corporate environment?
- Does resume avoid re-asking already confirmed topics?

## 8. Current Readiness Check

Confirm:

- [x] the feature has a complete spec package
- [x] web-first is explicitly recorded as the primary near-term demo path
- [x] `023` is explicitly preserved as follow-up transport scope
- [x] the browser adapter remains separated from `022` and `020`
- [x] automatic downstream launch and browser downloads are part of the contract

## 9. Handoff Rule

This feature is ready for implementation only when:

1. `tasks.md` exists and preserves the thin-adapter boundary
2. runtime work updates this package and any shared upstream/downstream artifacts when shared contracts change
3. topology documentation is refreshed after branch or worktree mutations
4. the implementation adds matching component, integration, browser, and targeted remote smoke coverage

## 10. Clarification Guard

For this package, interpret `024-web-factory-demo-adapter` as:

- primary web-first demo adapter for the factory business-analyst agent on `Moltis`
- a thin browser-facing layer over the already implemented discovery and factory runtimes
- a practical near-term demo surface for constrained corporate environments, not a full portal rewrite
